"""Irregular-rhythm screen on PhysioNet AF/NSR/arrhythmia annotations. Usage: eval_afib.py clean|noisy"""
import sys, zlib
SEED=int(__import__('os').environ.get('NOISE_SEED','0'))
import sys, numpy as np, pn, afdet as D, os
from concurrent.futures import ProcessPoolExecutor
def recs(db): return [r.strip() for r in open(os.path.join(pn.P,db,'RECORDS')) if r.strip()]
SETS={'ltafdb':('atr',None),'afdb':('qrs','atr'),'mitdb':('atr',None),'nsr2db':('ecg',None)}
def run(args):
    db,rec,noisy=args
    be,re_=SETS[db]
    try: t,rr,lab=pn.load(db,rec,be,re_)
    except Exception as e:
        print('SKIP',db,rec,e); return None
    ok=(rr>0.25)&(rr<2.5); t,rr,lab=t[ok],rr[ok],lab[ok]
    if noisy:
        rng=np.random.default_rng(zlib.crc32(rec.encode())+1000*SEED)
        nt,nrr=D.strapify(t,rr,rng)
        lab=lab[np.clip(np.searchsorted(t,nt),0,len(t)-1)]; t,rr=nt,nrr
    flag=D.detect(t,rr)
    st,m0=D.minutes(t,flag); gt,_=D.minutes(t,lab)
    both=(st>=0)&(gt>=0)
    tp=np.sum((st==1)&(gt==1)&both); fp=np.sum((st==1)&(gt==0)&both); fn=np.sum((st==0)&(gt==1)&both); tn=np.sum((st==0)&(gt==0)&both)
    eps=D.episodes(st); geps=D.episodes(gt)
    hit=any(any(a<=g1 and b>=g0 for (g0,g1,_) in geps) for (a,b,_) in eps)
    false_eps=sum(1 for (a,b,c) in eps if not any(a<=g1 and b>=g0 for (g0,g1,_) in geps))
    hours=(t[-1]-t[0])/3600
    burden_true=np.mean(gt[gt>=0]==1); burden_det=np.mean(st[st>=0]==1)
    return dict(db=db,rec=rec,tp=tp,fp=fp,fn=fn,tn=tn,beat_se=np.mean(flag[lab]) if lab.any() else np.nan,
                beat_sp=np.mean(~flag[~lab]) if (~lab).any() else np.nan,has_af=len(geps)>0,hit=hit,false_eps=false_eps,
                hours=hours,bt=burden_true,bd=burden_det)
if __name__=='__main__':
    noisy=sys.argv[1]=='noisy'
    jobs=[(db,r,noisy) for db in SETS for r in recs(db)]
    with ProcessPoolExecutor(10) as ex: res=[r for r in ex.map(run,jobs) if r]
    for db in SETS:
        R=[r for r in res if r['db']==db]
        tp=sum(r['tp'] for r in R); fp=sum(r['fp'] for r in R); fn=sum(r['fn'] for r in R); tn=sum(r['tn'] for r in R)
        se=tp/max(1,tp+fn); sp=tn/max(1,tn+fp)
        bse=np.nanmean([r['beat_se'] for r in R]); bsp=np.nanmean([r['beat_sp'] for r in R])
        pos=[r for r in R if r['has_af']]; neg=[r for r in R if not r['has_af']]
        fe=sum(r['false_eps'] for r in R); hrs=sum(r['hours'] for r in R)
        berr=[abs(r['bd']-r['bt'])*100 for r in R]
        print(f"{db:7s} n={len(R):3d} minute Se {100*se:5.1f} Sp {100*sp:5.1f} | beat Se {100*bse:5.1f} Sp {100*bsp:5.1f} | records w/ AF>=30min {len(pos)}: detected {sum(r['hit'] for r in pos)} | no-AF records {len(neg)} falsely alerted {sum(1 for r in neg if r['false_eps']>0)} | false episodes {fe} over {hrs:.0f} h | burden |err| median {np.median(berr):.1f} p90 {np.percentile(berr,90):.1f} pts")
