run_unit_tests <- function(verbose = TRUE) {
  if (verbose) cat("Testing topology, rigid rotations, dimension stages, and continuity...\n")
  near <- function(actual, expected, tolerance = 1e-10) {
    stopifnot(max(abs(actual - expected)) < tolerance)
  }
  must_fail <- function(expr) {
    stopifnot(inherits(tryCatch({ force(expr); NULL }, error = identity), "error"))
  }

  for (k in 1:10) {
    vertices <- generate_hypercube_vertices(k)
    edges <- generate_hypercube_edges(k)
    faces <- generate_hypercube_faces(k)
    stopifnot(nrow(vertices) == 2^k, nrow(edges) == k * 2^(k - 1),
              nrow(faces) == if (k == 1) 0 else choose(k, 2) * 2^(k - 2),
              !anyDuplicated(data.frame(edges)))
    near(rowSums((vertices[edges[, 1], , drop = FALSE] -
                    vertices[edges[, 2], , drop = FALSE])^2), 1)
    stopifnot(all(tabulate(as.vector(edges), nbins = nrow(vertices)) == k))
    if (nrow(faces)) {
      for (j in 1:4) {
        next_j <- j %% 4 + 1L
        near(rowSums((vertices[faces[, j], , drop = FALSE] -
                        vertices[faces[, next_j], , drop = FALSE])^2), 1)
      }
    }
  }

  for (k in c(1:10, 16)) {
    plan <- build_animation_plan(k)
    holds <- plan$schedule[plan$schedule$kind == "hold", ]
    expected <- if (k == 1) 1 else c(seq_len(k), seq.int(k - 1, 1))
    stopifnot(identical(as.numeric(holds$to), as.numeric(expected)))
    for (i in seq_len(nrow(holds))) {
      state <- animation_state(plan, mean(c(holds$start[i], holds$end[i])))
      d <- holds$to[i]
      stopifnot(state$visible_dimension == d)
      near(state$gates, as.numeric(seq_len(k) <= d))
      near(crossprod(state$pose), diag(k + 1))
      near(det(state$pose), 1)
      if (d < k) near(state$projection[seq.int(d + 1L, k), , drop = FALSE], 0)
      stopifnot(all(rowSums(state$projection[seq_len(d), , drop = FALSE]^2) > 1e-5))
      if (d == 1) near(sum(state$projection[1, ]^2), 1)
      if (d == 2) near(tcrossprod(state$projection[1:2, ]), diag(2))
      if (k <= 10) {
        xy <- generate_hypercube_vertices(k) %*% state$projection
        stopifnot(nrow(unique(round(xy, 9))) == 2^d)
      }
    }
    for (time in seq(0, plan$duration_seconds, length.out = 19)) {
      state <- animation_state(plan, time)
      near(crossprod(state$pose), diag(k + 1))
      near(det(state$pose), 1)
      stopifnot(all(state$gates >= 0), all(state$gates <= 1))
    }
    diagnostics <- animation_diagnostics(plan)
    stopifnot(max(diagnostics$velocity_mismatch) < 1e-6,
              max(diagnostics$acceleration_mismatch) < 0.01)
    # Check the limit from inside the cycle, not merely modulo(T) == modulo(0).
    near(animation_state(plan, plan$duration_seconds - 1e-8)$pose,
         animation_state(plan, 0)$pose, 1e-7)
    near(animation_state(plan, -0.1)$pose,
         animation_state(plan, plan$duration_seconds - 0.1)$pose)
  }

  plan <- build_animation_plan(5)
  vertices <- cbind(generate_hypercube_vertices(5), 0)
  rotated <- vertices %*% t(animation_state(plan, 21.3)$pose)
  near(as.matrix(dist(vertices)), as.matrix(dist(rotated)))

  # Halving the probe interval must reduce boundary derivative discrepancies.
  boundaries <- unique(c(plan$schedule$start, plan$schedule$end))
  jump <- function(h, order) max(vapply(boundaries, function(t) {
    p <- lapply(t + (-2:2) * h, function(s) animation_state(plan, s)$projection)
    if (order == 1) {
      max(abs((3 * p[[3]] - 4 * p[[2]] + p[[1]]) / (2 * h) -
                (-3 * p[[3]] + 4 * p[[4]] - p[[5]]) / (2 * h)))
    } else {
      max(abs((p[[3]] - 2 * p[[2]] + p[[1]]) / h^2 -
                (p[[5]] - 2 * p[[4]] + p[[3]]) / h^2))
    }
  }, numeric(1)))
  stopifnot(jump(0.001, 1) < 0.4 * jump(0.002, 1),
            jump(0.001, 2) < 0.6 * jump(0.002, 2))

  a <- generate_hypercube_animation(3, fps = 24, target_seconds = 12)
  b <- generate_hypercube_animation(3, fps = 48, target_seconds = 12)
  stopifnot(length(a$states) == 288L, max(a$times) == 12 - 1 / 24)
  for (i in seq_along(a$states)) near(a$states[[i]]$pose, b$states[[2 * i - 1]]$pose)
  other_seed <- build_animation_plan(3, seed = 12)
  stopifnot(max(abs(animation_state(a$config, 6)$projection -
                     animation_state(other_seed, 24)$projection)) > 0.01)
  # Continuous positive screen rotation remains active when only the line is visible.
  p0 <- animation_state(a$config, 0)$projection[1, ]
  p1 <- animation_state(a$config, 0.001)$projection[1, ]
  stopifnot(p0[1] * p1[2] - p0[2] * p1[1] > 0)
  for (bad in list(0, 2.5, NA_real_, Inf, 17)) must_fail(build_animation_plan(bad))
  must_fail(build_animation_plan(9, target_seconds = 1))
  must_fail(build_animation_plan(3, base_turns = 0.5))
  must_fail(build_animation_plan(3, wobble = 1))
  if (verbose) cat("All checks passed (k = 1..10 and 16; every stage boundary and loop seam).\n")
  invisible(TRUE)
}
