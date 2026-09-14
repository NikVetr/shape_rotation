# Copied from deprecated/; edited here. See docs/repair_notes.md.

vectorize_skew_symmetric <- function(A) {
  k <- nrow(A)
  if (k < 2) return(numeric(0))
  p <- A[upper.tri(A)]
  return(p)
}

reconstruct_skew_symmetric <- function(p, k) {
  expected_len <- k * (k - 1) / 2
  if (length(p) != expected_len) {
    stop(paste("Incorrect number of parameters. Expected", expected_len, "but got", length(p), "for dimension k =", k))
  }
  A <- matrix(0, k, k)
  if (k < 2) return(A)
  A[upper.tri(A)] <- p
  A <- A - t(A)
  return(A)
}

random_skew_symmetric <- function(k) {
  M <- matrix(rnorm(k * k), nrow = k)
  A <- M - t(M)
  return(A)
}

skew_to_rot <- function(A){
  k <- dim(A)[1]
  R <- expm(A)
  svd_res <- svd(R)
  R <- svd_res$u %*% diag(c(rep(1, k-1), det(svd_res$u %*% t(svd_res$v)))) %*% t(svd_res$v)
  return(R)
}

random_rotation_matrix <- function(k) {
  A <- random_skew_symmetric(k)
  return(skew_to_rot(A))
}

rot_to_skew <- function(R){
  logR <- expm::logm(R)
  skew <- 0.5 * (logR - t(logR))
  return(skew)
}

angular_velocity <- function(R, delta_t = 1) {
  k <- nrow(R)
  svd_res <- svd(R)
  det_uv <- det(svd_res$u %*% t(svd_res$v))
  diag_mat <- diag(c(rep(1, k - 1), det_uv))
  R_proj <- svd_res$u %*% diag_mat %*% t(svd_res$v)

  if (norm(R_proj - diag(k), type = "F") < sqrt(.Machine$double.eps) * k) {
    return(0)
  }
  logm_R <- try(logm(R_proj), silent = TRUE)
  if(inherits(logm_R, "try-error")){
    warning("logm failed in angular_velocity")
    # What to return? 0 might bias variance down, NA needs handling. Let's try 0.
    return(0)
  }
  A_skew <- 0.5 * (logm_R - t(logm_R))
  omega_mag <- norm(A_skew, type = "F") / sqrt(2)
  return(max(0, omega_mag / delta_t))
}

blend_skew_symmetric <- function(A1, A2, w, method = c("lie_group", "linear")) {
  method <- match.arg(method)

  if (!all(dim(A1) == c(3, 3)) || !all(dim(A2) == c(3, 3))) {
    stop("Both A1 and A2 must be 3x3 matrices.")
  }
  if (abs(w) > 1) stop("w should be between 0 and 1.")

  if (method == "linear") {
    return((1 - w) * A1 + w * A2)
  }

  if (!requireNamespace("expm", quietly = TRUE)) {
    stop("Please install the 'expm' package: install.packages('expm')")
  }

  R1 <- expm::expm(A1)
  R2 <- expm::expm(A2)

  # Interpolated rotation matrix
  R_blend <- R1 %*% expm::expm(w * expm::logm(t(R1) %*% R2))

  # Return the skew-symmetric matrix that generates this
  A_blend <- 0.5 * (expm::logm(R_blend) - t(expm::logm(R_blend)))
  return(A_blend)
}

blending_weights <- function(n, shape = 0) {
  stopifnot(n >= 1) # Can have n=1
  if (n == 1) return(0)
  t <- seq(0, 1, length.out = n)
  if (is.na(shape) || shape == 0) {
    w <- t
  } else {
    shape <- max(-5, min(5, shape))
    a <- 10^shape
    raw_w <- 1 / (1 + exp(-a * (t - 0.5)))
    min_w <- raw_w[1]
    max_w <- raw_w[n]
    if (abs(max_w - min_w) < .Machine$double.eps) {
      w <- t
    } else {
      w <- (raw_w - min_w) / (max_w - min_w)
    }
  }
  w[1] <- 0
  w[n] <- 1 # Ensure ends are exact
  return(w)
}

blending_simplex_path <- function(k, n, shape = 2, pow_ends = 2) {
  stopifnot(k >= 2, n >= 2, is.finite(shape), pow_ends >= 1)
  a <- 10^shape
  # Preserve the logistic-simplex shape, with zero angular acceleration at joins.
  t_grid <- (1 - cos(pi * seq(0, 1, length.out = n))) / 2
  t_breaks <- seq(0, 1, length.out = k + 1)
  weights <- vapply(seq_len(k), function(i) {
    plogis(a * (t_grid - t_breaks[i])) - plogis(a * (t_grid - t_breaks[i + 1]))
  }, numeric(n))
  weights_pow <- abs(t_grid * 2 - 1)^pow_ends * max(0, pow_ends - 1) + 1
  weights <- weights^weights_pow
  weights <- weights / rowSums(weights)
  cumulative <- t(apply(weights, 1, cumsum))[, seq_len(k - 1L), drop = FALSE]
  for (j in seq_len(k - 1L)) {
    cumulative[, j] <- (cumulative[, j] - cumulative[n, j]) /
      (cumulative[1, j] - cumulative[n, j])
  }
  weights <- cbind(cumulative, 1) - cbind(0, cumulative)
  if (min(weights) < -1e-12 || any(!is.finite(weights))) stop("Invalid simplex blend")
  weights[abs(weights) < 1e-14] <- 0
  weights
}

rotation_distance <- function(R1, R2) {
  k <- nrow(R1)
  R_rel <- try(t(R1) %*% R2, silent=TRUE)
  if(inherits(R_rel, "try-error")){
    warning("Matrix multiplication failed in rotation_distance (t(R1) %*% R2)")
    return(pi) # Return a large distance like pi?
  }

  svd_res <- svd(R_rel)
  det_uv <- det(svd_res$u %*% t(svd_res$v))
  diag_mat <- diag(c(rep(1, k - 1), det_uv))
  R_rel_proj <- svd_res$u %*% diag_mat %*% t(svd_res$v)

  if (norm(R_rel_proj - diag(k), type = "F") < sqrt(.Machine$double.eps) * k) {
    return(0)
  }

  A <- try(logm(R_rel_proj), silent=TRUE)
  if(inherits(A, "try-error")){
    warning("logm failed in rotation_distance")
    return(pi) # Return a large distance
  }
  A_skew <- 0.5 * (A - t(A))
  d <- norm(A_skew, type = "F") / sqrt(2)
  return(max(0, d)) # Ensure non-negative
}

compute_rotmat <- function(angles, rotmat, k){
  bigrm <- diag(k)
  bigrm[angles$V1, angles$V1] <- rotmat[1,1]
  bigrm[angles$V1, angles$V2] <- rotmat[1,2]
  bigrm[angles$V2, angles$V1] <- rotmat[2,1]
  bigrm[angles$V2, angles$V2] <- rotmat[2,2]
  bigrm
}

compute_rotmat_theta <- function(angles, theta, k){
  bigrm <- diag(k)
  bigrm[angles$X1, angles$X1] <- cos(theta)
  bigrm[angles$X1, angles$X2] <- -sin(theta)
  bigrm[angles$X2, angles$X1] <- sin(theta)
  bigrm[angles$X2, angles$X2] <- cos(theta)
  bigrm
}

undokrot <- function(rotmat) {
  k <- nrow(rotmat)
  # list of plane pairs in the same order as dkrot
  planes <- t(combn(k, 2))  # same ordering as in `dkrot()`
  planes <- planes[order(apply(planes, 1, max)),]
  N <- nrow(planes)

  # We will have: rotmat = G_1 * G_2 * ... * G_N
  # We want to peel off G_1, then G_2, etc., from the LEFT side in that order.

  # Start with the matrix we want to factor
  R <- rotmat
  thetas <- numeric(N)

  for (i in seq_len(N)) {
    i1 <- planes[i,1]
    i2 <- planes[i,2]

    # Solve for G_i from the left factor:
    #   R = G_i * M   ==>   M = G_i^{-1} * R = G_i^T * R
    # But we first need to figure out the angle used by G_i in the original (i1,i2) plane.

    # G_i^T is also a rotation in the same (i1,i2) plane, but we have to measure it correctly
    # from R. The sub-block R[i1, c(i1,i2); i2, c(i1,i2)] is already "contaminated" by G_2..G_N.
    #
    # There's no trivial one-liner to do this. We must find the angle that un-rotates R's columns
    # i1 and i2 back to something orthonormal in the original plane. The safest approach is to
    # re-embed the basis as we go.

    # One approach: look at columns i1 and i2 of R to see how the standard basis e_i1, e_i2
    # got rotated. Then deduce the rotation angle from those 2 vectors.
    #
    # Let v1 = R[,i1], v2 = R[,i2]. In an "ideal" scenario (kD rotation), these should be orthonormal
    # if R is orthonormal. The angle in plane (i1,i2) is the angle between the projections
    # of v1, v2 onto that plane and the original axes. This is complicated to do in a short snippet.

    # Pseudocode approach (not fully fleshed out):
    #
    # 1) let e1 = unit vector with 1 in position i1, 0 in others
    #    let e2 = unit vector with 1 in position i2, 0 in others
    # 2) find out how those got mapped by R => r1 = R %*% e1, r2 = R %*% e2
    # 3) in principle, G_i was the rotation that took e1->r1', e2->r2' before
    #    the next factors changed them further. So we have to solve or guess from geometry.
    #
    # Because so many frames have changed, you'd have to do a partial backward approach
    # or store partial products.

    # => In practice, doing the exact left-to-right peeling to get the same angles is quite complex.
    #    Usually you store the partial products if you need the same angles.

    # (for illustration, let's pretend we do a "standard" Givens extraction, but
    #  it won't produce the same angles as the original.)

    # Here is the typical "standard" approach that zeroes out R[i2,i1]:
    r  <- sqrt(R[i1,i1]^2 + R[i2,i1]^2)
    c  <- R[i1,i1]/r
    s  <- R[i2,i1]/r
    theta <- atan2(s, c)
    thetas[i] <- theta

    # Left-multiply R by G_i^T to peel it off
    GiT <- diag(k)
    GiT[i1,i1] <- c
    GiT[i1,i2] <- s
    GiT[i2,i1] <- -s
    GiT[i2,i2] <- c

    R <- GiT %*% R  # now we've peeled off G_i, conceptually
  }

  # 'thetas' are the angles from a standard row-by-row Givens factorization approach
  # with the same plane order, but it still won't match the original angles from 'dkrot()'.

  return(thetas)
}

blendRotations <- function(thetas1, thetas2, w = 0.5,
                           method = c("linear", "geodesic")) {
  method <- match.arg(method)

  # Sanity checks
  if (length(thetas1) != length(thetas2)) {
    stop("theta1 and theta2 must have the same length.")
  }
  if (w < 0 || w > 1) {
    stop("w must be in [0,1].")
  }

  # Infer k from length(thetas1) = choose(k,2)
  # Solve k*(k-1)/2 = length(thetas1)
  # E.g. find integer k that satisfies the equation
  nTheta <- length(thetas1)
  # Not the most robust but works for typical small k
  k <- which( (seq_len(100)*(seq_len(100)-1))/2 == nTheta )
  if (length(k) != 1) {
    stop("Could not infer a unique k from length(thetas1). Please specify or check your inputs.")
  }

  if (method == "linear") {
    # Naive angle-wise interpolation
    theta_blend <- (1 - w)*thetas1 + w*thetas2
    Rblend <- dkrot(k, theta_blend)
    return(Rblend)
  } else if (method == "geodesic") {
    # Shortest path on SO(k)
    # R(t) = R1 * exp(t * log(R1^T * R2)), for t in [0,1]

    # 1) Construct the two rotation matrices
    R1 <- dkrot(k, thetas1)
    R2 <- dkrot(k, thetas2)

    # 2) Use matrix log/expm for the geodesic
    #    Rblend = R1 * exp( w * log( R1^T * R2 ) )
    library(expm)         # for expm(), logm()
    M <- logm(t(R1) %*% R2)
    Rblend <- R1 %*% expm(w * M)

    return(Rblend)
  }
}

blend_givens <- function(thetas1, thetas2, w = 0.5,
                         method = c("linear", "geodesic")) {
  method <- match.arg(method)

  # Sanity checks
  if (length(thetas1) != length(thetas2)) {
    stop("theta1 and theta2 must have the same length.")
  }
  if (w < 0 || w > 1) {
    stop("w must be in [0,1].")
  }

  # Infer k from length(thetas1) = choose(k,2)
  # Solve k*(k-1)/2 = length(thetas1)
  # E.g. find integer k that satisfies the equation
  nTheta <- length(thetas1)
  # Not the most robust but works for typical small k
  k <- which( (seq_len(100)*(seq_len(100)-1))/2 == nTheta )
  if (length(k) != 1) {
    stop("Could not infer a unique k from length(thetas1). Please specify or check your inputs.")
  }

  if (method == "linear") {
    # Naive angle-wise interpolation
    theta_blend <- (1 - w)*thetas1 + w*thetas2
    Rblend <- dkrot(k, theta_blend)
    return(Rblend)
  } else if (method == "geodesic") {
    # Shortest path on SO(k)
    # R(t) = R1 * exp(t * log(R1^T * R2)), for t in [0,1]

    # 1) Construct the two rotation matrices
    R1 <- dkrot(k, thetas1)
    R2 <- dkrot(k, thetas2)

    # 2) Use matrix log/expm for the geodesic
    #    Rblend = R1 * exp( w * log( R1^T * R2 ) )
    library(expm)         # for expm(), logm()
    M <- logm(t(R1) %*% R2)
    Rblend <- R1 %*% expm(w * M)

    return(Rblend)
  }
}

dkrot_info <- function(k, thetas) {
  planes <- t(combn(k, 2))  # same ordering as in `dkrot()`
  planes <- data.frame(planes[order(apply(planes, 1, max)),])
  big_rotmats <- lapply(1:choose(k, 2), function(i){
    compute_rotmat_theta(planes[i,], thetas[i], k)
  })
  return(list(planes = planes,
              big_rotmats = big_rotmats))
}

dkrot_premult <- function(k,
                          thetas_remaining,
                          planes_remaining,
                          precomputed_bg) {
  big_rotmats_remaining <- lapply(1:length(thetas_remaining), function(i){
    compute_rotmat_theta(planes_remaining[i,], thetas_remaining[i], k)
  })
  rotmat <- Reduce("%*%", c(list(precomputed_bg), big_rotmats_remaining))
  rotmat
}

invlogit <- function(x) plogis(x)

collapse_objective_givens <- function(p, n_p, theta_init, p_inds, p_fixed = NULL,
    hcube_init, angular_vel_fun, dkrot, k, precomputed_bg, planes_remaining,
    print_loss = FALSE, loss_weights, n_steps) {
  path <- build_original_collapse_path(p, n_p, theta_init, p_inds, k, precomputed_bg, n_steps)
  endpoint <- hcube_init %*% t(path$cumulative)
  alignment_loss <- sum((abs(endpoint[, k]) - 0.5)^2) * loss_weights[1]
  controls <- matrix(p[seq_len((n_p - 1L) * length(p_inds))], n_p - 1L,
                      length(p_inds), byrow = TRUE)
  deviation <- sum(sweep(controls, 2, theta_init[p_inds])^2) * loss_weights[2]
  shape_loss <- abs(p[length(p)] + 1)
  value <- alignment_loss + deviation + shape_loss
  if (print_loss) cat("alignment:", alignment_loss, "deviation:", deviation, "shape:", shape_loss, "\n")
  value
}

align_hypercube_axis <- function(hcube_coords, tol = 1e-9) {
  # --- Input Validation ---
  if (!is.matrix(hcube_coords) || !is.numeric(hcube_coords)) {
    stop("Input 'hcube_coords' must be a numeric matrix.")
  }
  n <- nrow(hcube_coords)
  k <- ncol(hcube_coords)
  if (k < 1) {
    stop("Input matrix must have at least one column (k >= 1).")
  }
  # Check if it looks like a hypercube (optional)
  # is_power_of_2 <- n > 0 && k >= 0 && ceiling(log2(n)) == floor(log2(n))
  # if (k > 0 && n != 2^k && is_power_of_2 && log2(n) != k) {
  #   warning(paste("Number of rows (", n, ") suggests dimension", log2(n), "but number of columns is k =", k))
  # } else if (k > 0 && !is_power_of_2) {
  #   warning(paste("Number of rows (", n, ") is not 2^k for k =", k, ". Input might not be a hypercube."))
  # }

  if (k == 1) {
    warning("k=1, rotation is trivial (identity matrix).")
    # Calculate side length even for k=1
    min_val <- min(hcube_coords[,1])
    max_val <- max(hcube_coords[,1])
    side_length = max_val - min_val
    return(list(rotation_matrix = matrix(1, 1, 1),
                rotated_coords = hcube_coords,
                side_length = side_length))
  }

  # --- Identify Hypercube Axis corresponding to last coordinate separation ---
  # Use the median of the last coordinate to split the points
  last_col_median <- median(hcube_coords[, k])
  group1_indices <- which(hcube_coords[, k] < last_col_median)
  group2_indices <- which(hcube_coords[, k] >= last_col_median)

  # Check if split is reasonable
  if (length(group1_indices) == 0 || length(group2_indices) == 0) {
    stop("Could not separate points based on the last coordinate. Is the input degenerate or already aligned perfectly?")
  }
  # For a hypercube, expect n/2 points in each group
  if (n == 2^k && (length(group1_indices) != n/2 || length(group2_indices) != n/2)) {
    warning(paste("Split based on median of last column resulted in uneven groups (",
                  length(group1_indices), "vs", length(group2_indices),
                  "). This might indicate precision issues or non-standard hypercube input.",
                  "Proceeding with calculated centroids."))
  }

  center1 <- colMeans(hcube_coords[group1_indices, , drop = FALSE])
  center2 <- colMeans(hcube_coords[group2_indices, , drop = FALSE])

  # This vector represents the direction (and length) of the hypercube's axis
  # that currently separates the points along the k-th dimension.
  u_direction <- center2 - center1

  # Calculate the side length along this axis
  side_length <- sqrt(sum(u_direction^2))
  if (side_length < tol) {
    stop("Hypercube seems collapsed along the k-th dimension axis (side length is near zero).")
  }

  # Normalize the direction vector
  u_norm <- u_direction / side_length

  # --- Define Target Vector ---
  # We want to align u_norm with the k-th standard basis vector e_k
  e_k <- c(rep(0, k - 1), 1)

  # --- Calculate Rotation Matrix R ---
  # R maps u_norm to e_k. We use the method based on reflections.
  # R = H_ek %*% H_prime, where H_prime maps u_norm -> -e_k, and H_ek maps -e_k -> e_k

  # Handle edge case: u_norm is already aligned with e_k
  if (sqrt(sum((u_norm - e_k)^2)) < tol) {
    R <- diag(k) # Identity matrix
    # Handle edge case: u_norm is anti-aligned with e_k
  } else if (sqrt(sum((u_norm + e_k)^2)) < tol) {
    # Need 180-degree rotation mapping -e_k to e_k. det(R) must be 1.
    # Rotate 180 degrees in the (x1, xk) plane.
    R <- diag(k)
    R[1, 1] <- -1
    R[k, k] <- -1
    # General case: use the reflection method
  } else {
    # H_prime = I - 2*outer(v,v)/dot(v,v), where v = u_norm + e_k
    v_prime <- u_norm + e_k
    v_prime_outer <- outer(v_prime, v_prime)
    v_prime_dot <- sum(v_prime^2) # Guaranteed > 0 because u_norm != -e_k

    H_prime <- diag(k) - 2 * v_prime_outer / v_prime_dot

    # H_ek reflects across the hyperplane orthogonal to e_k (flips k-th coord)
    H_ek <- diag(k)
    H_ek[k,k] <- -1
    # H_ek = diag(c(rep(1, k - 1), -1)) # Equivalent

    # The rotation R = H_ek %*% H_prime maps u_norm to e_k
    R <- H_ek %*% H_prime
  }

  rotated_coords <- hcube_coords %*% t(R)

  # --- Return Results ---
  return(list(rotation_matrix = R,
              rotated_coords = rotated_coords,
              side_length = side_length))
}

collapse_hcube <- function(hcube_init, R_init, n_steps = 100, n_p = 2, nrep = 10,
                           n_steps_range = 0.1, trace = 0,
                           cores = getOption("hypercube.cores", 1L)) {
  k <- nrow(R_init)
  stopifnot(k >= 3, n_p >= 2, nrep >= 1, n_steps >= 4, n_steps_range >= 0, n_steps_range < 1)
  n_angles <- choose(k, 2)
  fixed <- seq_len(choose(k - 1, 2))
  free <- seq.int(choose(k - 1, 2) + 1L, n_angles)
  theta_init <- undokrot(R_init)
  if (max(abs(dkrot(k, theta_init) - R_init)) > 1e-9) stop("Givens reconstruction failed")
  info <- dkrot_info(k, theta_init)
  precomputed_bg <- Reduce("%*%", info$big_rotmats[fixed])
  planes_remaining <- info$planes[free, , drop = FALSE]
  p_init <- c(rep(theta_init[free], n_p - 1L), shape_blend = -1)
  n_steps_vec <- if (nrep == 1) round(n_steps) else
    round(n_steps * seq(1 - n_steps_range, 1 + n_steps_range, length.out = nrep))
  starts <- replicate(nrep, p_init, simplify = FALSE)
  if (nrep > 1) {
    for (i in 2:nrep) {
      # These are small PER-FRAME angles. Wrapping negative perturbations through
      # 2*pi created spurious full turns; the shape parameter is not an angle.
      starts[[i]][-length(p_init)] <- p_init[-length(p_init)] +
        runif(length(p_init) - 1L, -1, 1) * max(0.005, 2 * max(abs(theta_init)))
      starts[[i]][length(p_init)] <- -1 + runif(1, -0.25, 0.25)
    }
  }
  cat(sprintf("Collapsing %d-cube: %d timing/restart candidates (%d..%d steps)\n",
              k, nrep, min(n_steps_vec), max(n_steps_vec)))
  fit_one <- function(i) {
    tryCatch({
      objective <- function(p, weights) collapse_objective_givens(p, n_p, theta_init, free,
        hcube_init = hcube_init, angular_vel_fun = angular_velocity, dkrot = dkrot, k = k,
        precomputed_bg = precomputed_bg, planes_remaining = planes_remaining,
        loss_weights = weights, n_steps = n_steps_vec[i])
      first <- optim(starts[[i]], objective, weights = c(1, 5), method = "L-BFGS-B",
                      control = list(maxit = 40, trace = trace))
      final <- optim(first$par, objective, weights = c(5, 1), method = "L-BFGS-B",
                      control = list(maxit = 20, trace = trace))
      path_function <- function(p) build_original_collapse_path(p, n_p, theta_init, free, k,
                                                               precomputed_bg, n_steps_vec[i])
      refined <- refine_original_collapse(final$par, path_function, hcube_init)
      final$par <- refined$parameters
      # Compare the actual trajectory/duration that each candidate optimized.
      list(res_final = final, value = objective(final$par, c(1, 5)),
           refined = refined, n_steps = n_steps_vec[i], error = NULL)
    }, error = function(e) list(value = Inf, error = conditionMessage(e), n_steps = n_steps_vec[i]))
  }
  results <- if (cores > 1 && nrep > 1) parallel::mclapply(seq_len(nrep), fit_one,
    mc.cores = min(cores, nrep), mc.set.seed = FALSE) else lapply(seq_len(nrep), fit_one)
  failed <- vapply(results, function(x) !is.null(x$error), logical(1))
  if (any(failed)) {
    cat("Rejected candidates:", paste(which(failed), collapse = ", "), "\n")
    cat(paste(unique(vapply(results[failed], function(x) x$error, character(1))), collapse = "\n"), "\n")
  }
  if (all(failed)) stop("No collapse candidate met the alignment constraints")
  best <- which.min(vapply(results, function(x) x$value, numeric(1)))
  selected <- results[[best]]
  path <- selected$refined$path
  hcube_end <- hcube_init %*% t(path$cumulative)
  if (max(abs(abs(hcube_end[, k]) - 0.5)) > 1e-8) stop("Collapsed coordinates failed validation")
  if (max(abs(path$rotations[[1]] - R_init)) > 1e-9) stop("Initial angular velocity changed at the join")
  if (max(abs(path$rotations[[length(path$rotations)]][k, -k])) > 1e-12) {
    stop("The ending velocity would reveal the collapsed axis again")
  }
  list(hcube_end = hcube_end, R_mats = path$rotations, cumulative_R = path$cumulative,
       final_rotation = list(rotation_matrix = diag(k)),
       mean_abs_deviation_from_R_init = vapply(path$rotations, function(x) mean(abs(x - R_init)), numeric(1)),
       mean_abs_deviation_from_givens = rowMeans(abs(sweep(path$angles, 2, theta_init[free]))),
       n_steps = selected$n_steps, res = results, best_res = selected$res_final,
       alignment_error = selected$refined$error, selected_candidate = best)
}

find_min_directed_rotation <- function(curr_line, starting_line, curr_rot_angle, tolerance = 1e-9) {

  # --- Pre-calculations ---
  # Check for zero rotation case: only possible if already aligned
  if (abs(curr_rot_angle) < tolerance) {
    delta_coords <- starting_line - curr_line # Check direct match P1->S1, P2->S2
    delta_coords_swap <- starting_line[2:1, ] - curr_line # Check swapped match P1->S2, P2->S1

    aligned <- (all(abs(delta_coords) < tolerance) || all(abs(delta_coords_swap) < tolerance))
    return(if (aligned) 0 else NA_real_)
  }

  # Calculate angles and radii using vectorized operations
  a_curr <- atan2(curr_line[, 2], curr_line[, 1])
  a_start <- atan2(starting_line[, 2], starting_line[, 1])
  r_curr <- sqrt(rowSums(curr_line^2))
  r_start <- sqrt(rowSums(starting_line^2))

  possible_angles <- c()
  direction_sign <- sign(curr_rot_angle) # +1 for CCW, -1 for CW

  # --- Loop through pairings (curr index i to start index j) ---
  for (i in 1:2) {
    for (j in 1:2) {
      # Check radius match first
      if (abs(r_curr[i] - r_start[j]) < tolerance) {

        # Calculate raw angle difference (start - curr)
        delta_angle_raw <- a_start[j] - a_curr[i]

        # Normalize to [0, 2*pi) for CCW angle
        delta_ccw <- (delta_angle_raw %% (2 * pi) + 2 * pi) %% (2 * pi)

        # Calculate equivalent CW angle (-2*pi, 0]
        # Handle case where delta_ccw is ~0 (raw angle was 0 or multiple of 2*pi)
        delta_cw <- if (abs(delta_ccw) < tolerance) 0 else delta_ccw - 2 * pi

        # Add the angle corresponding to the desired rotation direction
        angle_to_consider <- if (direction_sign > 0) delta_ccw else delta_cw

        # Add to list if it's non-zero OR if raw difference was zero
        # Also filter out angles in the "wrong" direction (e.g., negative if positive required)
        # Allow angles very close to zero.
        if ( (abs(angle_to_consider) > tolerance || abs(delta_angle_raw) < tolerance) &&
             (sign(angle_to_consider) == direction_sign || abs(angle_to_consider) < tolerance) ) {
          possible_angles <- c(possible_angles, angle_to_consider)
        }
      }
    }
  }

  # --- Select Minimum Magnitude Angle in Correct Direction ---
  if (length(possible_angles) == 0) {
    warning("No possible alignment found for the specified direction and tolerance.")
    return(NA_real_)
  }

  # Remove duplicates caused by floating point noise near 0/2pi/-2pi etc.
  possible_angles <- unique(round(possible_angles / tolerance)) * tolerance

  # Filter again just to be safe (shouldn't be needed with check inside loop)
  possible_angles <- possible_angles[sign(possible_angles) == direction_sign | abs(possible_angles) < tolerance]

  if (length(possible_angles) == 0) {
    warning("No possible alignment found after final filtering.")
    return(NA_real_)
  }

  # Find the angle with the minimum absolute value *in the desired direction*
  result_angle <- if (direction_sign > 0) {
    min(possible_angles) # Smallest positive angle
  } else {
    max(possible_angles) # Largest negative angle (closest to 0 from below)
  }

  # Ensure exactly zero if result is within tolerance
  return(if (abs(result_angle) < tolerance) 0 else result_angle)
}

generate_smooth_rotation_steps <- function(curr_rot_angle,
                                                       starting_rot_angle,
                                                       rotation_needed,
                                                       tolerance = 1e-9,
                                                       step_multiple = 1L,
                                                       existing_steps = 0L) {

  # --- Input Validation and Edge Cases (mostly same as fixed_ends) ---
  # Check for Zero Rotation Needed
  if (abs(rotation_needed) < tolerance) {
    if (abs(curr_rot_angle) < tolerance && abs(starting_rot_angle) < tolerance) {
      return(numeric(0))
    } else if (abs(curr_rot_angle + starting_rot_angle) < tolerance) {
      # Achievable with N=2 if start = -end
      return(c(curr_rot_angle, starting_rot_angle))
    } else {
      warning("Target rotation is zero, but start/end angles don't allow for simple cancellation.")
      return(NA_real_)
    }
  }

  avg_angle_initial = (curr_rot_angle + starting_rot_angle) / 2

  # Check for Direction Conflict
  if (abs(avg_angle_initial) > tolerance && sign(rotation_needed) != sign(avg_angle_initial)) {
    warning("Required rotation direction conflicts with the average step direction.")
    return(NA_real_)
  }

  # --- Estimate Number of Steps (N) ---
  n_steps <- NA

  # Case 1: Start and End angles are the same
  if (abs(curr_rot_angle - starting_rot_angle) < tolerance) {
    if (abs(curr_rot_angle) < tolerance) {
      warning("Cannot reach non-zero rotation if start/end angles are zero.")
      return(NA_real_)
    }
    n_steps_est <- rotation_needed / curr_rot_angle
    if (n_steps_est < 1 - tolerance) {
      warning("Rotation needed cannot be achieved with constant positive angle steps.")
      return(NA_real_)
    }
    n_steps <- max(3, round(n_steps_est))
    if (n_steps == 1 && abs(rotation_needed - curr_rot_angle) > tolerance) {
      warning("Single step required but target rotation doesn't match start/end angle.")
      return(NA_real_)
    }
    # Integer duration generally leaves a residual even when end speeds match.
    # Distribute it through the same smooth interior correction used below.

  } else {
    # Case 2: Start and End angles differ
    if (abs(avg_angle_initial) < tolerance) {
      if (abs(curr_rot_angle + starting_rot_angle - rotation_needed) < tolerance) {
        n_steps <- 2 # N=2 is exact and the only possibility
      } else {
        warning("Average step angle is zero, cannot achieve this total rotation.")
        return(NA_real_)
      }
    } else {
      n_steps_est <- rotation_needed / avg_angle_initial
      n_steps <- max(2, round(n_steps_est))
      if(n_steps < 2) n_steps <- 2 # Force N>=2 for transition
    }
    # Check if N=2 works, otherwise force N=3 minimum for adjustment
    if (n_steps == 2 && abs(curr_rot_angle + starting_rot_angle - rotation_needed) > tolerance) {
      n_steps <- 3
    }
  }

  # --- Generate Final Step Angles ---
  # Keep the encoded loop on its sampling grid without a shortened final gap.
  n_steps <- round((existing_steps + n_steps) / step_multiple) * step_multiple - existing_steps
  while (n_steps < 3) n_steps <- n_steps + step_multiple

  # Handle N=1 (Should only be reached if start=end=needed)
  if (n_steps == 1) {
    # This case should have been fully handled by the start=end logic above
    return(curr_rot_angle)
  }

  # Handle N=2
  if (n_steps == 2) {
    # N=2 is only valid if start + end == needed (checked above)
    return(c(curr_rot_angle, starting_rot_angle))
  }

  # Handle N >= 3: Use smooth base + smooth adjustment
  if (n_steps >= 3) {
    # 1. Generate ideal smooth steps using cosine blend
    t <- (0:(n_steps - 1)) / (n_steps - 1)
    blend_factor <- (1 - cos(pi * t)) / 2
    ideal_step_angles <- curr_rot_angle + (starting_rot_angle - curr_rot_angle) * blend_factor

    # Verify ends (should be correct by construction)
    # ideal_step_angles[1] should be curr_rot_angle
    # ideal_step_angles[n_steps] should be starting_rot_angle

    # 2. Calculate sum error
    sum_ideal <- sum(ideal_step_angles)
    delta_sum <- rotation_needed - sum_ideal

    # If error is negligible, we are done
    if (abs(delta_sum) < tolerance) {
      return(ideal_step_angles)
    }

    # 3. Generate smooth adjustment profile (Sine based, zero at ends)
    # Squaring also makes the acceleration vanish at the endpoints.
    adjustment_profile <- sin(pi * t)^2
    # Ensure ends are exactly zero due to potential float issues
    adjustment_profile[1] <- 0
    adjustment_profile[n_steps] <- 0

    sum_profile <- sum(adjustment_profile)

    # 4. Calculate scaling factor for adjustment
    # Avoid division by zero if profile sum is somehow zero (e.g., N=2?)
    if (abs(sum_profile) < tolerance) {
      # This shouldn't happen for N>=3 unless delta_sum is also zero (handled above)
      # If delta_sum is non-zero but profile sum is zero, we cannot adjust smoothly.
      warning("Cannot apply smooth adjustment: Adjustment profile sum is zero.")
      # Fallback: return the unadjusted ideal steps? Or NA?
      # Returning ideal steps fails the sum constraint. NA is safer.
      return(NA_real_)
    }
    k <- delta_sum / sum_profile

    # 5. Apply adjustment
    final_step_angles <- ideal_step_angles + k * adjustment_profile

    # Ensure start/end are *exactly* the target values after float arithmetic
    final_step_angles[1] <- curr_rot_angle
    final_step_angles[n_steps] <- starting_rot_angle

    # Optional Verification: Check final sum
    # final_sum <- sum(final_step_angles)
    # print(paste("Final Sum Verification:", final_sum, "vs", rotation_needed))

    return(final_step_angles)
  }

  # Fallback
  warning("Failed to determine valid step count or configuration.")
  return(NA_real_)
}

build_original_collapse_path <- function(p, n_p, theta_init, p_inds, k,
                                          precomputed_bg, n_steps) {
  n_angles <- (n_p - 1L) * length(p_inds)
  if (length(p) != n_angles + 1L) stop("Collapse parameter count does not match n_p")
  anchors <- rbind(theta_init[p_inds], matrix(p[seq_len(n_angles)], n_p - 1L,
                                             length(p_inds), byrow = TRUE), 0)
  weights <- blending_simplex_path(n_p + 1L, n_steps,
                                    shape = 0.8 + plogis(p[length(p)]) * 0.4, pow_ends = 2)
  angles <- weights %*% anchors
  rotations <- lapply(seq_len(n_steps), function(i) {
    out <- precomputed_bg
    # Equivalent to the original precomputed_bg %*% G_1k %*% ... %*% G_(k-1)k.
    for (j in seq_len(k - 1L)) {
      x <- out[, j]; y <- out[, k]
      ca <- cos(angles[i, j]); sa <- sin(angles[i, j])
      out[, j] <- ca * x + sa * y
      out[, k] <- -sa * x + ca * y
    }
    out
  })
  list(rotations = rotations, angles = angles,
       cumulative = Reduce("%*%", rev(rotations)))
}

cube_edge_axes <- function(vertices) {
  differences <- sweep(vertices[-1, , drop = FALSE], 2, vertices[1, ])
  lengths <- sqrt(rowSums(differences^2))
  keep <- which(abs(lengths - 1) < 1e-6)
  if (length(keep) != ncol(vertices)) {
    stop("Expected ", ncol(vertices), " unit edges at a cube vertex; found ", length(keep))
  }
  differences[keep, , drop = FALSE]
}

refine_original_collapse <- function(parameters, path_function, vertices, tolerance = 1e-9) {
  axes <- cube_edge_axes(vertices)
  path <- path_function(parameters)
  projected_axes <- axes %*% t(path$cumulative)
  chosen <- which.max(abs(projected_axes[, ncol(vertices)]))
  axis <- axes[chosen, ]
  residual <- function(p) c(path_function(p)$cumulative %*% axis)[-length(axis)]
  for (iteration in 1:20) {
    error <- residual(parameters)
    if (max(abs(error)) < tolerance) break
    jacobian <- vapply(seq_along(parameters), function(j) {
      plus <- minus <- parameters
      plus[j] <- plus[j] + 1e-6
      minus[j] <- minus[j] - 1e-6
      (residual(plus) - residual(minus)) / 2e-6
    }, numeric(length(error)))
    change <- c(t(jacobian) %*% solve(tcrossprod(jacobian), error))
    improved <- FALSE
    for (scale in 2^-(0:12)) {
      candidate <- parameters - scale * change
      if (sum(residual(candidate)^2) < sum(error^2)) {
        parameters <- candidate
        improved <- TRUE
        break
      }
    }
    if (!improved) stop("The collapse control-curve refinement did not converge")
  }
  error <- max(abs(residual(parameters)))
  if (error > tolerance) stop("The collapse trajectory did not reach alignment")
  list(parameters = parameters, path = path_function(parameters), error = error)
}
