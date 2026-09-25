import numpy as np
def beat_times(ts):
    out=np.empty(len(ts)); prev=None; k=0
    for i,t in enumerate(ts):
        k = k+1 if t==prev else 0; prev=t; out[i]=t+0.25*k
    return out
def still_minutes(g):   # g: array ts,dynAccel
    m=(g[:,0]//60).astype(int); d={}
    for mm,v in zip(m,g[:,1]):
        if not np.isnan(v): d[mm]=max(d.get(mm,0.0),v)
    return {k for k,v in d.items() if v<0.1}
