# Incremental hypercube rotation

The working entry point is `run_original.R`. Its implementation lives in
`src/incremental/`: editable copies of the original scripts, with targeted
repairs. `deprecated/` is a frozen reference and is never loaded at runtime.

The animation unfolds `1 → 2 → … → k` and collapses back to a rotating line.
Each frame applies a small Givens rotation to a rigid cube. Collapse optimization
nudges those rotations toward alignment, with gradual velocity changes and a
search over transition durations. This retains the original motion model,
nonlinear schedule, rotation prior, and face renderer.

## Install and run

```sh
brew install r ffmpeg imagemagick
Rscript -e 'install.packages(c("expm", "foreach", "doParallel", "png"), repos="https://cloud.r-project.org")'
Rscript run_original.R --k=9 --cores=4 --out=output/my-k9
```

The output directory must be new or empty. It contains `rotation.mp4`, PNG
frames, `animation.rds`, individual collapse checkpoints, `motion.csv`,
`motion.png`, validation metrics, and R session information. Existing outputs
are never deleted. `output/` and exploratory `tmp/` are ignored by Git.

The original defaults are retained: 720 forward steps, 120 steps per reference
rotation, seed 1, ten optimization candidates, and a ±10% duration search for
each collapse. Integration uses 60 steps per second; `--thin=2` renders every
second step into a 30 fps video. Rendering defaults to one worker; `--cores`
also sets the maximum number of concurrent optimization candidates.

```sh
# Solve and inspect before rendering.
Rscript run_original.R --k=9 --cores=4 --plan-only --out=output/plan
# Render saved data into a different, empty directory.
Rscript run_original.R --resume=output/plan/animation.rds --cores=4 --out=output/video
# Fewer restarts provide less search coverage.
Rscript run_original.R --k=5 --nrots=360 --nrep=3 --out=output/quick
Rscript run_original.R --help
```

`--nrots` changes the original schedule's time scale. Larger values allow more
time for alignment. `--seed` selects a different initial rotation. `--no-video`
saves frames without encoding. Maximum dimension must be at least 3; the
animation includes line and square stages. There is no fixed upper cap, but
vertices and faces grow exponentially.

The closing interval is timed so the frame count is divisible by `--thin`.
When resuming saved data, choose a thinning factor that divides its length;
`--thin=1` always does. This avoids a shorter time interval at the video seam.

## Motion and rendering

Square-to-line stages retain the original diagonal-axis tilt. Expansion blends
the original nested subrotations in Givens coordinates using a cosine velocity
profile. Collapse retains the logistic-simplex family and the two-pass objective:
alignment, deviation from incoming rotation, and a blend-shape prior. Endpoint
conditions match incoming velocity and stop revealing the outgoing hidden axis.
Remaining alignment error is corrected through the whole control curve, never
by changing only the last frame.

Timing candidates are scored using their own durations. Invalid candidates are
reported and rejected; the run fails if none meet alignment. Optimization is
local and does not establish a global minimum correction.

Rendering retains depth-sorted translucent faces, colored outlines, 800×800 Cairo
PNGs, fixed bounds, and parallel workers. The original RGL branch and its PNG
labels remain behind `--rgl`; install `rgl` separately and use an OpenGL-capable
environment. That branch has not been validated on this laptop. The copied
custom text utilities remain available; the original base-R branch drew no labels.

Smooth joins and a consistent screen-plane rotation direction do **not** imply
constant full-dimensional angular speed or eliminate every perceptual rhythm.
Saved motion plots expose that variation. Short upper-dimensional stages can
require substantial corrections. Visual acceptance of the “barely nudged”
trajectory remains a separate check.

## Validation and reference

```sh
Rscript scripts/check_incremental.R
shasum -a 256 -c docs/deprecated.sha256
```

Checks exercise Givens reconstruction through dimension 9, proper rotation
products, endpoint velocity constraints, interpolation convergence at joins,
same-direction line closure, timing metadata, and complete multi-seed
trajectories. Full runs validate their own alignment and projected loop seam.

See [repair notes](docs/repair_notes.md) for the preservation audit. The older
`run.R` and top-level `src/*.R` are retained as a comparison experiment using
prescribed eased poses. They are **not** the incremental optimizer described here.
Their checks remain separate: `Rscript run.R --test-only` and
`Rscript scripts/check_rendering.R`.
