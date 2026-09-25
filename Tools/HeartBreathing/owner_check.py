"""Run both screens over a copy of the app database (whoop.sqlite): irregular-rhythm minutes/episodes over the
whole history, and the breathing-disturbance index per scored sleep session. Usage: owner_check.py <whoop.sqlite>"""
import sqlite3, sys, datetime as dt, numpy as np, afdet as D, acat, beattimes as B
acat.SG_HALF = 10
db = sqlite3.connect(sys.argv[1])
rr = np.array(db.execute("select ts,rrMs from rrInterval where (srcChannel=5 or srcChannel is null) "
                         "order by ts,ord,rrMs,seq").fetchall(), float)
g = np.array(db.execute("select ts,dynAccel from gravitySample where dynAccel is not null").fetchall(), float)
still = B.still_minutes(g)
k = (rr[:, 1] >= 300) & (rr[:, 1] <= 2000)
t = B.beat_times(rr[k, 0]); f = D.detect(t, rr[k, 1] / 1000)
m = (t // 60).astype(int); m0 = m.min(); st = np.full(m.max() - m0 + 1, -1)
nb = np.zeros(len(st), int); na = np.zeros(len(st), int)
for mm, ff in zip(m, f):
    if mm in still: nb[mm - m0] += 1; na[mm - m0] += ff
ok = nb >= D.MIN_BEATS_PER_MIN; st[ok] = (na[ok] / nb[ok] > 0.5).astype(int)
print(f"rhythm: readable minutes {int((st >= 0).sum())}, irregular {int((st == 1).sum())}, episodes {D.episodes(st)}")
for s, e in db.execute("select startTs,endTs from sleepSession where deviceId like '%-noop' and endTs-startTs>3*3600 order by startTs"):
    sel = (rr[:, 0] >= s) & (rr[:, 0] <= e)
    d, h, _ = acat.detect(B.beat_times(rr[sel, 0]), rr[sel, 1],
                          still_mask=lambda grid: np.array([int(x // 60) in still for x in grid]))
    print(f"{dt.datetime.fromtimestamp(e):%Y-%m-%d}  index {len(d) / max(h, 1e-9):5.2f}/h over {h:.1f} h")
