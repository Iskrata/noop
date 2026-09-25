# Heart & Breathing screens (fork)

Two screens run over the beat-to-beat intervals the WHOOP 5.0 banks: **irregular rhythm** (possible atrial
fibrillation) and **breathing disturbances** (possible sleep apnea). Neither is a diagnosis. Results show in
Lab → Heart & Breathing; the Today screen shows a banner only when a pattern **repeats**. Nothing is
written to Apple Health (`atrialFibrillationBurden`, `irregularHeartRhythmEvent`, `sleepApneaEvent` and
`appleSleepingBreathingDisturbances` are Apple-only, read-only types anyway), no push notification is sent
and the strap is never buzzed.

Scoping report with the literature review: https://claude.ai/artifact/8MzE57m4XbD9KgQzQDDUzw

## What the strap gives us (owner's phone database, checked 2026-09-25)

- R-R: `rrInterval`, 1-s `ts` + `ord`, 1 ms resolution, unsmoothed; ~90% of each night covered.
- Measured artifact profile over 14 nights: 4.9% of intervals 20–70% off their local median, 0.41% split
  beats, 0.14% merged beats, ~64 holes > 10 s per night. `Tools/HeartBreathing/afdet.py:strapify` injects
  exactly this into the PhysioNet ECG beats, so the accuracy below is for this strap, not a Holter.
- Motion: `gravitySample.dynAccel` present over the whole history. 0.1 g per-minute max keeps 63% of
  beat-covered minutes (`MotionStillness`).
- No continuous SpO₂ on a 5.0 (the @82 candidate is present ~6 min/night), so the apnea screen uses the
  heart-rate signature of apneas, not oxygen dips.

## Irregular rhythm — `AFibDetector`

Petrėnas, Marozas & Sörnmo 2015 (Comput Biol Med 65:184), ported from github.com/tabaraei/LTAF-detection:
3-point median filter, forward-backward exponential averaging (α 0.02), pairwise-difference irregularity
over 8 beats (γ 30 ms), bigeminy suppression, decision threshold η 0.725 (δ 2e-4). Fork aggregation: a
minute is irregular when > 50% of its ≥ 20 still-wrist beats are; an episode is ≥ 30 irregular minutes
bridging ≤ 3 regular ones (the Fitbit Heart Study's sustained-rhythm idea).

PhysioNet, strap artifacts injected, 5 noise draws (`eval_afib.py noisy`, `NOISE_SEED=0..4`):

| Database | Result |
|---|---|
| MIT-BIH AF (25 × 10 h) | patients with ≥ 30 min AF flagged 15/16; minute Se 90.7–91.5%, Sp 97.1–97.3%; 0 false episodes in 249 h |
| Long-Term AF (84 × ~24 h) | 65–66/67 flagged; minute Se 82.3–82.5%, Sp 93.7–93.8% (other atrial arrhythmias count as "not AF") |
| NSR RR (54 healthy × 24 h) | 0–1 of 54 with a false episode (0–1 in 1,275 h) |
| MIT-BIH Arrhythmia (48 × 30 min, heavy ectopy) | 0–1 of 47 non-AF records falsely flagged |

Clean ECG beats (no injected artifacts), pooled beat level on Long-Term AF: Se 92.6% / Sp 93.4% (paper:
97.1 / 98.3; the gap is the edge handling of the exponential average and other rhythms counted as non-AF).

Owner, 45 days (08-24 → 09-25): 15,292 readable minutes, 133 irregular (0.87%), **0 episodes**; even with
no motion gate there are 0 episodes.

## Breathing disturbances — `CvhrDetector`

Hayano's ACAT (Circ Arrhythm Electrophysiol 2011;4:64; parameters restated in PLOS One 2020 e0237279 and
JAHA 2022, PMC8916582): dips in 2nd-order-polynomial-smoothed R-R 10–120 s wide, depth/width > 0.7 ms/s,
depth > 40% of the 130-s 5–95th percentile range, 25–130 s cycles, mean morphology correlation > 0.4 with
2 preceding + 2 following dips, and 4 consecutive dips with (3 − 2L1/s)(3 − 2L2/s)(3 − 2L3/s) > 0.8.
Index = dips per readable hour (readable = beat train present and wrist still).

The smoothing window is unpublished: on the 35 released Apnea-ECG records (clean), half-widths 3/5/7/8/10/
12/15 s gave AUC(AHI ≥ 15) 0.874/0.881/0.952/0.942/0.963/0.927/0.918 — 10 s (21-s window) was chosen. The
night cut-off 5/h was fixed on the released set with artifacts injected (15/22 AHI ≥ 15 above it, all 13
others below; controls max 2.4/h), **before** the 35 withheld records were scored:

| Withheld Apnea-ECG, strap artifacts, 5 noise draws | |
|---|---|
| AUC apnea (≥ 100 apnea min) vs normal (< 5) | 0.950–0.975 |
| ≥ 15 apnea-min/h flagged at 5/h | 12–13 / 18 |
| < 5 apnea-min/h flagged at 5/h | 0 / 12 |
| r(index, apnea minutes/h) | 0.63–0.64 |

Benchmarks: Hayano 2020 wrist PPG AHI ≥ 15 Se 82% / Sp 89%; Apple Watch sleep apnea notifications Se 66% /
Sp 98.5%. Apnea-ECG is an easy set (few borderline cases), so real-world sensitivity will be lower.

Owner, 33 nights: index 0–1.0/h every night.

A per-night 30–41/h figure in the scoping report came from a naive heart-rate-surge counter; ACAT's
adaptive threshold and periodicity checks remove it.

## Repeating-pattern rules — `HeartBreathingPatterns`

- Irregular rhythm: episodes on ≥ 2 distinct days within 14 days.
- Breathing: within 30 days, ≥ 10 nights with ≥ 4 readable hours and ≥ 50% of them at ≥ 5/h (Apple's
  K240929 rule; Hayano 2022 measured a 66% night-to-night coefficient of variation).

## Parity

The Swift port reproduced the Python reference exactly — beat flags, readable/irregular minute counts,
episode boundaries, dip timestamps and readable hours — on the owner's last 14 days and 14 nights and on
noisy MIT-BIH AF 04015/04043/07162/08378 and Apnea-ECG a01. `HeartBreathingTests` pins the reference's
output on deterministic synthetic signals (`Tools/HeartBreathing/golden.py`).

## Limits

Irregular rhythm: atrial flutter with regular conduction is invisible; frequent premature beats are the
main false positive; episodes under 30 minutes are not reported. Breathing: cannot separate obstructive
from central apnea; hypopnea-heavy apnea is under-counted; periodic leg movements and arousals mimic it;
the index needs sinus rhythm (irregular-rhythm nights are unreliable).
