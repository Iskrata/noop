"""AP-1 prototype: Hayano ACAT cyclic-variation-of-heart-rate detector.
Steps (Hayano 2011/2020/2022): smooth R-R by 2nd-order polynomial fitting; dips 10-120 s wide with
depth/width > 0.7 ms/s; relative depth > 40% of the 130-s 5-95th percentile envelope; cycle 25-130 s;
mean morphological correlation with 2 preceding + 2 following dips > 0.4; 3 cycle lengths between 4
consecutive dips with (3-2L1/s)(3-2L2/s)(3-2L3/s) > 0.8. Fcv = CVHR dips per analysed hour.
Written with direct Swift twins in mind (no scipy)."""
import numpy as np
FS=1.0            # resample rate (Hz)
SG_HALF=5         # polynomial window half-width (s) -> tuned
MIN_W,MAX_W=10,120
RATIO=0.7         # ms/s
ENV_WIN=130; REL=0.40
CYC_MIN,CYC_MAX=25,130
MORPH_HALF=30; MORPH_R=0.4
EQUIV=0.8
MAX_GAP=10

def clean_rr(t, rr):
    """t beat times (s), rr ms. drop implausible, replace >20% local-median deviations (artifact/ectopy)."""
    ok=(rr>=300)&(rr<=2000); t,rr=t[ok],rr[ok]
    n=len(rr); med=np.empty(n)
    for i in range(n):
        med[i]=np.median(rr[max(0,i-5):i+6])
    good=np.abs(rr-med)<=0.2*med
    return t[good], rr[good]

def resample(t, rr):
    """1 Hz grid; grid points inside a >MAX_GAP-s hole are NaN."""
    g=np.arange(np.ceil(t[0]), np.floor(t[-1])+1, 1/FS)
    y=np.interp(g,t,rr)
    j=np.searchsorted(t,g); j=np.clip(j,1,len(t)-1)
    hole=(t[j]-t[j-1])>MAX_GAP
    y[hole]=np.nan
    return g,y

def sg_quadratic(y, h=None):
    """Savitzky-Golay smoothing, 2nd order, window 2h+1: closed-form weights; NaN-propagating."""
    h=h or SG_HALF
    m=2*h+1; k=np.arange(-h,h+1)
    # SG quadratic smoothing weights (central point)
    w=(3*(3*m*m-7-20*k*k))/(4*m*(m*m-4))
    out=np.full_like(y,np.nan)
    for i in range(h,len(y)-h):
        seg=y[i-h:i+h+1]
        if not np.isnan(seg).any(): out[i]=np.dot(w,seg)
    return out

def local_extrema(s):
    mins=[];maxs=[]
    for i in range(1,len(s)-1):
        a,b,c=s[i-1],s[i],s[i+1]
        if np.isnan(a) or np.isnan(b) or np.isnan(c): continue
        if b<a and b<=c: mins.append(i)
        elif b>a and b>=c: maxs.append(i)
    return np.array(mins,int),np.array(maxs,int)

def envelope(y, i, half=ENV_WIN//2):
    seg=y[max(0,i-half):i+half+1]; seg=seg[~np.isnan(seg)]
    if len(seg)<10: return np.nan
    return np.percentile(seg,95)-np.percentile(seg,5)

def detect(t, rr, still_mask=None):
    """returns (dip_times, analysed_hours, candidate_times)."""
    t,rr=clean_rr(t,rr)
    if len(rr)<200: return np.array([]),0.0,np.array([])
    g,y=resample(t,rr)
    if still_mask is not None: y[~still_mask(g)]=np.nan
    s=sg_quadratic(y)
    mins,maxs=local_extrema(s)
    cand=[]
    for m in mins:
        L=maxs[maxs<m]; R=maxs[maxs>m]
        if len(L)==0 or len(R)==0: continue
        l,r=L[-1],R[0]
        if np.isnan(s[l:r+1]).any(): continue
        w=(r-l)/FS
        if not (MIN_W<=w<=MAX_W): continue
        depth=min(s[l],s[r])-s[m]
        if depth/w<=RATIO: continue
        env=envelope(y,m)
        if not (env>0) or depth<REL*env: continue
        cand.append(m)
    cand=np.array(cand,int)
    acc=np.zeros(len(cand),bool)
    def seg(i):
        a=cand[i]-MORPH_HALF; b=cand[i]+MORPH_HALF+1
        if a<0 or b>len(s): return None
        x=s[a:b]
        return None if np.isnan(x).any() else x
    segs=[seg(i) for i in range(len(cand))]
    def corr(i,j):
        if segs[i] is None or segs[j] is None: return None
        return np.corrcoef(segs[i],segs[j])[0,1]
    ct=cand/FS
    for i in range(len(cand)):
        # morphology vs 2 preceding + 2 following
        cs=[corr(i,j) for j in (i-2,i-1,i+1,i+2) if 0<=j<len(cand)]
        cs=[c for c in cs if c is not None and not np.isnan(c)]
        if len(cs)<2 or np.mean(cs)<=MORPH_R: continue
        # a 4-consecutive-dip group containing i with 25-130 s cycles and equivalence
        ok=False
        for st in range(i-3,i+1):
            if st<0 or st+3>=len(cand): continue
            L=np.diff(ct[st:st+4])
            if np.all((L>=CYC_MIN)&(L<=CYC_MAX)):
                sm=L.mean()
                if np.prod(3-2*L/sm)>EQUIV: ok=True; break
        acc[i]=ok
    hours=np.sum(~np.isnan(s))/FS/3600
    return g[cand[acc]], hours, g[cand]
