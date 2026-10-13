"""AIM-CANON-1 : encodage typé portable pour empreintes sémantiques.

Distinct du SHA-256 des octets du fichier. Sans dépendance externe.
Tous les nombres JSON sont encodés en IEEE754 binary64, -0 normalisé à +0.
Les identités/graines restent des chaînes ; les µs échangées restent <=2^53-1.
"""
import hashlib
import json
import math
import struct

VERSION='AIM-CANON-1'
MAX_SAFE_INTEGER=(1<<53)-1

def _u32(n):
    if not 0<=n<=0xffffffff:raise ValueError('CANON_LENGTH_RANGE')
    return struct.pack('>I',n)

def encode(value):
    if value is None:return b'Z'
    if value is False:return b'F'
    if value is True:return b'T'
    if isinstance(value,(int,float)) and not isinstance(value,bool):
        if isinstance(value,int) and abs(value)>MAX_SAFE_INTEGER:raise ValueError('CANON_UNSAFE_INTEGER')
        x=float(value)
        if not math.isfinite(x):raise ValueError('CANON_NONFINITE')
        if x==0:x=0.
        return b'N'+struct.pack('>d',x)
    if isinstance(value,str):
        b=value.encode('utf-8',errors='strict')
        return b'S'+_u32(len(b))+b
    if isinstance(value,list):return b'A'+_u32(len(value))+b''.join(encode(v) for v in value)
    if isinstance(value,dict):
        if any(not isinstance(k,str) for k in value):raise ValueError('CANON_NONSTRING_KEY')
        keys=sorted(value,key=lambda k:k.encode('utf-8'))
        return b'O'+_u32(len(keys))+b''.join(encode(k)+encode(value[k]) for k in keys)
    raise ValueError('CANON_UNSUPPORTED_TYPE')

def semantic_sha256(value):
    return hashlib.sha256(VERSION.encode('ascii')+b'\0'+encode(value)).hexdigest()

def strict_pairs(pairs):
    out={}
    for key,value in pairs:
        if key in out:raise ValueError('DUPLICATE_JSON_KEY:'+key)
        out[key]=value
    return out

def strict_loads(text):
    def bad(x):raise ValueError('NONFINITE_JSON:'+x)
    return json.loads(text,object_pairs_hook=strict_pairs,parse_constant=bad)

def fixture_set():
    inputs=[None,True,False,0,-0.,1,1.,.1,'é',[1,'1',None],{'b':2,'a':1},
            {'gain':914.4/(800*35),'seed':'0000000000000000000000000000002a','time_us':24000000}]
    return [{'input':v,'encoded_hex':encode(v).hex(),'semantic_sha256':semantic_sha256(v)} for v in inputs]

if __name__=='__main__':
    assert semantic_sha256(1)==semantic_sha256(1.)
    assert semantic_sha256(-0.)==semantic_sha256(0)
    assert semantic_sha256({'b':2,'a':1})==semantic_sha256({'a':1.,'b':2.})
    assert semantic_sha256([1,2])!=semantic_sha256([2,1])
    print(json.dumps({'version':VERSION,'fixtures':fixture_set()},ensure_ascii=False,indent=2))
