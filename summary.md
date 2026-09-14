# Project summary

This base-R project renders a smoothly unfolding and collapsing orthographic hypercube projection, from a rotating line through dimensions 2 to k and back to a line. The default animation is a 48-second, 30-fps 1→9→1 loop. All rotations preserve the rigid cube's edge lengths; only its projection changes dimensional appearance.

`run.R` validates command-line options, runs the local checks, builds the animation, saves reproducibility data, renders PNG frames, and calls FFmpeg for H.264 MP4 output. Each run writes a new directory under the ignored `output/` tree.

The implementation is divided into:

- `src/rotation_math.R`: analytic plane rotations, quintic easing, validation, and bit-indexed cube vertices, edges, and square faces.
- `src/dimension_schedule.R`: unfold, hold, and collapse intervals and C2 dimension gates.
- `src/animation.R`: periodic poses composed from constant screen rotation, gated higher-dimensional tilts, and a spare-coordinate square-to-line rotation. Compact poses and projection matrices are stored per frame.
- `src/diagnostics.R`: one-sided velocity and acceleration comparisons at every phase boundary and the loop seam.
- `src/render_frames.R`: fixed framing, a translucent projected silhouette, compound-path edge drawing, headless Cairo PNG output, and checked FFmpeg encoding.
- `src/tests.R`: topology, rigid geometry, exact dimension stages, periodicity, derivative convergence, frame sampling, and input validation.
- `scripts/check_rendering.R`: ImageMagick pixel comparisons at dimension boundaries.
- `scripts/preview.R`: milestone storyboards and base-R motion plots from saved animation data.
- `deprecated/`: reference scripts outside the supported execution path.

The motion is constructed to satisfy alignment exactly, eliminating numerical collapse optimization and final-frame corrections. Quintic gates ensure continuous position, velocity, and acceleration while the screen rotation always proceeds in the same direction. A spare zero coordinate allows a square to turn edge-on as a line without deforming the cube. The encoded loop excludes its duplicated endpoint.

Rendering uses a single compound stroke to avoid brightness changes from coincident edge copies. A fixed camera avoids zoom changes. The pale blue convex silhouette improves legibility without depth-sorting artifacts. Geometry is generated only for the visible dimension, and storage contains poses rather than large vertex histories. Rendering remains exponential in k; input is limited to dimensions 1–16, with 8–10 suitable for ordinary previews.

The runtime needs R with Cairo and FFmpeg; no external R packages are required. ImageMagick supplies preview composition and raster checks. Outputs include `animation.rds`, PNG frames, `rotation.mp4`, phase and continuity CSV files, and an R session record. README.md documents installation, commands, the geometry, and validation.
