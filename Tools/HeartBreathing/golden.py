import numpy as np, math, afdet as D, acat
acat.SG_HALF=10
M=(1<<64)-1
class LCG:
    def __init__(s,seed): s.x=seed
    def u(s):
        s.x=(s.x*6364136223846793005+1442695040888963407)&M
        return (s.x>>11)/float(1<<53)
T0=1_790_000_040.0
def build(parts):
    t=T0; ts=[]; rr=[]
    for p in parts:
        for r in p: t+=r; ts.append(t); rr.append(r)
    return np.array(ts),np.array(rr)
def sinus(minutes,t=[0.0]):
    out=[]; acc=0.0
    while acc<minutes*60:
        r=0.9+0.04*math.sin(2*math.pi*acc/4.0); out.append(r); acc+=r
    return out
def irregular(minutes,g):
    out=[]; acc=0.0
    while acc<minutes*60:
        r=0.45+0.6*g.u(); out.append(r); acc+=r
    return out
def bigeminy(minutes):
    out=[]; acc=0.0; i=0
    while acc<minutes*60:
        r=0.6 if i%2==0 else 1.1; out.append(r); acc+=r; i+=1
    return out
def report(name,t,rr):
    f=D.detect(t,rr); st,m0=D.minutes(t,f)
    print(name,'flags',int(f.sum()),'readable',int((st>=0).sum()),'irregular',int((st==1).sum()),'episodes',[(m0+a,m0+b,c) for a,b,c in D.episodes(st)])
t,rr=build([sinus(30),irregular(60,LCG(42)),sinus(30)]); report('sinus-af-sinus',t,rr)
t,rr=build([bigeminy(60)]); report('bigeminy',t,rr)
# CVHR
def cvhr(hours_cyc,hours_flat):
    ts=[];rs=[]; t=T0; acc=0.0
    while acc<(hours_cyc+hours_flat)*3600:
        p=acc%55.0
        if acc<hours_cyc*3600:
            if p<40: b=150*p/40
            elif p<45: b=150-350*(p-40)/5
            else: b=-200+200*(p-45)/10
        else: b=0.0
        r=1000+30*math.sin(2*math.pi*acc/4.0)+b
        acc+=r/1000; ts.append(T0+acc); rs.append(r)
    return np.array(ts),np.array(rs)
t,r=cvhr(1,1); d,h,_=acat.detect(t,r)
print('cvhr dips',len(d),'hours %.6f'%h,'first',d[:3].tolist())
