validate_incremental_animation <- function(animation, out = NULL) {
  a <- animation
  k <- a$k
  rotations <- a$rot_mats
  orthogonality <- max(vapply(rotations, function(r) max(abs(crossprod(r) - diag(k))), numeric(1)))
  alignment <- max(vapply(a$backwards_rotations, function(f) f$alignment_error, numeric(1)))
  if (orthogonality > 1e-9 || alignment > 1e-8) stop("Invalid rotation trajectory")
  endpoints <- function(p) p[c(which.min(p[, 1]), which.max(p[, 1])), , drop = FALSE]
  first <- endpoints(a$hcubes_proj[[1]])
  last <- endpoints(tail(a$hcubes_proj, 1)[[1]]) %*% t(rotations[[1]][1:2, 1:2])
  seam <- min(max(abs(first - last)), max(abs(first - last[2:1, ])))
  if (seam > 1e-7) stop("Projected loop seam did not close: ", seam)
  angles <- t(vapply(rotations, undokrot, numeric(choose(k, 2))))
  speed <- sqrt(rowSums(angles^2)) * 60
  # Matrix differences avoid branch ambiguity in Givens angles at joins.
  change <- vapply(seq_along(rotations), function(i) {
    previous <- if (i == 1) tail(rotations, 1)[[1]] else rotations[[i - 1]]
    sqrt(sum((rotations[[i]] - previous)^2)) * 60^2
  }, numeric(1))
  result <- c(orthogonality_error = orthogonality, alignment_error = alignment,
              projected_seam_error = seam, screen_step_min = min(angles[, 1]),
              screen_step_max = max(angles[, 1]), step_norm_min = min(speed),
              step_norm_max = max(speed), max_step_change = max(change))
  if (min(angles[, 1]) * max(angles[, 1]) <= 0) stop("Screen-plane incremental rotation reversed")
  if (!is.null(out)) {
    write.table(data.frame(metric = names(result), value = result),
                file.path(out, "validation.tsv"), row.names = FALSE, sep = "\t")
    write.csv(data.frame(frame = seq_along(rotations), dimension = a$n_dim_per_tim,
                         speed = speed, step_change = change), file.path(out, "motion.csv"), row.names = FALSE)
    png(file.path(out, "motion.png"), width = 1200, height = 800, type = "cairo")
    par(mfrow = c(3, 1), mar = c(3, 4, 2, 1))
    time <- (seq_along(rotations) - 1) / 60
    plot(time, a$n_dim_per_tim, type = "s", ylab = "Stage dimension", xlab = "Seconds")
    plot(time, speed, type = "l", ylab = "Step angle norm / s", xlab = "Seconds")
    plot(time, angles[, 1] * 60, type = "l", ylab = "Screen plane rad / s", xlab = "Seconds")
    dev.off()
  }
  print(result)
  invisible(result)
}
