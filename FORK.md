# This fork (Iskrata/noop)

Personal fork of ryanbr/noop, run on the owner's iPhone 16 with a WHOOP 5.0 strap. The owner reads their
scores in Bevel (NOOP → Apple Health → Bevel), so **never break what NOOP writes to Apple Health** (sleep
stages, HRV, resting HR, heartbeat series). Charge/Effort/Rest themselves are not written to Health.

## Branches and remotes
- `origin` = github.com/Iskrata/noop (primary line, `main` = the phone's build). `upstream` = ryanbr/noop.
- Fork-only customizations go straight on `main`, **Swift/iOS only** (no Kotlin twin).
- A genuine upstream bug: branch from `upstream/main`, fix it there **with the Kotlin/Android twin compiled
  and tested locally**, open a PR on ryanbr/noop, then merge the branch into `main`.
- Commits and PRs carry no attribution / co-author lines. Push over SSH (the repo's `core.sshCommand`); the
  gh token lacks `workflow` scope.
- Parallel work: use a git worktree per task (`git worktree add ../noop-<task> -b <branch> main`) and copy
  `Config/BundleIdSecrets.xcconfig` into it.

## Build, test, install
- Project is generated: `xcodegen generate` (never hand-edit `Strand.xcodeproj`). Scheme `NOOPiOS`.
- **Always Release on the phone**:
  `xcodebuild -project Strand.xcodeproj -scheme NOOPiOS -configuration Release -destination 'generic/platform=iOS' -derivedDataPath build -allowProvisioningUpdates build`
  then `xcrun devicectl device install app --device BB3E4333-ACC6-5348-BA35-C66955060441 "build/Build/Products/Release-iphoneos/NOOP Staging.app"`
  (phone must be unlocked; a cable is more reliable than Wi-Fi).
- App tests: `xcodebuild test -scheme Strand -destination 'platform=macOS' -derivedDataPath build-mac -only-testing:StrandTests/<Class>`.
  Package tests: `swift test` inside `Packages/<Pkg>`.
- Parity tools need Python 3.12 (`~/.local/share/uv/python/cpython-3.12-macos-aarch64-none/bin/python3.12`).
- Reading the phone's state: `xcrun devicectl device copy from --device <id> --domain-type appDataContainer
  --domain-identifier com.iskren.noop --source "Library/Preferences/com.iskren.noop.plist" --destination <file>`
  (the strap log is under `strapLog.tail`); the DB is `Library/Application Support/OpenWhoop/whoop.sqlite`.

## Fork customizations (on `main`)
- WHOOP calibration: `SleepStagerV2.Calibration.personal`, `StrainScorer.Method.whoopCalibrated`,
  `RecoveryScorer` wRHR 0.05 / K 1.34 / Z0 −0.61, and unlabelled legacy WHOOP 5 R-R is scored
  (`WhoopStore.scoresUnlabelledWhoop5Legacy`).
- UI: WHOOP black palette (`NoopVisualStyle`), day-cycle sky off, hide-scores switch, Today Activities list
  (`DayActivities*`), Sleep Consistency pinned with a 7-night bedtime/wake sheet, Effort target band, tabs
  Today · Zones · Trends · Coach · More, Start-session row off.
- Stale-sync notification, heartbeat export toggle, MetricKit exit-reason logging.

## Working rules from the owner
- Don't start the WHOOP app or pair anything. Don't use the Fable model for subagents.
- The owner makes trade-off decisions: present options with evidence. Add debug logs rather than guess.
- Fix bugs you find; keep things DRY; don't grow already-large files (split them).
