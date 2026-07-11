# Result schema conventions

This document defines the metadata vocabulary RD Gauntlet uses to describe test results
(test definitions in `apps.json`, telemetry columns in `results/*/telemetry.csv`, and the
merged `results/comparison-dataset.{csv,json}`). The vocabulary is modeled on the
[Phoronix Test Suite](https://github.com/phoronix-test-suite/phoronix-test-suite) (PTS)
test-profile/result-file schema, adopted as a **design reference only** -- no PTS code is
vendored here (PTS is GPLv3; see licensing note below). Background research and full
citations: see the PTS/OpenBenchmarking.org research findings summarized in this project's
session history (2026-07-11).

## Why borrow from PTS

PTS has no Android support and its GPU/battery sensors don't work on our hardware (Adreno,
Mali, PowerVR) -- see `docs/coverage-gaps-research.md` for why PTS/OpenBenchmarking.org
aren't directly usable. What *is* worth borrowing is PTS's 15+ year old, well-exercised
vocabulary for describing what a result number actually means -- specifically: which
direction is "better", how many times to run something, and whether a metric changed
enough that historical comparisons are no longer valid. RD Gauntlet's own JSON previously
had none of this declared explicitly; charts and comparisons silently assumed "higher is
better" for everything, which is wrong for temperature, fan speed, and several other
telemetry columns.

## The vocabulary

### `proportion`

Borrowed directly from PTS's `Proportion` schema field
(`pts-core/openbenchmarking.org/schemas/test-profile.xsd`). Three allowed values:

| Value | Meaning |
|---|---|
| `HIB` | Higher Is Better (e.g. FPS, sustained CPU/GPU clock under load) |
| `LIB` | Lower Is Better (e.g. temperature, fan speed, frame time) |
| `ABSTRACT` | No inherent direction / context-dependent -- do not colorize as good/bad in charts (e.g. CPU/GPU utilization %, which can mean "using the hardware well" or "bottlenecked" depending on the paired FPS result) |

### `resultScale`

A human-readable unit string (`"Frames Per Second"`, `"Celsius"`, `"kHz"`, etc.) -- same
idea as PTS's `ResultScale` field. Always a string, even for count-like or dimensionless
metrics (use `"unknown"` if genuinely undetermined).

### `resultQuantifier`

How multiple samples/runs are collapsed into one headline number. Currently always `AVG`
in this project (telemetry is a continuous poll averaged over the run window, not N
discrete repeated runs) -- the field exists now so it's explicit rather than implicit, and
so future test types (e.g. an emulator that runs the same 60-second benchmark clip 3 times)
can declare `MIN`/`MAX` per PTS convention without a schema change.

### `timesToRun` / `ignoreRuns`

Declares how many discrete runs a test performs and which run indices to discard (e.g.
discarding run 1 for shader-compilation/cache warm-up on an emulator's first launch). Set
to `1` / `[]` today for every entry in `apps.json` since the current architecture runs one
continuous telemetry-monitored session per app, not N discrete repeated launches. These
fields are forward-looking scaffolding, not yet load-bearing.

### `testVersion`

Semantic versioning for a test *definition* (not the emulator/app build number, which is
already tracked separately in `apps.json` notes and `device-info.json`). Convention,
directly borrowed from PTS's test-profile `Version` field docs:

- **Major/minor bump (`X.Y`)** -- something changed that invalidates historical
  comparisons: the ROM/content used, the test duration, the launch method, or (as
  happened 2026-07-08) the emulator build itself changed materially. Results captured
  under the old version should not be plotted against results captured under the new one
  without a caveat.
- **Patch bump (`Z`)** -- metadata-only change (notes, description). Historical
  comparisons remain valid.

Every entry in `apps.json` now declares a `testVersion`. See the RetroArch entry for a
worked example: it was bumped `1.0.0` -> `2.0.0` when the app was upgraded in place to a
nightly build, specifically because that change could shift performance results enough
that pre/post comparisons would be misleading without knowing the build changed.

## Where this lives

- **`metric-definitions.json`** (repo root) -- pattern-matched (regex against
  `metric_name`) declarative metadata for every telemetry/result column: `proportion`,
  `resultScale`, `resultQuantifier`, plus a human `label` and free-text `notes` explaining
  any caveats (e.g. battery current sign-convention ambiguity, coulomb-counter
  reliability). Pattern-based rather than literal column names because CPU core count,
  thermal zone names, and available sensors all vary per device (see
  `telemetry-monitor.sh`'s auto-discovery logic) -- the same pattern set works unmodified
  across every device in `devices.json`.
- **`apps.json`** -- each app/test entry now carries `testVersion`, `timesToRun`,
  `ignoreRuns`, `resultQuantifier`, and (for manual-score benchmarks like 3DMark/Geekbench)
  a `primaryMetric` block describing the official score's own scale/proportion.
- **`New-ComparisonDataset.ps1`** -- enriches every row of `comparison-dataset.{csv,json}`
  with `proportion`, `result_scale`, and `result_quantifier` (looked up from
  `metric-definitions.json` by pattern match) plus `test_version` (read from each run's
  captured `app-metadata.json` snapshot). Unmatched/uncatalogued metrics fall back to
  `ABSTRACT`/`unknown` rather than failing -- this is enrichment, not a validation gate,
  so a new sysfs column showing up on a future device never blocks dataset generation.

## What was deliberately NOT changed

- **`telemetry-monitor.sh` itself** -- unmodified. PTS's own sensor code is AMD/NVIDIA-only
  for GPU usage and generic-Linux-only for CPU temperature; there was nothing in PTS's
  sensor implementation worth porting. Our script's SoC-agnostic auto-discovery (Adreno
  kgsl, legacy Mali, generic devfreq fallback) is already more capable for this hardware
  than PTS's equivalent.
- **The per-run result file structure** (`device-info.json`, `app-metadata.json`,
  `telemetry.csv`, `cooldown.csv` per app folder) -- unchanged. Only the *merged*
  `comparison-dataset` output gained new columns. This keeps the change additive: existing
  per-run data on disk needs no migration, and any pre-existing consumer that reads named
  JSON/CSV columns (not positional) is unaffected by the new columns appearing.

## Licensing note

PTS is GPLv3 licensed. This document and the files it describes were written by studying
PTS's publicly documented schema *concepts* (HIB/LIB/ABSTRACT, versioning semantics, the
systems/results separation) and independently reimplementing equivalent ideas in our own
JSON files and PowerShell code -- no PTS source was copied. File formats/schemas are not
themselves copyrightable in the way source code is; the safe boundary observed here is
"inspired by the design, zero vendored code."
