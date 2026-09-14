# Preservation audit and targeted repairs

`deprecated/` is frozen. All seven R scripts match the backup made before this
work; `deprecated.sha256` records SHA-256 hashes. Working code uses independent
copies in `src/incremental/`, with a separate `run_original.R` entry point. It
does not source or override archive functions.

Function definitions were copied with their original source text. Top-level
notebook experiments, hardcoded paths, and session-dependent example objects
were excluded. Duplicate definitions resolve to the versions the original
source order used. Animation and both render branches were copied into functions
so configuration and output handling can be explicit.

## Preserved choices

| Original choice | Working copy |
| --- | --- |
| Ordered incremental Givens rotations | Retained; `dkrot`, `undokrot`, and cube geometry unchanged |
| Matrix log/exponential for initial small rotation | Retained with `expm` |
| Nested subrotations obtained by QR | Retained for expansion |
| Quadratic dimension schedule | Retained, including longer low-dimensional stages |
| Ten candidates and ±10% collapse timing flexibility | Retained by default |
| Logistic-simplex blending, endpoint emphasis, shape parameter | Retained with explicit endpoint conditions |
| Two L-BFGS-B passes and original loss weights | Retained: (1,5), then (5,1); selection uses (1,5) |
| Prior favoring incoming incremental rotation | Retained |
| Lower-dimensional rotation during collapse | Retained; surviving Givens prefix stays fixed |
| Square tilted about its diagonal to make a line | Retained |
| Same-direction line return with flexible duration | Retained with endpoint fixes |
| Translucent blue faces, depth order, outlines, fixed bounds | Retained |
| Parallel base-R and optional RGL renderer with PNG labels | Retained; RGL not yet validated here |
| Custom text functions | Copied, retaining effective final definitions |

There is no imposed screen-spin factor, prescribed pose gate, or angular-speed
normalization in this pipeline. The eased implementation remains separate in
`run.R` and top-level `src/*.R` for comparison.

## Demonstrated defects and repairs

1. **Unused parameters.** The original allocated `n_p` blocks of free angles
   but consumed `n_p - 1`. The copy allocates exactly the consumed parameters,
   plus the blend-shape parameter.
2. **Wrong duration during selection.** Original rescoring used the nominal
   duration instead of each candidate's optimized duration. Scores now evaluate
   the actual path and duration, including refinement.
3. **Restart wrapping.** Negative per-frame angles were wrapped through `2π`,
   along with the non-angular shape parameter. Restarts now use small signed
   perturbations scaled to incoming angles; shape is perturbed separately.
   Restarts are generated before parallel work for reproducibility.
4. **Final-frame impulse.** The original appended alignment to the last step.
   The copy refines control parameters to align an actual unit edge with the
   hidden axis. Finite-difference Newton updates and backtracking distribute
   correction through the curve. Failure is explicit; no final pose snap.
5. **Velocity mismatch at collapse joins.** Original logistic weights leaked
   into other anchors at endpoints, and outgoing free angles did not vanish
   before removing a dimension. Normalized cumulative weights now select the
   first/last anchors exactly. An additional terminal zero anchor constrains
   hidden-plane velocity. A cosine time map makes weight derivatives vanish
   at both ends. This is an intentional change to the control basis.
6. **Disabled expansion blending.** The main script calculated a smooth weight
   but immediately applied the next subrotation. The copy blends incremental
   Givens angles over the interval; directly blending matrix entries would
   lose rigidity.
7. **Fragile duplicate removal.** Rounding projected vertices can split copies
   across decimal boundaries. This occurred in a k=9 run. The copy identifies
   hidden original edge axes and selects one face by original vertex bits.
   The surviving rotation block is already orthogonal and is used directly.
8. **Backward interval bookkeeping.** The square branch reused stale `n_steps`.
   Next-stage indexing reused the last interval before lagging by one. Durations
   now match their dimension's schedule entry; every frame has one dimension label.
9. **Square/line tilt joins.** Linear tilt starts abruptly; its collapse formula
   uses expansion phase constants. The same diagonal tilt now uses
   `t - sin(2πt)/(2π)`, with zero velocity and acceleration at the endpoints.
10. **Line closure.** With equal incoming/outgoing speeds, rounding the original
    duration changed both endpoint speeds. The existing residual-distribution
    method now handles that case too. Its profile is `sin(πt)^2` so acceleration
    vanishes at joins. The return excludes the duplicate first frame and, if
    necessary, continues another half turn to allow a gradual correction.
    Closure length also respects the rendering stride, so the last-to-first
    frame interval has the same duration as every other encoded interval.
11. **Execution and output.** Configurable paths protect existing results;
    ffmpeg failures are checked, workers stopped, and expensive solves checkpointed.
    Logging uses `cat` without a shell. Face-list filtering is explicit and plot
    margins are set before plotting. RGL labels also handle dimensions above 9.

Suspicious comments in `undokrot` were not sufficient reason to replace it:
round-trip tests pass for the small incremental rotations it actually receives.
It remains unchanged.

## Validation and limits

`scripts/check_incremental.R` tests reconstruction/products through k=9,
endpoint constraints, interpolation convergence, line-loop sums/velocities,
duration metadata, and complete k=3/k=5 trajectories with multiple seeds. A
full k=9 solve uses ten timing candidates and validates alignment and its seam.
Checksums separately protect the archive.

Base rendering is exercised by k=5 and k=9 previews. RGL and optional text
utilities are retained but not fully exercised. The original renderer can still
show opacity changes when overlapping faces split or merge. No replacement
silhouette/edge renderer has been silently substituted.

These repairs remove specific discontinuities. They do not prove globally
minimal nudges, constant full-dimensional angular speed, or absence of perceived
rhythm. Short high-dimensional intervals can demand large corrections; motion
plots expose those for subsequent tuning.
