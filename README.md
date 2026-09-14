# Smooth hypercube rotation

Render a continuous `1 → 2 → … → k → … → 2 → 1` cube projection. The screen rotation keeps turning in one direction. Higher-dimensional tilts unfold and ease back into alignment, with continuous position, velocity, and acceleration at every dimension boundary and at the loop seam.

## Setup and run

On macOS, install the tools globally with Homebrew:

```sh
brew install r ffmpeg imagemagick
```

The animation uses **base R with Cairo**; no extra R packages, RStudio, OpenGL, or XQuartz are required. FFmpeg encodes the MP4. ImageMagick is used for preview sheets and raster regression tests.

```sh
Rscript run.R --k=9 --fps=30 --seconds=48 --supersample=2 --out=output/my-k9
Rscript scripts/preview.R output/my-k9
```

Open `output/my-k9/rotation.mp4`. The output also contains PNG frames, compact `animation.rds` data, `schedule.csv`, `continuity.csv`, and `sessionInfo.txt`. The preview command adds `storyboard.png`, `motion.png`, and milestone images. It does not require rendering all video frames first.

The output directory must be new or empty. Existing animations are never deleted. An omitted `--out` creates a timestamped directory under `output/`. Both `output/` and exploratory `tmp/` files are ignored by git.

Useful alternatives:

```sh
Rscript run.R --k=3 --seconds=12 --out=output/cube
Rscript run.R --k=10 --seconds=60 --wireframe --out=output/k10
Rscript run.R --k=12 --seconds=60 --no-frames --out=output/k12-plan
Rscript run.R --help
```

`--turns` is a positive integer number of screen rotations per loop. `--wobble=0` disables the gentle internal oscillation during holds; the unfold/collapse tilts and screen rotation still run. `--seed` deterministically selects viewing orientations. `--no-video` writes frames without encoding. `--supersample=2` draws frames at twice the requested width/height and downsamples the MP4 for cleaner thin edges. PNGs retain that larger size. MP4 dimensions must be even.

The requested duration is rounded to the nearest frame. Each phase needs at least four frames; insufficient duration/fps combinations fail explicitly. The endpoint at exactly the duration is excluded from encoding, so a looping player does not show the first frame twice.

## Geometry and motion

Vertices have coordinates `±0.5`; all edges retain unit length in the ambient space. A fixed orthographic projection displays the first two coordinates. Hidden coordinate axes have exactly zero screen contribution at lower-dimensional holds, up to floating-point roundoff. Thus a d-cube hold has `2^d` distinct projected vertices, rather than merely a different text label.

The pose is a product of explicit plane rotations:

1. A constant, positive screen rotation through an integer number of turns.
2. Nested tilts mixing each new axis with a direction in the screen plane.
3. A square-to-line tilt into one spare coordinate, whose original vertex values are zero.

That spare coordinate allows the square to turn edge-on without scaling or deforming its edges. It does **not** add another cube dimension. The original k-cube stays rigid; unfolding and collapsing describe its projection.

Each dimension has an unfold interval, a visible interval, and a collapse interval. The quintic easing function `6u^5 - 15u^4 + 10u^3` has zero first and second derivatives at its endpoints. Nested factors become identities outside their intervals, so higher dimensions cannot leak into earlier or later holds. Periodic internal oscillations and integer screen turns close the loop without a final corrective rotation. Motion is C2; it does not promise continuous jerk or fixed direction in every individual rotation plane.

There is no numerical collapse optimizer in the active pipeline: alignment is an exact endpoint constraint satisfied by construction. This avoids optimizer restarts and matrix logarithm branch problems entirely.

## Rendering and scale

The renderer draws the cube's projected edge graph over a pale blue convex silhouette. It uses one compound stroke for the edges, so overlapping copies have the same opacity and antialiasing as a single edge. Zero-length edges are omitted at numerical precision to prevent Cairo cap dots. There is no line/polygon threshold, per-frame camera fit, or depth-sort switch. The silhouette is a readability aid, not opaque 3D face occlusion; `--wireframe` removes it.

Geometry is generated using bit indices in `O(k 2^k)`, not all-pairs vertex comparisons. Only the currently visible cube's graph is drawn; compact poses are saved instead of storing all full-dimensional vertex frames. Supported `k` is 1–16 as an allocation guard. Geometry and raster cost still grow exponentially: dimensions 8–10 are practical previews, while larger values warrant shorter runs or `--no-frames` first. Dense edge overlap at high k is inherent to a 2D projection.

## Checks

```sh
Rscript run.R --test-only
Rscript scripts/check_rendering.R
```

Core tests cover topology through k=10, unit edge lengths, proper rotations and distance preservation, exact dimension order, distinct projected vertices and hidden-axis alignment, small dimensions, k=16 pose planning, frame-rate independence, invalid inputs, and continuity at all joins and the seam. A convergence check verifies that derivative discrepancies decrease as the finite-difference interval shrinks.

Raster tests compare both graph representations at identical limiting coordinates at all 32 transitions for k=9. This isolates opacity/antialiasing jumps from ordinary subpixel movement. `continuity.csv` reports numerical one-sided derivative comparisons; small residuals reflect finite-difference and floating-point error, not exact analytical discontinuities.

`deprecated/` contains the original exploratory scripts as reference material. The supported entry point is `run.R`.

See [repair notes](docs/repair_notes.md) for the specific defects found in the supplied code and the regression checks that address them.
