"""Construit les SVG normatifs et les états de l'atlas sans dépendance externe.

Les PNG livrés sont des rendus de ces SVG. L'atlas illustre des trajectoires sans
simuler de tirs ou produire de mesures humaines. Voir README du kit.
"""
from __future__ import annotations
import base64
import copy
import html
import json
import math
from math import sin, cos, tan, asin, radians, degrees, pi
from pathlib import Path
from geometrie_reference import *
from mouvements_reference import *

BASE=Path(__file__).resolve().parents[1]
OUT=BASE/'visuels';OUT.mkdir(exist_ok=True)
CAT=json.load(open(BASE/'donnees/catalogue.v2.json'))
THEME=json.load(open(BASE/'donnees/interface.theme.json'))
COL={'bg':'#0B1119','surface':'#121D29','raised':'#1B2A3A','border':'#314252',
     'text':'#F2F6FA','secondary':'#A9BACB','wall':'#18212B','floor':'#202A35',
     'seam':'#344250','teal':'#42D9CB','amber':'#FFB454','muted':'#77899B',
     'success':'#81D6A5','caution':'#FFCA74'}
SLUG={'EX01':'acquisition','EX02':'multicibles','EX03':'temporisees','EX04':'clic_mobile',
      'EX05':'suivi_fluide','EX06':'suivi_reactif','EX07':'controle_3d','EX08':'transitions'}
DESCRIPTIONS={
 'EX01':'Trouver le centre. Corriger finement. Étendre le geste.',
 'EX02':'Choisir une cible, puis enchaîner sans perdre la précision.',
 'EX03':'Lire une apparition imprévisible et agir dans une fenêtre limitée.',
 'EX04':'Intercepter une cible en mouvement, avec une pression par tir.',
 'EX05':'Rester sur la cible pendant un déplacement régulier.',
 'EX06':'Reprendre le suivi après des changements de direction.',
 'EX07':'Garder le contact quand distance et taille apparente évoluent.',
 'EX08':'Maintenir le tir, terminer une cible, puis transférer le geste.'}
PHASE_FR={'micro':'Micro-correction','general':'Acquisition générale','amplitude':'Grande amplitude',
 'grid':'Grille','precision':'Précision','fixed_window':'Fenêtre fixe','shrinking_window':'Rétrécissement',
 'linear':'Linéaire','evasive':'Esquive','arcs':'Arcs','horizontal':'Horizontal',
 'vertical':'Vertical','ellipse':'Ellipse','reactive':'Réactif','depth':'Profondeur',
 'static':'Statique','mobile':'Mobile'}
LEVEL={'novice':'Novice','standard':'Standard','advanced':'Avancé'}

def fmt(v):
    if isinstance(v,str):return v
    return (f'{v:.3f}'.rstrip('0').rstrip('.')).replace('.',',')
def esc(s):return html.escape(str(s),quote=True)
def rect(x,y,w,h,fill,rx=0,stroke=None,sw=1,opacity=None):
    extra=(f' stroke="{stroke}" stroke-width="{sw}"' if stroke else '')+(f' opacity="{opacity}"' if opacity is not None else '')
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}"{extra}/>'
def text(x,y,s,size=20,color=None,weight=400,anchor='start'):
    return f'<text x="{x}" y="{y}" font-family="DejaVu Sans" font-size="{size}" font-weight="{weight}" fill="{color or COL["text"]}" text-anchor="{anchor}">{esc(s)}</text>'
def line(x1,y1,x2,y2,color=None,width=1,dash=None):
    extra=f' stroke-dasharray="{dash}"' if dash else ''
    return f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{color or COL["border"]}" stroke-width="{width}"{extra}/>'
def path(points,color=None,width=2,fill='none',close=False,opacity=1):
    d='M '+' L '.join(f'{x:.4f} {y:.4f}' for x,y in points)+(' Z' if close else '')
    return f'<path d="{d}" fill="{fill}" stroke="{color or fill}" stroke-width="{width}" opacity="{opacity}" stroke-linejoin="round" stroke-linecap="round"/>'
def circle(x,y,r,color,stroke=None,width=1):
    return f'<circle cx="{x}" cy="{y}" r="{r}" fill="{color}"'+(f' stroke="{stroke}" stroke-width="{width}"' if stroke else '')+'/>'
def svg(body,w=1600,h=1400):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}"><title>AIM/LOCAL — référence visuelle V2</title>{body}</svg>'
def button(x,y,w,label,active=False,h=52):
    return rect(x,y,w,h,COL['teal'] if active else COL['raised'],10,COL['teal'] if active else COL['border'])+text(x+w/2,y+h/2+7,label,20,COL['bg'] if active else COL['text'],600,'middle')

def make_motion(program,phase,slot):
    seed=exercise_seed(CAT,program,phase,'motion',slot,0,'trajectory')
    motion=Motion(phase['motion'],seed,slot,horizon_s=phase['duration_s'])
    spec=phase['spawn'];kind=spec['kind']
    if kind in ('one_target_per_lane','one_target_per_chamber'):
        rng=XorShift32(exercise_seed(CAT,program,phase,'layout',slot,0,'candidate'))
        anchor=direction(*spec['initial_reference_yaw_pitch_deg']);minimum=spec['transition_angle_deg'][0]
        for _ in range(spec['random_candidate_limit']):
            if 'sample_cycle_fraction' in spec['coordinate_distribution']:
                motion.cycle=rng.uniform01()
            else:
                bounds=spec['chambers'][slot]['yaw_deg'] if kind=='one_target_per_chamber' else spec['candidate_yaw_deg']
                yaw=rng.uniform(*bounds)
                motion=Motion(phase['motion'],seed,slot,phase['duration_s'],yaw)
            h,v,_=motion.sample(0)
            if separation_deg(direction(h,v),anchor)>=minimum-1e-9:break
        else:raise ValueError('ILLUSTRATION_INITIAL_STATE_CONSTRAINT_FAILED')
    return motion

def serialize_motion(motion):
    state={k:v for k,v in vars(motion).items() if k not in ('rng','ellipse')}
    if hasattr(motion,'ellipse'):
        e=motion.ellipse;state['ellipse']={k:getattr(e,k) for k in ['a','b','n','h','prefix','length']}
    return state

CONFIGS=[]
for program in CAT['programs']:
    phases=[]
    for p in program['phases']:
        entry={'id':p['id'],'definition':p,'static_positions':[],'opportunities':[],'states':[]}
        if p['motion']['kind']=='static' and p['mechanic']!='opportunity':
            entry['static_positions']=static_layout(CAT,program,p)
        elif p['mechanic']=='opportunity':
            sch=p['spawn']['schedule'];previous=[]
            for i in range(sch['slots']):
                pos=static_layout(CAT,program,p,generation=i,previous=previous);previous=pos
                rng=XorShift32(exercise_seed(CAT,program,p,'timing',0,i,'onset'))
                onset=i*sch['slot_duration_s']+rng.uniform(*sch['onset_delay_uniform_s'])
                entry['opportunities'].append({'slot':i,'onset_s':us_round(onset),'deadline_s':us_round(onset+p['lifecycle']['ttl_s']),'yaw_pitch_deg':pos[0]})
        else:
            for slot in range(p['target_count']):entry['states'].append(serialize_motion(make_motion(program,p,slot)))
        phases.append(entry)
    CONFIGS.append({'program_id':program['program_id'],'difficulty':program['difficulty'],'title':program['title'],'phases':phases})

def rebuild_motion(state):
    obj=Motion.__new__(Motion)
    for k,v in state.items():
        if k!='ellipse':setattr(obj,k,v)
    if 'ellipse' in state:
        e=Ellipse.__new__(Ellipse)
        for k,v in state['ellipse'].items():setattr(e,k,v)
        obj.ellipse=e
    return obj

def targets_at(phase,t):
    p=phase['definition'];r=p['size']['world_radius_m'];d=p['distance_m']
    out=[]
    if p['mechanic']=='opportunity':
        for op in phase['opportunities']:
            if op['onset_s']<=t<op['deadline_s']:
                u=(t-op['onset_s'])/(op['deadline_s']-op['onset_s'])
                D=p['size']['diameter_start_deg']+(p['size']['diameter_end_deg']-p['size']['diameter_start_deg'])*u
                out.append((*op['yaw_pitch_deg'],d,radius_m(d,D),1-u))
    elif phase['states']:
        for state in phase['states']:
            h,v,dynamic_d=rebuild_motion(state).sample(t)
            out.append((h,v,dynamic_d if dynamic_d is not None else d,r,1.))
    else:
        out=[(*pos,d,r,1.) for pos in phase['static_positions']]
    return out

def arena(program,phase,t,hud=True,annotation=False):
    p=phase['definition'];global_t=p['start_s']+t;parts=[]
    parts.append(rect(0,0,1920,1080,COL['wall']))
    seam=540+(1080/(2*math.tan(math.radians(VFOV_DEG)/2)))*1.6/18
    parts.append(rect(0,seam,1920,1080-seam,COL['floor']))
    parts.append(line(0,seam,1920,seam,COL['seam'],1))
    for idx,(h,v,d,r,remaining) in enumerate(targets_at(phase,t)):
        pts=sphere_contour(h,v,d,r)
        parts.append(path(pts,fill=COL['teal'],width=0,close=True))
        if p['mechanic'] in ('switching','opportunity'):
            # Arc externe : aucun point n'entre dans le hitbox.
            arc=sphere_contour(h,v,d,d*math.sin(math.asin(r/d)*1.2),n=128)
            # Le premier point de sphere_contour est à gauche ; décaler au haut.
            arc=arc[32:]+arc[:32];count=max(2,math.ceil(len(arc)*remaining))
            parts.append(path(arc[:count],COL['amber'],2,close=remaining>=.99999))
    parts.append(circle(960,540,2,'#071018'))
    parts.append(circle(960,540,1,COL['text']))
    if hud:
        parts.append(text(32,47,program['title'],24,weight=600))
        parts.append(text(32,74,LEVEL[program['difficulty']]+' · 60 s',17,COL['secondary']))
        idx=next(i for i,q in enumerate(program['phases']) if q['id']==phase['id'])
        parts.append(text(960,55,f'{idx+1}/{len(program["phases"])}  {PHASE_FR[phase["id"]]}',20,anchor='middle'))
        remain=max(0,math.ceil(60-global_t));parts.append(text(1888,60,f'{remain//60:02}:{remain%60:02}',34,weight=600,anchor='end'))
        parts.append(rect(1696,82,192,4,COL['border'],2))
        parts.append(rect(1696,82,192*max(0,1-t/p['duration_s']),4,COL['teal'],2))
        label={'click':'0 touche · 0 tir','opportunity':'0 réussite · 0 tir','tracking':'Contact  —','switching':'0 cible terminée'}[p['mechanic']]
        parts.append(text(32,1002,label,20,weight=600))
        parts.append(text(32,1032,'Vue sans entrée de démonstration',17,COL['secondary']))
        helptext={'click':'Clic gauche : tirer   ·   Échap : pause','opportunity':'Attendez la cible, puis cliquez   ·   Échap : pause',
            'tracking':'Gardez le viseur sur la cible   ·   Échap : pause','switching':'Maintenez le clic pour tirer   ·   Échap : pause'}[p['mechanic']]
        parts.append(text(960,1036,helptext,17,COL['secondary'],anchor='middle'))
    return ''.join(parts)

def phase_summary(p):
    m=p['motion'];k=m['kind']
    base=f'{p["target_count"]} cible'+('s' if p['target_count']>1 else '')+f' · Ø {fmt(p["diameter_deg"])}°'
    if k=='static':
        if p['mechanic']=='opportunity':return base+f' · fenêtre {fmt(p["lifecycle"]["ttl_s"])} s'
        if p['mechanic']=='switching':return base+' · remplacement à PV épuisés'
        return base+' · remplacement sur impact'
    if k=='linear_reflect':return base+f' · {fmt(m["yaw_speed_deg_s"])}°/s'
    if k.startswith('reactive'):return base+f' · {fmt(m["yaw_speed_abs_deg_s"][0])}–{fmt(m["yaw_speed_abs_deg_s"][1])}°/s'
    if k=='angular_bounce':return base+f' · vol {fmt(m["flight_duration_s"])} s'
    if k=='sinusoid_axis':return base+f' · pic {fmt(m["peak_angular_speed_deg_s"])}°/s'
    if k=='angular_ellipse':return base+f' · {fmt(m["path_angular_speed_deg_s"])}°/s'
    if k=='depth_sines':return base+f' à 4 m · {fmt(m["distance_center_m"]-m["distance_amplitude_m"])}–{fmt(m["distance_center_m"]+m["distance_amplitude_m"])} m'
    return base

def angular_diagram(phase,x,y,w,h):
    p=phase['definition'];parts=[rect(x,y,w,h,COL['surface'],10,COL['border'])]
    if p['mechanic']=='opportunity':
        op=phase['opportunities'][0];left=x+24;right=x+w-24;barw=right-left
        parts.append(text(left,y+24,'Un créneau de 3 s · exemple programmé',12,COL['secondary']))
        parts.append(rect(left,y+38,barw,10,COL['raised'],4))
        parts.append(rect(left+barw*op['onset_s']/3,y+38,barw*(op['deadline_s']-op['onset_s'])/3,10,COL['teal'],4))
        parts.append(text(left,y+67,'0',11,COL['secondary']))
        parts.append(text(right,y+67,'3 s',11,COL['secondary'],anchor='end'))
        parts.append(text(left+barw*op['onset_s']/3,y+67,fmt(op['onset_s'])+' s',11,COL['teal']))
        for i,fraction in enumerate([0,.5,1]):
            D=p['size']['diameter_start_deg']+(p['size']['diameter_end_deg']-p['size']['diameter_start_deg'])*fraction
            cx=left+barw*(i+.5)/3
            parts.append(circle(cx,y+108,D*6,COL['teal']))
            parts.append(text(cx,y+147,['Début','Milieu','Fin'][i]+' · '+fmt(D)+'°',12,COL['secondary'],anchor='middle'))
        parts.append(text(x+10,y+h-10,'Schéma de durée et de taille · sphères agrandies',11,COL['secondary']))
        return ''.join(parts)
    if p['motion']['kind']=='reactive_axis':
        mo=rebuild_motion(phase['states'][0]);m=p['motion'];duration=6.
        regions=[(x+38,y+36,w-62,h-67,'Position yaw / temps',24,False)]
        if w>800:
            regions=[(x+45,y+36,w/2-76,h-68,'Yaw ±24° · seuils de bord ±21°',24,False),
                     (x+w/2+30,y+36,w/2-60,h-68,'Vitesse de yaw · rampes conservant la continuité',m['yaw_speed_abs_deg_s'][1],True)]
        for rx,ry,rw,rh,title,limit,velocity in regions:
            parts.append(text(rx,ry-12,title,12,COL['secondary']))
            def Q(t,val):return rx+rw*t/duration,ry+rh/2-val/limit*(rh/2)
            parts.append(line(*Q(0,0),*Q(duration,0),COL['border']))
            for bound in ([-21,21] if not velocity else [-limit,limit]):parts.append(line(*Q(0,bound),*Q(duration,bound),COL['border'],1,'4 4'))
            pts=[Q(i*duration/360,sample_reactive(mo.tape,i*duration/360)[1 if velocity else 0]) for i in range(361)]
            parts.append(path(pts,COL['teal'],2))
            for e in mo.tape['events']:
                t=e['time_us']/1e6
                if t<=duration and e['kind'].startswith('boundary'):
                    px,py=Q(t,sample_reactive(mo.tape,t)[1 if velocity else 0]);parts.append(circle(px,py,3,COL['amber']))
            parts.append(text(rx,ry+rh+15,'0 s',10,COL['secondary']))
            parts.append(text(rx+rw,ry+rh+15,'6 s',10,COL['secondary'],anchor='end'))
        parts.append(text(x+10,y+h-8,'Courbes explicatives · ambre : décision de demi-tour au bord',11,COL['secondary']))
        return ''.join(parts)
    if p['motion']['kind']=='depth_sines' and w>800:
        left_width=w*.48
        parts.append(angular_diagram(phase,x+14,y+14,left_width-24,h-30))
        for i,dist in enumerate([3,4,5]):
            D=diameter_deg(dist,p['size']['world_radius_m']);cx=x+left_width+(w-left_width)*(i+.5)/3
            parts.append(circle(cx,y+72,D*10,COL['teal']))
            parts.append(text(cx,y+131,fmt(dist)+' m · Ø '+fmt(D)+'°',17,COL['secondary'],anchor='middle'))
        parts.append(text(x+left_width+16,y+h-13,'Même rayon physique · tailles apparentes agrandies pour la comparaison',12,COL['secondary']))
        return ''.join(parts)
    margin=18;hscale=(w-2*margin)/84;vscale=(h-2*margin)/40
    scale=min(hscale,vscale);cx=x+w/2;cy=y+h/2
    def P(a,b):return cx+a*scale,cy-b*scale
    parts.append(line(*P(-40,0),*P(40,0),COL['border'],1))
    parts.append(line(*P(0,-18),*P(0,18),COL['border'],1))
    bounds=p['envelope'];H=bounds['center_yaw_deg'];V=bounds['center_pitch_deg']
    if H[1]-H[0]>0 and V[1]-V[0]>0:
        pts=[P(H[0],V[0]),P(H[1],V[0]),P(H[1],V[1]),P(H[0],V[1])]
        parts.append(path(pts,COL['border'],1,close=True))
    if p['spawn']['kind']=='grid_without_overlap':
        for a in p['spawn']['nodes_yaw_pitch_deg']:
            px,py=P(*a);parts.append(circle(px,py,2,'none',COL['muted'],1))
    if 'annulus' in p['spawn']['coordinate_distribution'] and p['target_count']==1:
        clipid='clip_'+p['id']+'_'+str(x).replace('.','_')+'_'+str(y).replace('.','_')
        px,py=P(H[0],V[1]);parts.append(f'<defs><clipPath id="{clipid}">{rect(px,py,(H[1]-H[0])*scale,(V[1]-V[0])*scale,"white")}</clipPath></defs>')
        rings=[]
        for amp in p['spawn']['transition_angle_deg']:
            points=[]
            for i in range(129):
                q=TAU*i/128;a=math.radians(amp)
                hh,vv=angles((math.sin(a)*math.cos(q),math.sin(a)*math.sin(q),-math.cos(a)))
                points.append(P(hh,vv))
            rings.append(path(points,COL['amber'],1,opacity=.45))
        parts.append(f'<g clip-path="url(#{clipid})">'+''.join(rings)+'</g>')
    if phase['states']:
        for state in phase['states']:
            mo=rebuild_motion(state);dur=min(p['duration_s'],2.6 if p['motion']['kind'] in ('angular_bounce','reactive_lanes') else 12)
            pts=[P(*mo.sample(i*dur/160)[:2]) for i in range(161)]
            parts.append(path(pts,COL['teal'],1.5,opacity=.65))
            px,py=P(*mo.sample(0)[:2]);parts.append(circle(px,py,3,COL['teal']))
    elif phase['opportunities']:
        points=[op['yaw_pitch_deg'] for op in phase['opportunities'][:4]]
        parts.append(path([P(*a) for a in points],COL['border'],1.5))
        for i,a in enumerate(points):
            px,py=P(*a);parts.append(circle(px,py,max(3,p['diameter_deg']*scale/2),COL['teal']))
            parts.append(text(px+9,py-9,i+1,12,COL['secondary']))
    else:
        for i,a in enumerate(phase['static_positions']):
            px,py=P(*a);parts.append(circle(px,py,max(2,p['diameter_deg']*scale/2),COL['teal']))
        if p['target_count']==1:
            parts.append(path([P(0,0),P(*phase['static_positions'][0])],COL['amber'],1.5))
    parts.append(circle(cx,cy,1.5,COL['secondary']))
    parts.append(text(x+10,y+h-10,'Plan angulaire · annotations hors jeu',11,COL['secondary']))
    return ''.join(parts)

def board(program):
    pid=program['program_id'];parts=[rect(0,0,1600,1420,COL['bg'])]
    parts.append(text(32,37,'AIM/LOCAL  /  RÉFÉRENCE VISUELLE V2',14,COL['teal'],600))
    parts.append(text(32,84,pid+'  '+program['title'],36,weight=600))
    parts.append(text(32,114,DESCRIPTIONS[pid],18,COL['secondary']))
    selected={'EX01':1,'EX02':0,'EX03':1,'EX04':2,'EX05':2,'EX06':0,'EX07':0,'EX08':1}[pid]
    phase=program['phases'][selected];p=phase['definition'];t=2.35
    if phase['opportunities']:t=phase['opportunities'][0]['onset_s']+.45*p['lifecycle']['ttl_s']
    if pid=='EX07':t=min([i*.25 for i in range(240)],key=lambda z:targets_at(phase,z)[0][2])
    parts.append(f'<g transform="translate(32 136) scale(.8)">{arena(program,phase,t)}</g>')
    parts.append(text(32,1028,'Vue de jeu 16:9 · Niveau standard · FOV horizontal 103° · Œil à 1,60 m',17,COL['secondary']))
    parts.append(text(1568,1028,f'Instant {fmt(p["start_s"]+t)} s / 60 s',17,COL['secondary'],anchor='end'))
    n=len(program['phases']);gap=20;cw=(1536-gap*(n-1))/n
    for i,q in enumerate(program['phases']):
        x=32+i*(cw+gap);definition=q['definition']
        parts.append(text(x,1074,f'{fmt(definition["start_s"])}–{fmt(definition["start_s"]+definition["duration_s"])} s  ·  {PHASE_FR[q["id"]]}',20,weight=600))
        parts.append(angular_diagram(q,x,1091,cw,186))
        parts.append(text(x,1307,phase_summary(definition),15,COL['secondary']))
    levels=[q for q in CAT['programs'] if q['program_id']==pid]
    leveltext='    |    '.join(LEVEL[q['difficulty']]+': '+', '.join('Ø'+fmt(ph['diameter_deg'])+'°' for ph in q['phases']) for q in levels)
    parts.append(line(32,1330,1568,1330))
    parts.append(text(32,1359,leveltext,15,COL['secondary']))
    parts.append(text(32,1395,'Sphères et caméra à l’échelle. Tracés, numéros et enveloppes explicatifs ne sont pas affichés pendant la mesure.',15,COL['secondary']))
    (OUT/f'{pid}_{SLUG[pid]}.svg').write_text(svg(''.join(parts),1600,1420),encoding='utf-8')
    (OUT/f'{pid}_vue_jeu.svg').write_text(svg(arena(program,phase,t),1920,1080),encoding='utf-8')

def sidebar(active='Entraînement'):
    s=rect(0,0,1920,1080,COL['bg'])+rect(0,0,232,1080,COL['surface'])
    s+=text(28,61,'AIM/LOCAL',28,weight=600)+text(28,90,'ENTRAÎNEZ LE GESTE',12,COL['secondary'])
    for i,label in enumerate(['Entraînement','Calibration','Historique','Réglages']):
        y=153+i*67
        if label==active:s+=rect(16,y,200,51,COL['raised'],9)+rect(16,y+13,3,25,COL['teal'],1)
        s+=text(34,y+33,label,19,COL['text'] if label==active else COL['secondary'],600 if label==active else 400)
    s+=circle(35,1009,5,COL['teal'])+text(51,1015,'Disponible hors ligne',14,COL['secondary'])+text(28,1052,'Windows · profil local',14,COL['secondary'])
    return s

def catalogue_ui():
    s=sidebar()+text(272,72,'Entraînement',42,weight=600)
    s+=text(272,113,'8 programmes · 60 secondes chacun · des résultats par geste',20,COL['secondary'])
    s+=button(1324,52,170,'Novice')+button(1506,52,178,'Standard',True)+button(1696,52,192,'Avancé')
    s+=rect(272,148,1616,48,COL['surface'],9)+text(292,179,'Profil général    ·    35,0 cm/360    ·    800 DPI    ·    Difficulté fixée pendant la séance',17,COL['secondary'])
    for i,program in enumerate(q for q in CONFIGS if q['difficulty']=='standard'):
        x=272+(i%4)*410;y=222+(i//4)*372;w=386;h=348
        s+=rect(x,y,w,h,COL['surface'],14,COL['border'])
        s+=text(x+20,y+34,program['program_id'],14,COL['teal'],600)
        s+=text(x+20,y+70,program['title'],26,weight=600)
        s+=angular_diagram(program['phases'][0],x+18,y+89,w-36,130)
        short={'EX01':'Micro → Général → Amplitude','EX02':'Grille → Précision','EX03':'Fenêtre fixe → Rétrécissement','EX04':'Linéaire → Esquive → Arcs','EX05':'Horizontal → Vertical → Ellipse','EX06':'Réactif','EX07':'Profondeur','EX08':'Statique → Mobile → Esquive'}
        s+=text(x+20,y+249,short[program['program_id']],14,COL['secondary'])
        mechanic=program['phases'][0]['definition']['mechanic']
        s+=text(x+20,y+280,{'click':'Clic','opportunity':'Apparition et timing','tracking':'Suivi','switching':'Dégâts continus'}[mechanic]+' · 60 s',16,COL['secondary'])
        s+=button(x+20,y+299,w-40,'Préparer',False,34)
    s+=text(272,1020,'Une phase se termine avant que la suivante commence. Les résultats conservent cette séparation.',17,COL['secondary'])
    return s

def preparation_ui():
    program=next(x for x in CONFIGS if x['program_id']=='EX04' and x['difficulty']=='standard')
    s=sidebar()+text(272,66,'Préparer · Clic mobile',38,weight=600)
    s+=text(272,110,'Interceptez chaque cible avec une pression de souris.',22,COL['secondary'])
    s+=rect(272,151,1616,560,COL['surface'],14,COL['border'])
    for i,phase in enumerate(program['phases']):
        x=296+i*531
        s+=text(x,198,f'{i+1:02}  {PHASE_FR[phase["id"]]}',25,weight=600)
        s+=angular_diagram(phase,x,225,493,295)
        s+=text(x,562,f'{i*20}–{i*20+20} secondes',22,COL['teal'],600)
        rows={'linear':['Mouvement horizontal régulier.','Visez le passage dans le viseur.'],
              'evasive':['Changements de direction adoucis.','Attendez un tir propre après la reprise.'],
              'arcs':['Rebonds dans quatre zones séparées.','Suivez le sommet puis la descente.']}[phase['id']]
        for j,row in enumerate(rows):s+=text(x,607+j*32,row,19,COL['secondary'])
    s+=rect(272,744,1010,200,COL['surface'],12,COL['border'])+text(298,786,'Avant de commencer',25,weight=600)
    s+=text(298,831,'4 cibles · niveau standard · 60 s · même sensibilité',21,COL['secondary'])
    s+=text(298,872,'Le clic de ce bouton ne comptera pas comme un tir.',19,COL['secondary'])
    s+=text(298,910,'Un décompte de 3 secondes prépare le départ.',19,COL['secondary'])
    s+=button(1310,744,578,'Démarrer la séance',True,74)
    s+=button(1310,841,578,'Retour au catalogue',False,58)
    s+=text(272,1018,'Clic gauche : un tir par pression    ·    Échap : suspendre    ·    Aucune assistance de visée',17,COL['secondary'])
    return s

def result_exercise_ui():
    s=sidebar('Historique')+text(272,70,'Acquisition · séance terminée',38,weight=600)
    s+=text(272,114,'Les trois gestes sont présentés séparément.',22,COL['secondary'])
    samples=[('Micro-correction','0–20 s','54','91,5 %','231 ms'),('Acquisition générale','20–40 s','46','88,5 %','299 ms'),('Grande amplitude','40–60 s','35','85,4 %','391 ms')]
    for i,(title,time,hits,acc,lat) in enumerate(samples):
        x=272+i*547
        s+=rect(x,170,522,390,COL['surface'],14,COL['border'])
        s+=text(x+26,219,title,27,weight=600)+text(x+26,255,time,18,COL['secondary'])
        s+=text(x+26,327,hits,62,COL['teal'],600)+text(x+26,360,'cibles touchées',20,COL['secondary'])
        s+=line(x+26,387,x+496,387)+text(x+26,430,'Précision',20,COL['secondary'])+text(x+496,430,acc,25,anchor='end')
        s+=text(x+26,487,'Acquisition médiane',20,COL['secondary'])+text(x+496,487,lat,25,anchor='end')
    s+=rect(272,597,1616,189,COL['surface'],14,COL['border'])+text(300,643,'Lecture de cette séance',25,weight=600)
    s+=text(300,686,'Les grandes amplitudes ont demandé davantage de temps. Travaillez la reprise de précision après le déplacement.',20,COL['secondary'])
    s+=text(300,729,'Comparez chaque phase à vos séances dans les mêmes conditions.',20,COL['secondary'])
    s+=button(272,836,350,'Recommencer',True,62)+button(646,836,360,'Voir les essais',False,62)+button(1030,836,390,'Exporter le rapport',False,62)
    s+=text(272,978,'Données fictives pour la maquette · ne pas intégrer ces nombres comme résultats par défaut.',17,COL['caution'])
    return s

def calibration_plan_ui():
    s=sidebar('Calibration')+text(272,69,'Trouver un réglage qui vous convient',38,weight=600)
    s+=text(272,112,'Un réglage constant pendant chaque bloc. Une confirmation sur deux jours.',21,COL['secondary'])
    s+=rect(272,153,1616,104,COL['surface'],12,COL['border'])+text(298,195,'Votre point de départ',20,COL['secondary'])
    s+=text(298,234,'35,0 cm/360    ·    800 DPI    ·    Profil général',27,weight=600)
    s+=button(1560,182,298,'Vérifier le réglage',False,48)
    cards=[('01','Exploration','11 min 36 s','Comparer trois réglages','28,0 · 35,0 · 43,75 cm/360'),
           ('02','Confirmation · jour 1','16 min 48 s','Comparer votre réglage et le candidat','Quatre blocs avec des pauses'),
           ('03','Confirmation · jour 2','16 min 48 s','Reprendre la comparaison un autre jour','Ordre inversé et nouveaux parcours')]
    for i,(n,title,duration,body,small) in enumerate(cards):
        x=272+i*547
        s+=rect(x,298,522,354,COL['surface'],14,COL['border'])+text(x+27,339,n,17,COL['teal'],600)
        s+=text(x+27,389,title,26,weight=600)+text(x+27,441,duration,36,COL['teal'],600)
        s+=text(x+27,502,body,19,COL['secondary'])+text(x+27,548,small,18,COL['secondary'])
        s+=text(x+27,607,'4 gestes : clic, fluide, réactif, transitions',16,COL['secondary'])
    s+=rect(272,690,1616,138,COL['surface'],12,COL['border'])+text(298,732,'Ce que vous obtenez',23,weight=600)
    s+=text(298,772,'Un candidat, puis un résultat par geste et par jour. Si les résultats sont trop proches ou divergents,',20,COL['secondary'])
    s+=text(298,806,'l’application vous le dira et conservera votre réglage comme choix par défaut.',20,COL['secondary'])
    s+=button(272,869,520,'Commencer l’exploration',True,66)+button(820,869,370,'Reprendre un protocole',False,66)
    s+=text(272,1006,'Prévoyez de la place pour déplacer la souris. Vous pouvez arrêter et conserver une séance incomplète.',18,COL['secondary'])
    return s

def calibration_active_ui():
    program=next(x for x in CONFIGS if x['program_id']=='EX06' and x['difficulty']=='standard')
    phase=program['phases'][0];s=arena(program,phase,9.5,hud=False)
    s+=text(32,46,'Calibration · Jour 1',24,weight=600)+text(32,76,'Bloc 2/4 · Mesure 3/4',17,COL['secondary'])
    s+=text(960,55,'Suivi réactif',22,anchor='middle')
    s+=text(1888,60,'00:15',34,weight=600,anchor='end')
    s+=rect(1696,82,192,4,COL['border'],2)+rect(1696,82,116,4,COL['teal'],2)
    s+=text(960,1028,'Gardez le viseur sur la cible. Le réglage reste constant pendant ce bloc.',18,COL['secondary'],anchor='middle')
    s+=text(32,1038,'Échap : arrêter',17,COL['secondary'])
    return s

def calibration_result_ui():
    s=sidebar('Calibration')+text(272,70,'Un avantage retrouvé sur deux séances',38,weight=600)
    s+=text(272,114,'Résultat conditionnel à votre profil général et aux exercices testés.',21,COL['secondary'])
    s+=rect(272,158,620,302,COL['surface'],14,COL['border'])+text(302,204,'Candidat recommandé',21,COL['secondary'])
    s+=text(302,282,'28,00',62,COL['teal'],600)+text(518,279,'cm/360',25,COL['secondary'])
    s+=text(302,334,'Réglage actuel : 35,0 cm/360',21,COL['secondary'])+text(302,384,'Déplacement plus court pour une même rotation.',18,COL['secondary'])
    s+=text(302,423,'800 DPI · gain : 0,0408214° par unité relative',17,COL['secondary'])
    s+=rect(922,158,966,302,COL['surface'],14,COL['border'])+text(952,204,'Différence de l’indice composite · points',23,weight=600)
    rows=[('Jour 1','+3,08 pt',.615),('Jour 2','+3,20 pt',.64)]
    for i,(label,val,f) in enumerate(rows):
        y=260+i*76;s+=text(952,y,label,21,COL['secondary'])+rect(1086,y-23,590,26,COL['raised'],6)+rect(1086,y-23,590*f,26,COL['teal'],6)+text(1828,y,val,25,anchor='end')
    s+=text(952,386,'Échelle : 0 à 5 points',15,COL['secondary'])
    s+=text(952,425,'Avantage observé après la courte prise en main prévue.',17,COL['secondary'])
    s+=rect(272,497,1616,260,COL['surface'],14,COL['border'])+text(300,541,'Vérification par geste',25,weight=600)
    for i,(name,a,b) in enumerate([('Clic','+2,9 pt','+2,9 pt'),('Suivi fluide','+2,7 pt','+2,9 pt'),('Suivi réactif','+4,6 pt','+4,9 pt'),('Transitions','+2,1 pt','+2,1 pt')]):
        x=300+i*392;s+=text(x,592,name,22,weight=600)+text(x,635,'Jour 1   '+a,20,COL['teal'])+text(x,674,'Jour 2   '+b,20,COL['teal'])
    s+=text(300,727,'Pour chaque réglage : 60/64 réussites au clic et 44/48 cibles terminées en transfert.',19,COL['secondary'])
    s+=button(272,800,458,'Appliquer ce candidat',True,64)+button(754,800,458,'Conserver mon réglage',False,64)+button(1236,800,390,'Exporter les données',False,64)
    s+=text(272,930,'Essayez ensuite ce réglage dans votre jeu habituel. Vous pourrez revenir à votre réglage précédent.',20,COL['secondary'])
    s+=text(272,998,'Données fictives pour la maquette · le texte réel dépend exclusivement du moteur de décision.',17,COL['caution'])
    return s

def mechanics_board():
    s=rect(0,0,1600,1280,COL['bg'])+text(48,60,'CIBLES · CE QUI CHANGE ET CE QUI RESTE FIXE',17,COL['teal'],600)
    s+=text(48,116,'États et transformations',40,weight=600)
    s+=text(48,156,'Schémas agrandis pour lire la mécanique · aucune de ces annotations ne masque l’arène mesurée.',19,COL['secondary'])
    panels=[(48,196,736,472),(808,196,744,472),(48,692,736,522),(808,692,744,522)]
    for x,y,w,h in panels:s+=rect(x,y,w,h,COL['surface'],14,COL['border'])
    s+=text(78,241,'01 · Une fenêtre, une issue',26,weight=600)
    s+=text(78,278,'EX03 Standard · slot 3 s · apparition illustrée à 1 s',18,COL['secondary'])
    x0=108;yw=340;wide=580
    s+=line(x0,yw,x0+wide,yw,COL['border'],5)+line(x0+wide/3,yw,x0+wide*2.1/3,yw,COL['teal'],7)
    for t,label in [(0,'0'),(1,'1,00'),(2.1,'2,10'),(3,'3,00 s')]:
        px=x0+wide*t/3;s+=line(px,yw-9,px,yw+9,COL['secondary'],1)+text(px,yw+36,label,17,COL['secondary'],anchor='middle')
    for px,r,label in [(192,44,'2,40°'),(416,35.2,'1,92°'),(640,26.4,'1,44°')]:
        s+=circle(px,467,r,COL['teal'])+text(px,540,label,21,anchor='middle')
    s+=text(78,590,'Diamètre angulaire : début → milieu → limite finale.',18,COL['secondary'])
    s+=text(78,624,'Un hit retire la cible ; un miss ne réinitialise pas le slot.',18,COL['secondary'])
    s+=text(838,241,'02 · Les PV diminuent, pas le corps',26,weight=600)
    s+=text(838,278,'EX08 Standard · 40 PV · 100 dégâts/s au contact',18,COL['secondary'])
    for px,fraction,label in [(936,1,'40 / 40 PV'),(1180,.5,'20 / 40 PV'),(1424,.75,'30 / 40 PV')]:
        s+=circle(px,420,43,COL['teal'])
        pts=[(px+52*cos(-pi/2+2*pi*fraction*i/100),420+52*sin(-pi/2+2*pi*fraction*i/100)) for i in range(101)]
        s+=path(pts,COL['amber'],3)+text(px,521,label,20,anchor='middle')
    s+=text(838,590,'Le contour ambré montre les PV restants, hors hitbox.',18,COL['secondary'])
    s+=text(838,624,'Travail : 1 destruction + 20/40 + 10/40 = 1,75 unité.',18,COL['secondary'])
    s+=text(78,737,'03 · La profondeur modifie la perspective',26,weight=600)
    s+=text(78,778,'EX07 Standard · rayon physique constant ≈ 9,08 cm',18,COL['secondary'])
    radius=4*sin(radians(2.6/2)); ds=[3,4,5]
    for px,d in zip([192,416,640],ds):
        dia=degrees(2*asin(radius/d));r=48*(tan(asin(radius/d))/tan(asin(radius/4)))
        s+=circle(px,932,r,COL['teal'])+text(px,1036,fmt(d)+' m',21,weight=600,anchor='middle')+text(px,1074,fmt(dia)+'°',20,COL['secondary'],anchor='middle')
    s+=text(78,1141,'À gauche la cible est plus proche, elle paraît plus grande.',18,COL['secondary'])
    s+=text(78,1177,'Aucun rétrécissement commandé par l’âge ou les dégâts.',18,COL['secondary'])
    s+=text(838,737,'04 · Une nouvelle identité après destruction',26,weight=600)
    s+=text(838,778,'EX02 · un seul slot remplacé ; ses voisines restent en place',18,COL['secondary'])
    for px,py in [(929,929),(1203,883)]:s+=circle(px,py,26,COL['teal'])
    s+=circle(1081,977,26,'none',COL['secondary'],2)+line(1061,957,1101,997,COL['secondary'],2)+line(1061,997,1101,957,COL['secondary'],2)
    s+=line(1115,967,1369,901,COL['amber'],2)+circle(1405,893,26,COL['teal'])
    s+=text(1058,1040,'ancienne',17,COL['secondary'])+text(1362,949,'nouvelle',17,COL['amber'])
    s+=text(838,1101,'Tirages indépendants du viseur, séparation avec les vivantes.',18,COL['secondary'])
    s+=text(838,1141,'La nouvelle génération doit être rendue avant de recevoir',18,COL['secondary'])
    s+=text(838,1177,'un impact. L’effet de disparition n’a aucune collision.',18,COL['secondary'])
    s+=text(48,1250,'Règle commune : la silhouette active et la sphère du hitscan ont exactement le même centre et le même rayon.',18,COL['secondary'])
    return svg(s,1600,1280)

def write_outputs():
    for program in CONFIGS:
        if program['difficulty']=='standard':board(program)
    screens=[('00_vue_ensemble',catalogue_ui),('UI02_preparation',preparation_ui),('UI03_resultats_exercice',result_exercise_ui),
       ('UI04_calibration_parcours',calibration_plan_ui),('UI05_calibration_mesure',calibration_active_ui),('UI06_calibration_resultat',calibration_result_ui)]
    for name,fn in screens:(OUT/(name+'.svg')).write_text(svg(fn(),1920,1080),encoding='utf-8')
    (OUT/'M01_cibles_et_etats.svg').write_text(mechanics_board(),encoding='utf-8')
    payload={'version':'aimlocal.atlas.v2','compiler_version':COMPILER_VERSION,'theme':THEME,'configs':CONFIGS,
        'scope':'Geometry and motion without firing or human scoring. Logical onset times. Exact analytic sampler; no live RNG.'}
    (BASE/'donnees/atlas.etats.json').write_text(json.dumps(payload,ensure_ascii=False,separators=(',',':'),allow_nan=False),encoding='utf-8')
    shell=(BASE/'outils/atlas_shell.html').read_text(encoding='utf-8')
    font1=base64.b64encode((BASE/'assets/fonts/DejaVuSans.ttf').read_bytes()).decode('ascii')
    font2=base64.b64encode((BASE/'assets/fonts/DejaVuSans-Bold.ttf').read_bytes()).decode('ascii')
    shell=shell.replace('__FONT_NORMAL__',font1).replace('__FONT_BOLD__',font2)
    shell=shell.replace('__ATLAS_DATA__',json.dumps(payload,ensure_ascii=False,separators=(',',':'),allow_nan=False).replace('</','<\\/'))
    (BASE/'ATLAS_EXERCICES_V2.html').write_text(shell,encoding='utf-8')
    print(json.dumps({'configurations':len(CONFIGS),'phases':sum(len(x['phases']) for x in CONFIGS),'svg_count':len(list(OUT.glob('*.svg'))),'atlas_bytes':(BASE/'ATLAS_EXERCICES_V2.html').stat().st_size}))

if __name__=='__main__':write_outputs()
