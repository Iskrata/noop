"""AF-1 prototype: Petrenas 2015 low-complexity detector + minute/episode aggregation.
Written so every step has a direct Swift twin (no scipy): EMA forward-backward with first-sample init."""
import numpy as np
ALPHA=0.02; N=8; GAMMA=0.03; DELTA=2e-4; ETA=0.725

def fb_ema(x, a=ALPHA):
    y=np.empty_like(x); acc=x[0]
    for i,v in enumerate(x): acc=(1-a)*acc+a*v; y[i]=acc
    z=np.empty_like(y); acc=y[-1]
    for i in range(len(y)-1,-1,-1): acc=(1-a)*acc+a*y[i]; z[i]=acc
    return z

def med3(r):
    rm=r.copy()
    rm[1:-1]=np.median(np.stack([r[:-2],r[1:-1],r[2:]]),axis=0)
    return rm

def petrenas(r):
    """r: RR seconds of ONE contiguous segment. Returns decision O and AF flag per beat."""
    n=len(r)
    if n<N+2: return np.zeros(n), np.zeros(n,bool)
    rm=med3(r); rt=fb_ema(r)
    M=np.zeros(n)
    for j in range(N-1):
        for k in range(j+1,N):
            a=np.full(n,np.nan); b=np.full(n,np.nan)
            a[j:]=rm[:n-j] if j else rm; b[k:]=rm[:n-k]
            M+=np.nan_to_num((np.abs(a-b)>=GAMMA).astype(float)*(~np.isnan(a)&~np.isnan(b)))
    M*=2/(N*(N-1))
    It=fb_ema(M)/rt
    cs_m=np.cumsum(np.r_[0,rm]); cs_r=np.cumsum(np.r_[0,r])
    idx=np.arange(n); st=np.maximum(0,idx-(N-1))
    B=((cs_m[idx+1]-cs_m[st])/(cs_r[idx+1]-cs_r[st])-1)**2
    Bt=fb_ema(B)
    O=np.where(Bt>=DELTA,It,Bt)
    return O, O>ETA

def segments(t, rr, maxgap=10.0):
    """split where wall-clock gap between beats exceeds rr+maxgap (missing data)."""
    brk=np.where(np.diff(t)-rr[1:]>maxgap)[0]+1
    return np.split(np.arange(len(rr)),brk)

def detect(t, rr):
    flag=np.zeros(len(rr),bool)
    for seg in segments(t,rr):
        _,f=petrenas(rr[seg]); flag[seg]=f
    return flag

MIN_BEATS_PER_MIN=20
def minutes(t, flag, valid=None):
    """per-minute state: 1=AF (>50% beats flagged), 0=not AF, -1=unanalysable."""
    if valid is None: valid=np.ones(len(t),bool)
    m=(t//60).astype(int); m0=m.min(); m-=m0; K=m.max()+1
    nb=np.bincount(m[valid],minlength=K); na=np.bincount(m[valid&flag],minlength=K)
    st=np.full(K,-1); ok=nb>=MIN_BEATS_PER_MIN; st[ok]=(na[ok]/nb[ok]>0.5).astype(int)
    return st, m0

EPISODE_MIN=30; MAX_BREAK=3
def episodes(st):
    """runs of AF minutes; unanalysable minutes are neutral; <=MAX_BREAK non-AF minutes bridged.
    Episode kept if it has >= EPISODE_MIN AF minutes."""
    eps=[]; cur=None; brk=0
    for i,s in enumerate(st):
        if s==1:
            if cur is None: cur=[i,i,0]
            cur[1]=i; cur[2]+=1; brk=0
        elif s==0 and cur is not None:
            brk+=1
            if brk>MAX_BREAK: 
                if cur[2]>=EPISODE_MIN: eps.append(tuple(cur))
                cur=None; brk=0
    if cur is not None and cur[2]>=EPISODE_MIN: eps.append(tuple(cur))
    return eps

def strapify(t, rr, rng):
    """inject the measured WHOOP-5 R-R artifact profile into clean ECG beats."""
    bt=np.r_[t[0]-rr[0], t].copy()
    bt[1:]+=rng.normal(0,0.010,len(t))                       # PPG timing jitter ~10 ms
    k=rng.random(len(t))<0.05                                 # 5% misplaced peaks
    sh=rng.uniform(0.2,0.5,len(t))*rng.choice([-1,1],len(t))*rr
    bt[1:][k]+=sh[k]
    bt=np.sort(bt)
    drop=rng.random(len(bt))<0.0014; bt=bt[~drop]              # merged beats
    add=rng.random(len(bt)-1)<0.004
    extra=(bt[:-1][add]+bt[1:][add])/2; bt=np.sort(np.r_[bt,extra])  # split beats
    nt=bt[1:]; nrr=np.diff(bt)
    keep=np.ones(len(nt),bool)                                 # ~64 gaps (10-60 s) per 8 h
    ng=int(64*(nt[-1]-nt[0])/28800)
    for g0 in rng.uniform(nt[0],nt[-1],ng):
        keep&=~((nt>=g0)&(nt<g0+rng.uniform(10,60)))
    ok=keep&(nrr>0.3)&(nrr<2.0)
    return nt[ok], nrr[ok]
