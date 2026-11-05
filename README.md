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
brew install r ffmpeg imagemagick pkgconf harfbuzz fribidi
Rscript -e 'install.packages(c("expm", "png", "rgl", "webshot2", "ragg"), repos="https://cloud.r-project.org")'
Rscript run_original.R --k=9 --cores=4 --out=output/my-k9
```

On Ubuntu 22.04, the same R packages build from source:

```sh
sudo apt install r-base ffmpeg imagemagick google-chrome-stable pkg-config \
  libfontconfig1-dev libfreetype-dev libharfbuzz-dev libfribidi-dev libpng-dev \
  libtiff-dev libjpeg-dev libwebp-dev libssl-dev libx11-dev
Rscript -e 'install.packages(c("expm", "png", "rgl", "webshot2", "ragg"), repos="https://cloud.r-project.org")'
```

OpenGL headers are optional. Without them, rgl builds only its null/WebGL
device, which is all the headless RGL renderer uses. Chrome comes from Google's
APT repository; `CHROMOTE_CHROME` can name another Chrome or Chromium. Linux
fontconfig substitutes an installed font, such as DejaVu Sans, for Arial
Unicode MS; it still displays ℝ and superscripts. ImageMagick 6's `convert`
and `compare` commands are accepted in place of `magick`. Verify the archive
with `sha256sum -c docs/deprecated.sha256`.

The output directory must be new or empty. It contains `rotation.mp4`, PNG
frames, `animation.rds`, individual collapse checkpoints, `motion.csv`,
`motion.png`, validation metrics, and R session information. Existing outputs
are never deleted. `output/` and exploratory `tmp/` are ignored by Git.
Use `--continue` to recover an interrupted render in the same directory.

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

Render the lit RGL version with PNG label textures, or a lighter base-R version:

```sh
Rscript run_original.R --resume=output/plan/animation.rds --rgl --face-alpha=0.01 --cores=4 --out=output/rgl
Rscript run_original.R --resume=output/plan/animation.rds --rgl --face-alpha=1 --face-numbers --cores=4 --out=output/numbered
Rscript run_original.R --resume=output/plan/animation.rds --device=ragg16 --face-alpha=0.004 --cores=4 --out=output/translucent
# Continue with exactly the same rendering settings; worker count may change.
Rscript run_original.R --continue --rgl --face-alpha=0.01 --cores=4 --out=output/rgl
```

RGL uses an isolated headless Chrome process per worker through `webshot2`.
Chrome must be installed; `CHROMOTE_CHROME` can specify its executable. Native
OpenGL windows and XQuartz are not needed for this path. RGL outputs also include
`scene.html` and its asset directory: an interactive view of a high-dimensional
frame. Labels use the installed Arial Unicode MS font to display ℝ correctly.

`--face-numbers` prints dimension numerals directly onto opaque faces. It requires
`--rgl --face-alpha=1`. Each face retains its number while visible; hidden faces
receive the dimension scheduled for their next appearance. Numbers rotate and
foreshorten with the face, with separate texture coordinates for readable front
and back printing. The top-left dimension caption remains as a reference.
A line has no face on which to print “1”. An older number may persist across
several stages if its face has not yet disappeared from view.

The label planner uses stable original face identities and supporting planes of
the convex 3D projection to distinguish visible faces from buried ones. Coincident
faces count as potentially visible. Changes require concealment at the current
integration step and both neighboring steps, including the loop seam. The plan
is computed before frame thinning or parallel dispatch and saved in
`face-numbers.rds` for inspection. Opaque materials write depth, so interior
numbers cannot show through their covering panels. Visibility planning assumes
the video's fixed orthographic camera; dragging the exported static scene does
not recompute label history for a new camera path.

Workers receive projection data once, then render numbered batches. Each PNG
is decoded and checked before an atomic rename into the frame sequence. The
encoder runs only after every expected frame is present. `render-times.csv`
records per-frame timings; `workers.log` records worker output. Continuation
checks saved input/settings, retains valid PNGs, repairs incomplete ones, and
re-encodes when necessary. Workers and their browser processes are closed on exit.

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

Rendering retains depth-sorted translucent faces, colored outlines, 800×800 PNGs,
fixed bounds, and parallel workers. Cairo remains the default base-R device;
`--device=ragg16` uses 16-bit compositing for faint panels. `--rgl` uses lit blue
faces, specular highlights, true edge topology, and unlit PNG label textures.
The copied custom text utilities remain available; the base-R branch draws no labels.

The base renderer draws the cube's actual edges after all face fills. This keeps
edge-on faces from losing their edges and prevents translucent face layers from
painting over previously drawn outlines. Coincident edges share one compound
stroke to avoid repeated antialiasing buildup.

`--face-alpha` sets each face's opacity. If omitted, the original `1 / 1.25^k`
value remains in use. With many overlapping faces this can saturate: combined
opacity is `1 - (1 - alpha)^layers`. The square stage of a k=9 cube has 128
coincident layers throughout its interior; higher-dimensional stages have
spatially varying counts. Use a smaller alpha to see those variations. At very
low opacity, Cairo's 8-bit premultiplied colors can shift hue; use `ragg16` for
the base-R comparison. WebGL also has finite color precision, so its practical
opacity setting differs from the 16-bit renderer's.

Smooth joins and a consistent screen-plane rotation direction do **not** imply
constant full-dimensional angular speed or eliminate every perceptual rhythm.
Saved motion plots expose that variation. Short upper-dimensional stages can
require substantial corrections. Visual acceptance of the “barely nudged”
trajectory remains a separate check.

## Validation and reference

```sh
Rscript scripts/check_incremental.R
Rscript scripts/check_incremental_rendering.R
Rscript scripts/check_render_pipeline.R
Rscript scripts/check_render_pipeline.R --rgl
Rscript scripts/check_render_pipeline.R --ragg16
Rscript scripts/check_panel_opacity.R
Rscript scripts/check_face_numbers.R
Rscript scripts/check_render_pipeline.R --face-numbers
Rscript scripts/check_face_number_occlusion.R output/plan/animation.rds
shasum -a 256 -c docs/deprecated.sha256
```

Checks exercise Givens reconstruction through dimension 9, proper rotation
products, endpoint velocity constraints, interpolation convergence at joins,
same-direction line closure, timing metadata, and complete multi-seed
trajectories. Full runs validate their own alignment and projected loop seam.
Pipeline checks compare serial/parallel pixels, repair a corrupted frame,
reject mismatched continuation settings, and verify worker failures prevent
encoding. The panel check compares 128-layer compositing with its analytic result.

The interactive export has a Playwright check using the installed Chrome browser:

```sh
python3 -m venv tmp/browser-check-env
tmp/browser-check-env/bin/pip install playwright
tmp/browser-check-env/bin/python scripts/check_rgl_scene.py output/rgl/scene.html
tmp/browser-check-env/bin/python scripts/check_rgl_scene.py output/numbered/scene.html --face-numbers
```

It checks WebGL errors, scene/texture objects, and camera rotation after dragging.
Face-number checks independently intersect rays with projected panels through
k=9, verify hidden-only changes and visible-label retention, and exercise
coincident faces, line projections, and the circular frame boundary.
The occlusion check holds geometry fixed at sampled relabeling events and verifies
that changing the hidden numerals leaves the rendered pixels identical.

See [repair notes](docs/repair_notes.md) for the preservation audit. The older
`run.R` and top-level `src/*.R` are retained as a comparison experiment using
prescribed eased poses. They are **not** the incremental optimizer described here.
Their checks remain separate: `Rscript run.R --test-only` and
`Rscript scripts/check_rendering.R`.
