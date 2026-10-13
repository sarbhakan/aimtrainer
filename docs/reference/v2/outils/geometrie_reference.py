"""Référence numérique de conception, Python 3 standard uniquement.

Ces fonctions servent à contrôler les unités et à produire les figures du kit.
Elles ne constituent ni le moteur Godot ni un prérequis chez le joueur final.
"""
from __future__ import annotations

import hashlib
import json
import math

TAU = 2 * math.pi
HFOV_DEG = 103.0
VFOV_DEG = math.degrees(2 * math.atan(math.tan(math.radians(HFOV_DEG)/2)/(16/9)))
EYE_HEIGHT_M = 1.6


def dot(a, b):
    return sum(x*y for x,y in zip(a,b))


def cross(a, b):
    return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])


def norm(v):
    return math.sqrt(dot(v,v))


def unit(v):
    n=norm(v)
    if n<=1e-15:
        raise ValueError('ZERO_DIRECTION')
    return tuple(x/n for x in v)


def direction(yaw_deg, pitch_deg):
    h,v=math.radians(yaw_deg),math.radians(pitch_deg)
    return (math.cos(v)*math.sin(h), math.sin(v), -math.cos(v)*math.cos(h))


def angles(u):
    u=unit(u)
    return math.degrees(math.atan2(u[0],-u[2])), math.degrees(math.asin(max(-1,min(1,u[1]))))


def separation_deg(a, b):
    return math.degrees(math.atan2(norm(cross(a,b)),dot(a,b)))


def radius_m(distance_m, diameter_deg):
    if not 0<diameter_deg<180 or distance_m<=0:
        raise ValueError('INVALID_SPHERE')
    return distance_m*math.sin(math.radians(diameter_deg)/2)


def diameter_deg(distance_m, r_m):
    if not 0<r_m<distance_m:
        raise ValueError('EYE_INSIDE_SPHERE')
    return math.degrees(2*math.asin(r_m/distance_m))


def project_direction(u, width=1920, height=1080, vfov_deg=VFOV_DEG):
    if u[2]>=-1e-12:
        raise ValueError('POINT_BEHIND_CAMERA')
    f=height/(2*math.tan(math.radians(vfov_deg)/2))
    return width/2+f*u[0]/(-u[2]),height/2-f*u[1]/(-u[2])


def sphere_contour(yaw_deg, pitch_deg, distance_m, r_m, width=1920, height=1080, n=128):
    """Projection du cône tangent : silhouette exacte avant échantillonnage.

    Le contour hors axe n'est pas un cercle de diamètre_px centré en project(C).
    """
    u=direction(yaw_deg,pitch_deg)
    e1=unit(cross((0,1,0),u))
    e2=unit(cross(u,e1))
    rho=math.asin(r_m/distance_m)
    c,s=math.cos(rho),math.sin(rho)
    points=[]
    for i in range(n):
        t=TAU*i/n
        w=tuple(c*u[k]+s*(math.cos(t)*e1[k]+math.sin(t)*e2[k]) for k in range(3))
        points.append(project_direction(w,width,height))
    return points


def visible_sphere(yaw_deg,pitch_deg,distance_m,r_m,angular_margin_deg=2,physical_margin_m=.005):
    u=direction(yaw_deg,pitch_deg)
    C=tuple(distance_m*x for x in u)
    h=math.radians(HFOV_DEG/2-angular_margin_deg)
    v=math.radians(VFOV_DEG/2-angular_margin_deg)
    planes=[((math.cos(h),0,-math.sin(h)),0),((-math.cos(h),0,-math.sin(h)),0),
            ((0,math.cos(v),-math.sin(v)),0),((0,-math.cos(v),-math.sin(v)),0),
            ((0,0,-1),-.05),((0,0,1),100)]
    return EYE_HEIGHT_M+C[1]-r_m>=.05 and all(dot(n,C)+d>=r_m+physical_margin_m for n,d in planes)


def smoothstep(u):
    u=max(0,min(1,u))
    return u*u*(3-2*u)


def signed_ramp(v0,v1,duration_s,t):
    """Retourne vitesse et déplacement ; unités deg/s, s, deg."""
    if duration_s<=0:
        raise ValueError('RAMP_DURATION_NONPOSITIVE')
    t=max(0,min(duration_s,t));u=t/duration_s
    return v0+(v1-v0)*smoothstep(u),v0*t+(v1-v0)*duration_s*(u**3-.5*u**4)


def ramp_duration(v0,v1,nominal_s,max_accel):
    return max(nominal_s,1.5*abs(v1-v0)/max_accel)


def cm360_from_gain(dpi,gain):
    if dpi<=0 or gain<=0:
        raise ValueError('INVALID_GAIN_OR_DPI')
    return 914.4/(dpi*gain)


class XorShift32:
    def __init__(self,seed):
        self.state=(int(seed)&0xffffffff) or 0x6D2B79F5

    def next_u32(self):
        x=self.state
        x=(x^(x<<13))&0xffffffff
        x=(x^(x>>17))&0xffffffff
        x=(x^(x<<5))&0xffffffff
        self.state=x
        return x

    def uniform01(self):
        return (self.next_u32()+.5)/4294967296

    def uniform(self,low,high):
        if low>high:raise ValueError('INVERTED_RANGE')
        return low+(high-low)*self.uniform01()

    def index(self,n):
        if not 1<=n<=4294967296:raise ValueError('INVALID_INDEX_BOUND')
        limit=(4294967296//n)*n
        while True:
            x=self.next_u32()
            if x<limit:return x%n

    def shuffle(self,items):
        out=list(items)
        for i in range(len(out)-1,0,-1):
            j=self.index(i+1);out[i],out[j]=out[j],out[i]
        return out


def stream_seed(parts):
    encoded=json.dumps(parts,ensure_ascii=False,separators=(',',':'),allow_nan=False).encode('utf-8')
    return int.from_bytes(hashlib.sha256(encoded).digest()[:4],'big') or 0x6D2B79F5


def sample_rectangle(rng,yaw_range,pitch_range):
    h=rng.uniform(*yaw_range)
    lo,hi=(math.sin(math.radians(x)) for x in pitch_range)
    v=math.degrees(math.asin(rng.uniform(lo,hi)))
    return h,v


def sample_annulus(rng,origin_angles,amplitude_range):
    origin=direction(*origin_angles)
    e1=unit(cross((0,1,0),origin));e2=unit(cross(origin,e1))
    a,b=map(math.radians,amplitude_range)
    c=rng.uniform(math.cos(b),math.cos(a));s=math.sqrt(max(0,1-c*c))
    theta=TAU*rng.uniform01()
    u=tuple(c*origin[k]+s*(math.cos(theta)*e1[k]+math.sin(theta)*e2[k]) for k in range(3))
    return angles(u)


if __name__=='__main__':
    rng=XorShift32(1)
    assert abs(VFOV_DEG-70.53280043291679)<1e-10
    assert abs(cm360_from_gain(800,914.4/(800*35))-35)<1e-10
    print(json.dumps({'vfov_deg':VFOV_DEG,'point_10_7_px':project_direction(direction(10,7)),
        'sphere_r_4deg_4m':radius_m(4,4),'rng_seed1_first5':[rng.next_u32() for _ in range(5)]},indent=2))
