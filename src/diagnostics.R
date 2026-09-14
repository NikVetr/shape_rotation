animation_diagnostics <- function(plan) {
  boundaries <- unique(c(plan$schedule$start, plan$schedule$end))
  eps <- min(plan$schedule$end - plan$schedule$start) * 1e-4
  position <- velocity <- acceleration <- numeric(length(boundaries))
  for (i in seq_along(boundaries)) {
    t <- boundaries[i]
    p <- lapply(t + (-3:3) * eps, function(s) animation_state(plan, s)$projection)
    position[i] <- max(abs(p[[5]] - p[[3]]))
    left_v <- (3 * p[[4]] - 4 * p[[3]] + p[[2]]) / (2 * eps)
    right_v <- (-3 * p[[4]] + 4 * p[[5]] - p[[6]]) / (2 * eps)
    velocity[i] <- max(abs(left_v - right_v))
    left_a <- (2 * p[[4]] - 5 * p[[3]] + 4 * p[[2]] - p[[1]]) / eps^2
    right_a <- (2 * p[[4]] - 5 * p[[5]] + 4 * p[[6]] - p[[7]]) / eps^2
    acceleration[i] <- max(abs(left_a - right_a))
  }
  data.frame(time = boundaries, position_across_epsilon = position,
             velocity_mismatch = velocity, acceleration_mismatch = acceleration)
}

print_animation_diagnostics <- function(result) {
  plan <- result$config
  diagnostics <- animation_diagnostics(plan)
  cat(sprintf("%d-cube loop: %d frames, %.3f seconds, %d fps\n",
              plan$k, plan$n_frames, plan$duration_seconds, plan$fps))
  cat(sprintf("Largest boundary velocity mismatch (finite difference): %.3g\n",
              max(diagnostics$velocity_mismatch)))
  cat(sprintf("Largest boundary acceleration mismatch (finite difference): %.3g\n",
              max(diagnostics$acceleration_mismatch)))
  invisible(diagnostics)
}
