# Findings and validation

The supplied refactor had several independent problems:

- `generate_hypercube_animation()` never called the collapse optimizer. Its method, restart, and optimizer tuning arguments were recorded but did not determine the animation.
- Gating angular velocity to zero did not undo an already accumulated rotation. A "collapse" label therefore did not guarantee that the corresponding coordinate axis was hidden.
- A global full-dimensional loop correction mixed otherwise hidden axes into lower-dimensional stages.
- The renderer changed abruptly between a single line and the full graph at a squash threshold. Repeated translucent faces and edges could also change brightness when copies coincided.
- Several `3:k` loops and fixed three-coordinate slices were invalid for k=1 or k=2.
- The tests compared optimizer motion penalties without checking the actual animation's dimension order or collapse alignment.

The original scripts in `deprecated/` supplied the useful geometric basis: rigid plane rotations, a fixed orthographic projection, and turning a square edge-on for the line stage. However, `collapse_hcube_efficient.R` applies its final alignment correction to the last step alone. That can introduce a snap even if the preceding optimization is otherwise smooth. Its exploratory entry points also depend on hardcoded paths and numerous packages.

The active implementation solves endpoint alignment by construction. Quintic dimension gates control nested rotation poses, not accumulated velocity. The screen rotation remains positive, while internal tilts ease back during collapse. A spare coordinate makes the line stage a rigid rotation. The path is C2 and periodic without a final correction or reverse playback.

The renderer fills the projected silhouette once and strokes the whole edge graph as one compound path. This prevents opacity and antialiasing changes when identical edges split or merge. It does not implement opaque 3D face occlusion.

Validation includes geometry and dimension checks for k=1–10, pose checks at k=16, finite-difference continuity at every join, and a derivative convergence test. A separate raster regression compares the two graph representations at identical limiting coordinates for all 32 boundaries of the k=9 sequence. This detects the actual brightness defect without confusing normal subpixel movement with a discontinuity. The exported MP4 can be checked for dimensions, duration, frame rate, and frame count using FFprobe.

The reference scripts are preserved. The supplied folder had no `.git` metadata; a snapshot of the supplied `src/` and `run.R` was saved to `tmp/original-refactor.tar.gz` before editing.
