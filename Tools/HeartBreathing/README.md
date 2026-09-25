# Heart & Breathing validation harness (fork)

Python reference for the two Swift screens in `Packages/StrandAnalytics`:
`AFibDetector` (irregular rhythm) and `CvhrDetector` (breathing disturbances). Every step here has a
line-for-line Swift twin; the Swift port reproduced these scripts' output exactly (see
`docs/fork/HEART_BREATHING.md`).

| File | What |
|---|---|
| `afdet.py` | Petrėnas 2015 detector, minute/episode aggregation, and `strapify` (this strap's measured R-R artifact profile) |
| `acat.py` | Hayano ACAT cyclic-variation-of-heart-rate detector |
| `beattimes.py` | beat times from stored 1-s rows; still minutes from `dynAccel` |
| `pn.py` | PhysioNet annotation loader |
| `eval_afib.py` | MIT-BIH AF, Long-Term AF, MIT-BIH Arrhythmia, NSR RR — `clean` or `noisy` |
| `eval_apnea.py` | Apnea-ECG — tune on `abc`, score `x` |
| `owner_check.py` | both screens over a copy of the app database |
| `golden.py` | prints the golden values pinned in `HeartBreathingTests.swift` |

Data (annotation files only, ~45 MB, open access), into `./physionet/<db>/` or `$PHYSIONET_DIR`:

```bash
for db in afdb ltafdb nsr2db mitdb apnea-ecg; do mkdir -p physionet/$db; curl -sf https://physionet.org/files/$db/1.0.0/RECORDS -o physionet/$db/RECORDS; done
# afdb: .hea .atr .qrs   ltafdb: .hea .atr   nsr2db: .hea .ecg   mitdb: .hea .atr
# apnea-ecg (non-"r" records): .hea .qrs .apn, plus additional-information.txt
```

Run with `uv run --with numpy --with wfdb python eval_afib.py noisy` (and `eval_apnea.py noisy 10 x`).
