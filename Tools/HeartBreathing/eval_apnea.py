"""Breathing-disturbance screen on PhysioNet Apnea-ECG. Usage: eval_apnea.py clean|noisy <half-widths> <record prefixes: abc (released) or x (withheld)>"""
import sys, zlib
SEED=int(__import__('os').environ.get('NOISE_SEED','0'))
import sys, os, numpy as np, wfdb, pn, acat, afdet
from concurrent.futures import ProcessPoolExecutor
P=os.path.join(pn.P,'apnea-ecg')
INFO={}
for line in open(os.path.join(pn.P,'apnea-ecg','additional-information.txt')):
    p=line.split()
    if p and len(p[0])==3 and p[0][0] in 'abc' and p[0][1:].isdigit() and len(p)>7: INFO[p[0]]=float(p[7])
def run(args):
    rec,noisy,half=args
    acat.SG_HALF=half
    q=wfdb.rdann(os.path.join(P,rec),'qrs'); fs=q.fs or 100
    bt=np.array(q.sample)/fs; t=bt[1:]; rr=np.diff(bt)
    if noisy:
        ok=(rr>0.25)&(rr<2.5)
        t,rr=afdet.strapify(t[ok],rr[ok],np.random.default_rng(zlib.crc32(rec.encode())+1000*SEED))
    dips,hours,_=acat.detect(t,rr*1000)
    a=wfdb.rdann(os.path.join(P,rec),'apn'); lab=np.array([s=='A' for s in a.symbol])
    mins=len(lab)
    dm=np.zeros(mins,bool); idx=(dips//60).astype(int); dm[idx[idx<mins]]=True
    return rec, len(dips)/max(hours,1e-6), hours, lab.mean()*60, lab, dm
if __name__=='__main__':
    noisy=sys.argv[1]=='noisy'; halves=[int(x) for x in sys.argv[2].split(',')]; subset=sys.argv[3]
    recs=[r for r in sorted(set(f.split('.')[0] for f in os.listdir(P) if f.endswith('.apn'))) if r[0] in subset]
    for h in halves:
        with ProcessPoolExecutor(10) as ex: R=list(ex.map(run,[(r,noisy,h) for r in recs]))
        fcv=np.array([r[1] for r in R]); apm=np.array([r[3] for r in R])  # apnea minutes per hour
        ahi=np.array([INFO.get(r[0],np.nan) for r in R])
        from itertools import product
        def auc(score,pos):
            p=score[pos]; n=score[~pos]
            return np.mean([(a>b)+0.5*(a==b) for a,b in product(p,n)]) if len(p) and len(n) else np.nan
        # classes by apnea minutes (challenge def): A >=100 apnea min, C < 5
        totA=np.array([r[4].sum() for r in R])
        posA=totA>=100; negC=totA<5
        sel=posA|negC
        lab=np.concatenate([r[4] for r in R]); dm=np.concatenate([r[5] for r in R])
        acc=np.mean(lab==dm); se=np.mean(dm[lab]); sp=np.mean(~dm[~lab])
        line=f"half={h:2d} noisy={noisy} n={len(R)} r(Fcv,apnea-min/h)={np.corrcoef(fcv,apm)[0,1]:.2f} AUC A-vs-C={auc(fcv[sel],posA[sel]):.3f} minute acc {100*acc:.1f} (Se {100*se:.1f} Sp {100*sp:.1f})"
        if not np.isnan(ahi).all():
            m=~np.isnan(ahi); line+=f" | r(Fcv,AHI)={np.corrcoef(fcv[m],ahi[m])[0,1]:.2f} AUC AHI>=15={auc(fcv[m],ahi[m]>=15):.3f}"
        print(line)
        if len(halves)==1:
            for r,a in zip(R,ahi): print(f"   {r[0]} Fcv {r[1]:5.1f}/h  apnea-min/h {r[3]:5.1f}  AHI {a}")
