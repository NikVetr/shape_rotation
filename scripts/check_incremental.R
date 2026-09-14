#!/usr/bin/env Rscript
suppressPackageStartupMessages(library(expm))
for (file in c("optimization.R", "geometry.R", "animation.R", "diagnostics.R")) {
  source(file.path("src", "incremental", file))
}
set.seed(42)
for (k in c(3, 5, 9)) {
  theta <- runif(choose(k, 2), -0.05, 0.05)
  r <- dkrot(k, theta)
  stopifnot(max(abs(dkrot(k, undokrot(r)) - r)) < 1e-12)
  fixed <- seq_len(choose(k - 1, 2))
  free <- seq.int(max(fixed) + 1, length(theta))
  bg <- Reduce("%*%", dkrot_info(k, theta)$big_rotmats[fixed])
  p <- c(theta[free] + 0.01, -1)
  path <- build_original_collapse_path(p, 2, theta, free, k, bg, 101)
  for (i in c(1, 25, 50, 75, 101)) {
    expected <- dkrot(k, c(theta[fixed], path$angles[i, ]))
    stopifnot(max(abs(expected - path$rotations[[i]])) < 1e-12)
  }
  stopifnot(max(abs(path$rotations[[1]] - r)) < 1e-12,
            max(abs(tail(path$rotations, 1)[[1]][k, -k])) < 1e-12)
}

# Endpoint changes must converge quadratically with sample spacing: velocity
# interpolation approaches zero acceleration, rather than hiding a fixed jump.
for (anchors in 2:5) {
  for (shape in c(0.8, 1, 1.2)) {
    w1 <- blending_simplex_path(anchors, 101, shape)
    w2 <- blending_simplex_path(anchors, 201, shape)
    stopifnot(min(w1) >= -1e-12, max(abs(rowSums(w1) - 1)) < 1e-12,
              w1[1, 1] == 1, w1[101, anchors] == 1,
              max(abs(w2[2, ] - w2[1, ])) < 0.3 * max(abs(w1[2, ] - w1[1, ])))
  }
}
for (ends in list(c(0.025, 0.025), c(0.02, 0.025), c(-0.03, -0.025))) {
  needed <- sign(ends[1]) * 1.1234
  steps <- generate_smooth_rotation_steps(ends[1], ends[2], needed)
  stopifnot(abs(sum(steps) - needed) < 1e-12,
            abs(steps[1] - ends[1]) < 1e-12,
            abs(tail(steps, 1) - ends[2]) < 1e-12,
            all(sign(steps) == sign(ends[1])))
}

for (seed in c(1, 3, 11)) {
  a <- generate_incremental_animation(k = 5, nrots = 360, seed = seed, nrep = 3)
  validate_incremental_animation(a)
  stopifnot(length(a$rot_mats) %% 2 == 0)
  stopifnot(identical(as.integer(rle(a$n_dim_per_tim)$values), c(1:5, 4:1)))
  for (fit in a$backwards_rotations) {
    stopifnot(length(fit$R_mats) == fit$n_steps, fit$alignment_error < 1e-8)
    valid <- vapply(fit$res, function(x) is.null(x$error), logical(1))
    stopifnot(fit$selected_candidate == which.min(vapply(fit$res, function(x) x$value, numeric(1))))
    for (candidate in fit$res[valid]) {
      stopifnot(length(candidate$refined$path$rotations) == candidate$n_steps)
    }
  }
}
a3 <- generate_incremental_animation(k = 3, nrots = 180, seed = 1, nrep = 3)
validate_incremental_animation(a3)
stopifnot(identical(as.integer(rle(a3$n_dim_per_tim)$values), c(1:3, 2:1)))
cat("Incremental rotation checks passed.\n")
