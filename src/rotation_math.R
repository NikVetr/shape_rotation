check_number <- function(x, name, lower = -Inf, upper = Inf, integer = FALSE) {
  if (length(x) != 1L || !is.numeric(x) || !is.finite(x) ||
      x < lower || x > upper || (integer && x != floor(x))) {
    stop(sprintf("%s must be %sa finite number in [%s, %s]",
                 name, if (integer) "an integer and " else "", lower, upper))
  }
  invisible(x)
}

smoothstep01 <- function(x) {
  z <- pmax(0, pmin(1, x))
  z^3 * (10 + z * (-15 + 6 * z))
}

plane_rotation <- function(k, i, j, angle) {
  out <- diag(k)
  out[c(i, j), c(i, j)] <- matrix(c(cos(angle), sin(angle),
                                     -sin(angle), cos(angle)), 2)
  out
}

# Rotate between a screen-plane direction and a hidden coordinate axis.
tilt_rotation <- function(k, dim_index, angle, azimuth) {
  u <- v <- numeric(k)
  u[1:2] <- c(cos(azimuth), sin(azimuth))
  v[dim_index] <- 1
  diag(k) + (cos(angle) - 1) * (tcrossprod(u) + tcrossprod(v)) +
    sin(angle) * (tcrossprod(v, u) - tcrossprod(u, v))
}

generate_hypercube_vertices <- function(k) {
  check_number(k, "k", 1, 16, integer = TRUE)
  ids <- seq.int(0L, 2^k - 1L)
  vapply(seq_len(k), function(d) as.numeric(bitwAnd(ids, 2^(d - 1)) != 0) - 0.5,
         numeric(length(ids)))
}

generate_hypercube_edges <- function(k) {
  check_number(k, "k", 1, 16, integer = TRUE)
  ids <- seq.int(0L, 2^k - 1L)
  do.call(rbind, lapply(seq_len(k), function(d) {
    bit <- 2^(d - 1)
    from <- ids[bitwAnd(ids, bit) == 0L]
    cbind(from + 1L, from + bit + 1L)
  }))
}

generate_hypercube_faces <- function(k, d = 2L) {
  check_number(k, "k", 1, 16, integer = TRUE)
  if (d != 2L) stop("Only square faces (d = 2) are supported")
  if (k == 1L) return(matrix(integer(), 0L, 4L))
  ids <- seq.int(0L, 2^k - 1L)
  do.call(rbind, combn(seq_len(k), 2L, simplify = FALSE, FUN = function(pair) {
    bits <- 2^(pair - 1)
    from <- ids[bitwAnd(ids, sum(bits)) == 0L]
    # Cyclic vertex order, including when the projection becomes degenerate.
    cbind(from, from + bits[1], from + sum(bits), from + bits[2]) + 1L
  }))
}
