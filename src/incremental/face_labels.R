# Face identity follows the original vertex topology, including hidden copies.
face_label_visibility <- function(xyz, faces, k, tolerance = 1e-9) {
  a <- xyz[faces[, 2], , drop = FALSE] - xyz[faces[, 1], , drop = FALSE]
  b <- xyz[faces[, 4], , drop = FALSE] - xyz[faces[, 1], , drop = FALSE]
  normal <- cbind(a[, 2] * b[, 3] - a[, 3] * b[, 2],
                  a[, 3] * b[, 1] - a[, 1] * b[, 3],
                  a[, 1] * b[, 2] - a[, 2] * b[, 1])
  magnitude <- sqrt(rowSums(normal^2))
  # Camera looks along -z. Screen-edge-on faces have no visible ink area.
  visible <- abs(normal[, 3]) > tolerance
  normal <- normal * sign(normal[, 3]) / pmax(magnitude, tolerance)
  generators <- sweep(xyz[2^(0:(k - 1)) + 1L, , drop = FALSE], 2, xyz[1, ])
  center <- colMeans(xyz)
  face_center <- (xyz[faces[, 1], ] + xyz[faces[, 3], ]) / 2
  support <- rowSums(abs(normal %*% t(generators))) / 2
  gap <- support - rowSums(sweep(face_center, 2, center) * normal)
  # An opaque projected cube is convex. A face's relative interior is visible
  # only on its front supporting plane. Ties stay visible conservatively.
  visible & gap <= tolerance
}

plan_face_numbers <- function(data) {
  faces <- data$hcube$faces[, c(1, 2, 4, 3), drop = FALSE]
  steps <- length(data$hcubes_proj)
  stopifnot(steps >= 1L, length(data$n_dim_per_tim) == steps)
  visible <- vapply(seq_len(steps), function(i) {
    xyz <- cbind(data$hcubes_proj[[i]], data$depths_proj[[i]])
    if (any(!is.finite(xyz))) stop("Non-finite coordinates in face-label plan at step ", i)
    face_label_visibility(xyz, faces, data$k)
  }, logical(nrow(faces)))
  previous <- c(steps, seq_len(steps - 1L))
  following <- c(seq_len(steps - 1L) + 1L, 1L)
  concealed <- !visible & !visible[, previous, drop = FALSE] & !visible[, following, drop = FALSE]
  dimension <- pmax(2L, as.integer(data$n_dim_per_tim))
  numbers <- matrix(2L, nrow(faces), steps)
  for (f in seq_len(nrow(faces))) {
    appearances <- which(visible[f, ])
    if (!length(appearances)) next
    # Preload the next appearance's number; no changes on a visible face.
    next_number <- dimension[appearances[1]]
    upcoming <- integer(steps)
    for (i in rev(seq_len(steps))) {
      if (visible[f, i]) next_number <- dimension[i]
      upcoming[i] <- next_number
    }
    state <- upcoming[1]
    # Two passes settle the circular boundary, including faces visible at t=0.
    for (pass in 1:2) for (i in seq_len(steps)) {
      if (concealed[f, i]) state <- upcoming[i]
      if (pass == 2L) numbers[f, i] <- state
    }
  }
  changed <- numbers != numbers[, previous, drop = FALSE]
  if (any(changed & !concealed)) stop("Face-label change is not concealed")
  list(numbers = numbers, visible = visible, concealed = concealed,
       camera = "orthographic +z", tolerance = 1e-9)
}

prepare_face_number_textures <- function(k, out) {
  if (!requireNamespace("ragg", quietly = TRUE)) stop("Install R package: ragg")
  directory <- file.path(out, "labels")
  dir.create(directory, showWarnings = FALSE)
  vapply(seq_len(k), function(d) {
    path <- file.path(directory, sprintf("face-number-%02d.png", d))
    ragg::agg_png(path, width = 256, height = 256, background = "white")
    tryCatch({
      grid::grid.text(as.character(d), x = 0.5, y = 0.5,
        gp = grid::gpar(fontsize = if (d < 10) 132 else 100,
                       fontfamily = "sans", col = "#172C3A"))
    }, finally = grDevices::dev.off())
    path
  }, character(1))
}
