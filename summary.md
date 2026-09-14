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
translucent faces with base R/Cairo or optional RGL. `foreach`/`doParallel` support
parallel rendering; FFmpeg encodes MP4. `text.R` supplies custom text utilities.

Outputs include solver checkpoints, full trajectory RDS data, PNG frames,
validation metrics, motion plots, and R session information. Output directories
must be empty; `output/` and exploratory `tmp/` are ignored by Git. Maximum
dimension is at least three; computational cost grows exponentially. Local
optimization does not guarantee globally minimal corrections or constant
full-dimensional angular speed.

`scripts/check_incremental.R` covers geometry, interpolation, endpoint conditions,
timing metadata, and full trajectories. `docs/repair_notes.md` records the
preservation audit; `docs/deprecated.sha256` checks the frozen `deprecated/`
reference. Working code has no runtime dependency on that archive. The separate
`run.R` and top-level `src/*.R` are an eased-pose comparison implementation with
their own tests and preview utilities.
