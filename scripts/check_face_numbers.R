#!/usr/bin/env Rscript
source("src/incremental/geometry.R")
source("src/incremental/face_labels.R")

# Independent ray/quad intersections check the convex-support visibility rule.
ray_visible <- function(point, xyz, faces) {
  origin <- xyz[faces[, 1], , drop = FALSE]
  a <- xyz[faces[, 2], , drop = FALSE] - origin
  b <- xyz[faces[, 4], , drop = FALSE] - origin
  det <- a[, 1] * b[, 2] - a[, 2] * b[, 1]
  dx <- point[1] - origin[, 1]
  dy <- point[2] - origin[, 2]
  u <- (dx * b[, 2] - dy * b[, 1]) / det
  v <- (dy * a[, 1] - dx * a[, 2]) / det
  hit <- abs(det) > 1e-10 & is.finite(u) & is.finite(v) &
         u >= -1e-8 & u <= 1 + 1e-8 & v >= -1e-8 & v <= 1 + 1e-8
  z <- origin[, 3] + u * a[, 3] + v * b[, 3]
  !any(z[hit] > point[3] + 1e-8)
}
set.seed(19)
for (k in c(3L, 5L, 9L)) {
  cube <- generate_hypercube(k, 2)
  faces <- cube$faces[, c(1, 2, 4, 3), drop = FALSE]
  projection <- qr.Q(qr(matrix(rnorm(k * k), k)))[, 1:3]
  xyz <- cube$vertices %*% projection
  visible <- face_label_visibility(xyz, faces, k)
  selected <- unique(c(which(visible), sample(which(!visible), min(100, sum(!visible)))))
  for (f in selected) for (uv in list(c(.5, .5), c(.2, .7), c(.8, .3))) {
    point <- xyz[faces[f, 1], ] +
      uv[1] * (xyz[faces[f, 2], ] - xyz[faces[f, 1], ]) +
      uv[2] * (xyz[faces[f, 4], ] - xyz[faces[f, 1], ])
    stopifnot(identical(visible[f], ray_visible(point, xyz, faces)))
  }
}

# Turn a cube through a full loop with dimension changes while faces are visible.
cube <- generate_hypercube(3, 2)
angles <- seq(0, 4 * pi, length.out = 241)[-241]
vertices <- lapply(angles, function(t) cube$vertices %*% t(dkrot(3, c(.3, t, .1))))
data <- list(k = 3, hcube = cube, hcubes_proj = lapply(vertices, function(v) v[, 1:2]),
             depths_proj = lapply(vertices, function(v) v[, 3]),
             n_dim_per_tim = rep(c(2L, 3L, 2L), c(60, 120, 60)))
plan <- plan_face_numbers(data)
previous <- c(length(angles), seq_len(length(angles) - 1L))
changed <- plan$numbers != plan$numbers[, previous]
stopifnot(any(changed), !any(changed & !plan$concealed),
          any(plan$visible & plan$numbers != rep(data$n_dim_per_tim, each = 6)))
stopifnot(identical(plan, plan_face_numbers(data)))
still <- data
still$hcubes_proj <- data$hcubes_proj[1]
still$depths_proj <- data$depths_proj[1]
still$n_dim_per_tim <- 3L
stopifnot(identical(dim(plan_face_numbers(still)$numbers), c(6L, 1L)))

# Exactly coincident copies are potential visible faces, never hidden by a tie.
flat <- generate_hypercube(5, 2)
flat_xyz <- cbind(flat$vertices[, 1:2], 0)
flat_faces <- flat$faces[, c(1, 2, 4, 3)]
visible <- face_label_visibility(flat_xyz, flat_faces, 5)
stopifnot(sum(visible) == 8L)
line_xyz <- cbind(flat$vertices[, 1], 0, 0)
stopifnot(!any(face_label_visibility(line_xyz, flat_faces, 5)))
cat("Face visibility agrees with ray intersections through k=9; concealed relabeling, visible-label retention, loop seam, and degenerate projections passed.\n")
