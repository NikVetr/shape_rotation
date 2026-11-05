# Hypercube rotation

This R project renders a rigid hypercube's orthographic projection as its visible
dimension grows from a rotating line through k dimensions and returns to a line.
`run_original.R` configures, solves, validates, saves, and renders the pipeline
in `src/incremental/`.

`geometry.R` supplies vertices, faces, Givens rotations, subrotations, and label
rasterization. `optimization.R` blends small angular increments and searches
collapse durations with L-BFGS-B. A prior favors small changes from incoming
motion. Control-curve refinement enforces alignment without a last-frame impulse;
exact blend endpoints constrain incoming/outgoing velocity.

`animation.R` applies rotations on a nonlinear dimension schedule, handles
edge-on square/line tilts, and closes the projected loop in the continuing
rotation direction. `diagnostics.R` checks matrices, alignment, closure, and
screen-plane direction, and exports motion plots. `render.R` draws depth-sorted
translucent faces with base R/Cairo or 16-bit ragg. `render_rgl.R` builds lit
RGL scenes with PNG label textures, snapshots them through headless Chrome,
and exports interactive HTML. Base R's `parallel` package manages reusable
socket workers for both rendering paths; FFmpeg encodes MP4. `text.R` supplies
custom text utilities.
`face_labels.R` plans face-mounted dimension numerals for opaque RGL rendering.
Stable face identities retain their labels while visible; a hidden interval
preloads the number for the next appearance. Convex supporting planes determine
visibility for the fixed orthographic camera, with adjacent-step concealment
checks at changes and across the loop seam. The plan precedes thinning and
parallel rendering. RGB numeral textures share the lit panel material and its
depth test; front/back UV coordinates prevent mirrored printing. A face may
retain an older numeral across multiple stages until it is concealed.
The base renderer strokes the true edge graph after all face fills, keeping
edges visible through degenerate projections and overlapping translucent faces.

Outputs include solver checkpoints, full trajectory RDS data, PNG frames,
validation metrics, motion plots, render timings, and R session information.
`scripts/export_web_plan.R` exports a solved plan for a browser viewer: one k×3
projection matrix per step, stage dimensions and face-number events.
Render input/settings are recorded so interrupted runs can retain verified
frames and repair incomplete ones. PNG and video publication use atomic renames;
encoding requires a complete frame sequence. New output directories must be
empty; `output/` and exploratory `tmp/` are ignored by Git. Maximum
dimension is at least three; computational cost grows exponentially. Local
optimization does not guarantee globally minimal corrections or constant
full-dimensional angular speed.

`scripts/check_incremental.R` covers geometry, interpolation, endpoint conditions,
timing metadata, and full trajectories. `docs/repair_notes.md` records the
preservation audit; `docs/deprecated.sha256` checks the frozen `deprecated/`
reference. Working code has no runtime dependency on that archive. The separate
`run.R` and top-level `src/*.R` are an eased-pose comparison implementation with
their own tests and preview utilities.
`scripts/check_incremental_rendering.R` checks edge visibility in raster output,
including dense overlaps, edge-on faces, and near-collapsed dimensions.
Pipeline checks cover serial/parallel equality, restart recovery, and worker
failures. Opacity checks compare high-precision panel accumulation with the
analytic compositing formula. Face opacity is explicit and configurable; the
original default remains available alongside lighter layered-panel views.
`scripts/check_rgl_scene.py` uses Playwright to verify the exported scene's WebGL
context, textured label, and interactive camera rotation in Chrome.
`scripts/check_face_numbers.R` compares face visibility with independent ray
intersections through k=9 and verifies label retention and concealed changes.
`scripts/check_face_number_occlusion.R` renders before/after label assignments at
fixed poses to check that hidden changes leave identical pixels.
