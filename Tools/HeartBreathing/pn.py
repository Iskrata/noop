"""Load PhysioNet beat annotations into (beat_time_s, rr_s, is_af) arrays."""
import wfdb, numpy as np, os
P=os.environ.get('PHYSIONET_DIR', os.path.join(os.path.dirname(os.path.abspath(__file__)),'physionet'))
BEATS=set('NLRBAaJSVrFejnE/fQ?')
def load(db, rec, beat_ext, rhythm_ext=None):
    a=wfdb.rdann(os.path.join(P,db,rec), beat_ext)
    fs=a.fs or wfdb.rdheader(os.path.join(P,db,rec)).fs
    samp=np.array(a.sample); sym=np.array(a.symbol); aux=np.array(a.aux_note)
    if rhythm_ext and rhythm_ext!=beat_ext:
        r=wfdb.rdann(os.path.join(P,db,rec), rhythm_ext); rs=np.array(r.sample); raux=np.array(r.aux_note)
    else:
        m=np.array([s=='+' for s in sym]); rs=samp[m]; raux=aux[m]
    bm=np.array([s in BEATS for s in sym]); bs=samp[bm]
    # rhythm per beat
    lab=np.zeros(len(bs),bool)
    if len(rs):
        idx=np.searchsorted(rs,bs,side='right')-1
        cur=np.array([raux[i].strip('\x00').strip() if i>=0 else '' for i in idx])
        lab=np.char.startswith(cur,'(AFIB')|np.char.startswith(cur,'(AF')&~np.char.startswith(cur,'(AFL')
    t=bs/fs
    rr=np.diff(t); t=t[1:]; lab=lab[1:]
    return t, rr, lab
