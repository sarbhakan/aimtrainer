"""Primitives déterministes de référence pour le dossier AIM/LOCAL V2.

Python standard. Conception et vérification uniquement : aucune dépendance joueur.
Ce module ne simule ni l'entrée souris, ni les collisions, ni un moteur de jeu.
Versionner ensemble ce code, les paramètres et les fixtures numériques.
"""
from __future__ import annotations
import bisect
import copy
import hashlib
import json
import math
from pathlib import Path
from geometrie_reference import (XorShift32, stream_seed, TAU, signed_ramp,
    ramp_duration, sample_rectangle, sample_annulus, direction, separation_deg)

COMPILER_VERSION='motion_reference_v2.0'

def us_round(t):
    return math.floor(t*1_000_000+0.5)/1_000_000

def rng_child(seed, purpose):
    return XorShift32(stream_seed([COMPILER_VERSION,format(seed,'08x'),purpose]))

def reflected(x0,v,t,lo,hi):
    width=hi-lo
    q=(x0-lo+v*t)%(2*width)
    x=lo+q if q<=width else hi-(q-width)
    sign=1 if q<width else -1
    if abs(q)<1e-10:sign=1 if v>=0 else -1
    if abs(q-width)<1e-10:sign=-1 if v>=0 else 1
    return x,v*sign

def evaluate_piece(p,t):
    dt=max(0,t-p['origin_s'])
    if p['shape']=='constant':
        return p['x_origin_deg']+p['v0_deg_s']*dt,p['v0_deg_s']
    v,dx=signed_ramp(p['v0_deg_s'],p['v1_deg_s'],p['duration_s'],dt)
    return p['x_origin_deg']+dx,v

def _root_position(p,threshold,a,b):
    xa=evaluate_piece(p,a)[0]-threshold
    for _ in range(70):
        m=(a+b)/2;xm=evaluate_piece(p,m)[0]-threshold
        if abs(b-a)<1e-10:return m
        if xa*xm<=0:b=m
        else:a=m;xa=xm
    return (a+b)/2

def _velocity_zero(p,a,b):
    va=evaluate_piece(p,a)[1];vb=evaluate_piece(p,b)[1]
    if va*vb>=0:return None
    for _ in range(60):
        m=(a+b)/2;vm=evaluate_piece(p,m)[1]
        if va*vm<=0:b=m
        else:a=m;va=vm
    return (a+b)/2

def _first_crossing(p,threshold,desired_sign,a,b):
    """Première traversée d'un seuil sur portions de position monotones."""
    cut=_velocity_zero(p,a,b)
    stops=[a]+([cut] if cut is not None else [])+[b]
    for lo,hi in zip(stops,stops[1:]):
        if hi-lo<1e-12:continue
        xa,va=evaluate_piece(p,lo);xb,vb=evaluate_piece(p,hi)
        if desired_sign*(xb-xa)<=0:continue
        if desired_sign*(xa-threshold)<=1e-10 and desired_sign*(xb-threshold)>=0:
            root=_root_position(p,threshold,lo,hi)
            if root>a+1e-9:return root
    return None

def compile_reactive(motion,seed,horizon_s=60,initial_yaw_deg=None):
    """Compile une trajectoire réactive avant la mesure.

    RNG séparés initialization, events, vertical_phase ; tirages documentés dans
    README et exportés dans initial_state. Aucun appel RNG dans sample_reactive.
    Les événements sont quantifiés à la microseconde. Les rampes gardent leur
    origine même lorsqu'un événement de réarmement coupe leur intervalle.
    """
    m=motion;ri=rng_child(seed,'initialization');re=rng_child(seed,'events')
    rv=rng_child(seed,'vertical_phase')
    lo,hi=m['yaw_bounds_deg'];inset=m['boundary']['trigger_inset_deg']
    left,right=lo+inset,hi-inset
    x=ri.uniform(left,right)
    if initial_yaw_deg is not None:
        if not left-1e-9<=initial_yaw_deg<=right+1e-9:raise ValueError('INITIAL_YAW_OUTSIDE_SOFT_THRESHOLDS')
        x=initial_yaw_deg
    sign=1 if ri.uniform01()<m['initial_direction_prob_positive'] else -1
    last_speed=ri.uniform(*m['yaw_speed_abs_deg_s']);v=sign*last_speed
    vertical_phase=rv.uniform(0,TAU)
    def plateau_duration():
        u=re.uniform01();acc=0;selected=m['plateau_duration_mixture'][-1]
        for item in m['plateau_duration_mixture']:
            acc+=item['weight']
            if u<acc:selected=item;break
        return re.uniform(*selected['uniform_duration_s'])
    def constant(t,x,v):
        duration=max(.000001,us_round(plateau_duration()))
        return dict(shape='constant',origin_s=t,x_origin_deg=x,v0_deg_s=v,
            v1_deg_s=v,duration_s=duration),us_round(t+duration)
    def ramp(t,x,v,newv):
        spec=m['velocity_transition']
        duration=ramp_duration(v,newv,spec['nominal_duration_s'],spec['acceleration_limit_deg_s2'])
        # Le minimum accélération doit rester respecté après quantification.
        minimum=1.5*abs(newv-v)/spec['acceleration_limit_deg_s2']
        duration=max(us_round(duration),math.ceil(minimum*1e6)/1e6,.000001)
        return dict(shape='ramp',origin_s=t,x_origin_deg=x,v0_deg_s=v,
            v1_deg_s=newv,duration_s=duration),us_round(t+duration)
    initial=dict(yaw_deg=x,velocity_deg_s=v,vertical_phase_rad=vertical_phase)
    piece,control_end=constant(0,x,v);now=0.;armed=True;pieces=[];events=[];boundary_side=None
    if (x>=right-1e-10 and v>0) or (x<=left+1e-10 and v<0):
        kind='boundary_right' if v>0 else 'boundary_left'
        events.append(dict(time_us=0,kind=kind,yaw_deg=x,velocity_deg_s=v))
        piece,control_end=ramp(0,x,v,-last_speed if v>0 else last_speed)
        armed=False;boundary_side=kind
    for _ in range(10000):
        if now>=horizon_s-1e-9:break
        end=min(control_end,horizon_s);kind='control_end' if control_end<=horizon_s else 'end'
        threshold_candidates=[]
        if armed:
            for threshold,direction_sign,label in [(left,-1,'boundary_left'),(right,1,'boundary_right')]:
                r=_first_crossing(piece,threshold,direction_sign,now,end)
                if r is not None:threshold_candidates.append((r,label))
        else:
            xx,vv=evaluate_piece(piece,now)
            returning=(boundary_side=='boundary_right' and vv<0) or (boundary_side=='boundary_left' and vv>0)
            if left+1e-8<xx<right-1e-8 and returning:
                armed=True
                continue
            for threshold,direction_sign in [(left,1),(right,-1)]:
                r=_first_crossing(piece,threshold,direction_sign,now,end)
                if r is not None:threshold_candidates.append((r,'rearm'))
        if threshold_candidates:
            et,ek=min(threshold_candidates)
            et=min(end,max(now+.000001,us_round(et)))
            if et<=end+1e-9:end=et;kind=ek
        rec=copy.copy(piece);rec.update(from_s=now,to_s=end)
        pieces.append(rec)
        x,v=evaluate_piece(piece,end);now=end
        if now>=horizon_s-1e-9:break
        events.append(dict(time_us=round(now*1e6),kind=kind,yaw_deg=x,velocity_deg_s=v))
        if kind=='rearm':
            armed=True
            if abs(now-control_end)<.0000005:
                events[-1]['kind']='rearm_and_control_end'
                if piece['shape']=='ramp':
                    piece,control_end=constant(now,x,piece['v1_deg_s'])
                else:
                    sign=1 if v>=0 else -1
                    if re.uniform01()<m['direction_flip_probability']:sign=-sign
                    last_speed=re.uniform(*m['yaw_speed_abs_deg_s'])
                    piece,control_end=ramp(now,x,v,sign*last_speed)
        elif kind.startswith('boundary_'):
            newv=last_speed if kind=='boundary_left' else -last_speed
            piece,control_end=ramp(now,x,v,newv);armed=False;boundary_side=kind
        elif piece['shape']=='ramp':
            piece,control_end=constant(now,x,piece['v1_deg_s'])
        else:
            sign=1 if v>=0 else -1
            if re.uniform01()<m['direction_flip_probability']:sign=-sign
            last_speed=re.uniform(*m['yaw_speed_abs_deg_s'])
            piece,control_end=ramp(now,x,v,sign*last_speed)
    else:raise ValueError('REACTIVE_EVENT_LIMIT')
    if not pieces or abs(pieces[-1]['to_s']-horizon_s)>1e-6:raise ValueError('REACTIVE_TAPE_INCOMPLETE')
    return dict(compiler_version=COMPILER_VERSION,seed_u32=seed,horizon_s=horizon_s,
        initial_state=initial,pieces=pieces,events=events)

def sample_reactive(tape,t):
    t=max(0,min(tape['horizon_s'],t))
    stops=[p['to_s'] for p in tape['pieces']]
    i=min(len(stops)-1,bisect.bisect_right(stops,t))
    return evaluate_piece(tape['pieces'][i],t)

class Ellipse:
    def __init__(self,a_deg,b_deg,cells=4096):
        self.a=math.radians(a_deg);self.b=math.radians(b_deg);self.n=cells
        self.h=TAU/cells;self.prefix=[0.]
        for i in range(cells):self.prefix.append(self.prefix[-1]+self.integral(i*self.h,(i+1)*self.h))
        self.length=self.prefix[-1]
    def metric(self,q):
        return math.hypot(math.cos(self.b*math.sin(q))*(-self.a*math.sin(q)),self.b*math.cos(q))
    def integral(self,a,b):
        return (b-a)*(self.metric(a)+4*self.metric((a+b)/2)+self.metric(b))/6
    def parameter(self,arc):
        arc%=self.length;i=min(self.n-1,bisect.bisect_right(self.prefix,arc)-1)
        origin=i*self.h;lo=origin;hi=lo+self.h
        target=arc-self.prefix[i];q=lo+(hi-lo)*target/(self.prefix[i+1]-self.prefix[i])
        for _ in range(16):
            error=self.integral(origin,q)-target
            if abs(error)<1e-11:return q
            if error>0:hi=q
            else:lo=q
            candidate=q-error/self.metric(q)
            q=candidate if lo<candidate<hi else (lo+hi)/2
        if abs(self.integral(origin,q)-target)>1e-9:raise ValueError('ELLIPSE_INVERSION_DID_NOT_CONVERGE')
        return q

class Motion:
    """État immuable d'une génération de cible, échantillonnable à tout instant."""
    def __init__(self,motion,seed,slot=0,horizon_s=60,initial_yaw_deg=None):
        self.m=motion;self.kind=motion['kind'];self.seed=seed;self.slot=slot
        rng=rng_child(seed,'initialization');self.rng=rng
        self.phase=rng.uniform(0,TAU);self.sign=1 if rng.uniform01()<.5 else -1
        m=motion;k=self.kind
        if k in ('reactive_axis','reactive_lanes'):
            self.tape=compile_reactive(m,seed,horizon_s,initial_yaw_deg)
            self.phase=self.tape['initial_state']['vertical_phase_rad']
        elif k=='linear_reflect':
            lo,hi=m['yaw_bounds_deg']
            self.x0=rng.uniform(lo,hi)
            if initial_yaw_deg is not None:self.x0=initial_yaw_deg
            self.cycle=rng.uniform01()
        elif k=='angular_ellipse':
            self.ellipse=Ellipse(m['yaw_amplitude_deg'],m['pitch_amplitude_deg'],m['arc_length_solver']['lut_cells'])
            self.arc0=rng.uniform01()*self.ellipse.length
        elif k=='depth_sines':
            self.phases=[rng.uniform(0,TAU) for _ in range(3)]
        elif k=='angular_bounce':
            self.bounces=[];ch=m['chambers'][slot];lo,hi=ch['yaw_deg']
            x=rng.uniform(lo,hi)
            if initial_yaw_deg is not None:x=initial_yaw_deg
            v=self.sign*m['yaw_speed_deg_s'];age=rng.uniform(*m['initial_flight_age_uniform_s'])
            now=0;flight=True
            while now<horizon_s+1e-9:
                duration=m['flight_duration_s']-age if flight else rng.uniform(*m['ground_rest_uniform_s'])
                self.bounces.append(dict(start=now,end=now+duration,x=x,v=v,age=age,flight=flight))
                x,v=reflected(x,v,duration,lo,hi);now+=duration
                if flight:
                    if rng.uniform01()<m['landing_flip_probability']:v=-v
                    if abs(x-lo)<1e-8:v=abs(v)
                    if abs(x-hi)<1e-8:v=-abs(v)
                flight=not flight;age=0
    def sample(self,t):
        m=self.m;k=self.kind
        if k=='static':return 0.,0.,None
        if k in ('reactive_axis','reactive_lanes'):
            h,_=sample_reactive(self.tape,t);vert=m['vertical']
            v=m['lanes_pitch_deg'][self.slot]+vert['amplitude_deg']*math.sin(TAU*t/vert['period_s']+self.phase)
            return h,v,None
        if k=='sinusoid_axis':
            x=m['amplitude_deg']*math.sin(m['omega_rad_s']*t+self.phase)
            return (x,m['orthogonal_coordinate_deg'],None) if m['axis']=='yaw' else (m['orthogonal_coordinate_deg'],x,None)
        if k=='depth_sines':
            h=m['yaw_amplitude_deg']*math.sin(m['yaw_omega_rad_s']*t+self.phases[0])
            v=m['pitch_amplitude_deg']*math.sin(m['pitch_omega_rad_s']*t+self.phases[1])
            d=m['distance_center_m']+m['distance_amplitude_m']*math.sin(m['distance_omega_rad_s']*t+self.phases[2])
            return h,v,d
        if k=='angular_ellipse':
            q=self.ellipse.parameter(self.arc0+self.sign*math.radians(m['path_angular_speed_deg_s'])*t)
            return m['yaw_amplitude_deg']*math.cos(q),m['pitch_amplitude_deg']*math.sin(q),None
        if k=='linear_reflect':
            lo,hi=m['yaw_bounds_deg'];speed=m['yaw_speed_deg_s']
            if m['reflection']=='instantaneous_velocity_sign_change':
                h,_=reflected(self.x0,self.sign*speed,t,lo,hi)
            else:
                T=m['turn_duration_s'];inset=m['turn_entry_inset_deg']
                straight=m['straight_segment_duration_s'];period=2*(straight+T)
                tt=(t+self.cycle*period)%period
                if tt<straight:h=lo+inset+speed*tt
                elif tt<straight+T:h=hi-inset+signed_ramp(speed,-speed,T,tt-straight)[1]
                elif tt<2*straight+T:h=hi-inset-speed*(tt-straight-T)
                else:h=lo+inset+signed_ramp(-speed,speed,T,tt-2*straight-T)[1]
                if self.sign<0:h=lo+hi-h
            return h,m['lanes_pitch_deg'][self.slot],None
        if k=='angular_bounce':
            rec=self.bounces[min(len(self.bounces)-1,bisect.bisect_right([p['end'] for p in self.bounces],t))]
            ch=m['chambers'][self.slot];dt=max(0,t-rec['start'])
            h,_=reflected(rec['x'],rec['v'],dt,*ch['yaw_deg'])
            age=rec['age']+dt;u=max(0,min(1,age/m['flight_duration_s']))
            v=ch['baseline_pitch_deg']+(4*m['apex_height_above_baseline_deg']*u*(1-u) if rec['flight'] else 0)
            return h,v,None
        raise ValueError('UNKNOWN_MOTION_KIND:'+k)

def exercise_seed(catalogue,program,phase,domain,slot,generation,purpose):
    return stream_seed([catalogue['catalogue_revision'],catalogue['randomization']['illustrative_atlas_session_seed_hex'],
        program['program_id'],program['difficulty'],phase['id'],f'{domain}/{slot}/{generation}/{purpose}'])

def static_layout(catalogue,program,phase,generation=0,previous=None):
    """Placement d'une scène illustrative statique entière, sans tirs.

    PAS un spawner runtime de remplacement par slot. Celui-ci doit valider une
    nouvelle cible contre TOUTES les autres instances réellement vivantes, tout
    en préservant leurs états. Ici, generation change la scène illustrative
    entière ou l'opportunité unique d'EX03 ; voir contrat Markdown pour runtime.
    """
    spec=phase['spawn'];out=[];previous=previous or []
    if spec['kind']=='grid_without_overlap':
        rng=XorShift32(exercise_seed(catalogue,program,phase,'layout',0,generation,'grid'))
        return [tuple(p) for p in rng.shuffle(spec['nodes_yaw_pitch_deg'])[:phase['target_count']]]
    for slot in range(phase['target_count']):
        seed=exercise_seed(catalogue,program,phase,'layout',slot,generation,'candidate')
        rng=XorShift32(seed);anchor=previous[slot] if slot<len(previous) else tuple(spec['initial_reference_yaw_pitch_deg'])
        band=spec['transition_angle_deg']
        bag=spec.get('transition_band_bag')
        if bag:
            cycle,idx=divmod(generation,bag['draw_count'])
            rb=XorShift32(exercise_seed(catalogue,program,phase,'layout',slot,cycle,'band_bag'))
            entries=[b['angle_deg'] for b in bag['bands'] for _ in range(b['copies'])]
            band=rb.shuffle(entries)[idx]
        def valid(p):
            h,v=p
            if not spec['yaw_deg'][0]<=h<=spec['yaw_deg'][1] or not spec['pitch_deg'][0]<=v<=spec['pitch_deg'][1]:return False
            a=separation_deg(direction(*p),direction(*anchor))
            if not band[0]-1e-9<=a<=band[1]+1e-9:return False
            gap=phase['diameter_deg']+spec['minimum_silhouette_gap_deg']
            return all(separation_deg(direction(*p),direction(*q))>=gap-1e-9 for q in out)
        chosen=None
        for _ in range(spec['random_candidate_limit']):
            p=sample_annulus(rng,anchor,band) if 'annulus' in spec['coordinate_distribution'] else sample_rectangle(rng,spec['yaw_deg'],spec['pitch_deg'])
            if valid(p):chosen=p;break
        if chosen is None:
            candidates=[];lo,hi=spec['yaw_deg'];bottom,top=spec['pitch_deg']
            for iy in range(round((hi-lo)/.25)+1):
                for ip in range(round((top-bottom)/.25)+1):
                    p=(lo+iy*.25,bottom+ip*.25)
                    if valid(p):
                        index=iy*(round((top-bottom)/.25)+1)+ip
                        parts=[catalogue['catalogue_revision'],catalogue['randomization']['illustrative_atlas_session_seed_hex'],
                            program['program_id'],program['difficulty'],phase['id'],f'layout/{slot}/{generation}/fallback_lattice_{index}']
                        digest=hashlib.sha256(json.dumps(parts,ensure_ascii=True,separators=(',',':')).encode('ascii')).digest()
                        candidates.append((digest,index,p))
            if not candidates:raise ValueError('SPAWN_CONSTRAINT_FAILURE')
            chosen=min(candidates)[2]
        out.append(chosen)
    return out

if __name__=='__main__':
    base=Path(__file__).resolve().parents[1]
    cat=json.load(open(base/'donnees/catalogue.v2.json'))
    spec=next(p for p in cat['programs'] if p['program_id']=='EX06' and p['difficulty']=='standard')
    tape=compile_reactive(spec['phases'][0]['motion'],42,60)
    report={'version':COMPILER_VERSION,'events':len(tape['events']),'samples':[{'t':t,'yaw_velocity':sample_reactive(tape,t)} for t in [0,1,5,20,59.999999]]}
    print(json.dumps(report,indent=2))
