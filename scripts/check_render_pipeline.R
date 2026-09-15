#!/usr/bin/env Rscript
source("src/incremental/geometry.R")
source("src/incremental/render.R")
source("src/incremental/render_rgl.R")
source("src/incremental/face_labels.R")
library(grid)
use_rgl <- "--rgl" %in% commandArgs(trailingOnly = TRUE)
face_numbers <- "--face-numbers" %in% commandArgs(trailingOnly = TRUE)
if (face_numbers) {
  use_rgl <- TRUE
  render_without_numbers <- render_incremental_animation
  render_incremental_animation <- function(..., face_alpha = 1) {
    render_without_numbers(..., face_alpha = face_alpha, face_numbers = TRUE)
  }
}
device <- if ("--ragg16" %in% commandArgs(trailingOnly = TRUE)) "ragg16" else "cairo"
cube <- generate_hypercube(3, 2)
rotations <- lapply(seq(0.1, 0.7, length.out = 4), function(t) dkrot(3, c(t, t / 2, -t / 3)))
vertices <- lapply(rotations, function(r) cube$vertices %*% t(r))
a <- list(k = 3, hcube = cube, axis_bounds = sqrt(3) / 2,
          hcubes_proj = lapply(vertices, function(v) v[, 1:2]),
          depths_proj = lapply(vertices, function(v) v[, 3]),
          n_dim_per_tim = rep(3, 4), face_cols = "#87CEFA80", seg_cols = "deepskyblue4")
root <- file.path("tmp", "output", paste0("pipeline-check-", Sys.getpid()))
serial <- file.path(root, "serial")
workers <- file.path(root, "parallel")
render_incremental_animation(a, serial, thin = 1, cores = 1, use_rgl = use_rgl, video = FALSE, device = device)
render_incremental_animation(a, workers, thin = 1, cores = 2, use_rgl = use_rgl, video = FALSE, batch_size = 1, device = device)
paths <- file.path("frames", sprintf("%05d.png", 1:4))
for (path in paths) {
  stopifnot(identical(png::readPNG(file.path(serial, path)), png::readPNG(file.path(workers, path))))
}
before <- file.info(file.path(workers, paths))$mtime
writeBin(charToRaw("incomplete PNG"), file.path(workers, paths[2]))
render_incremental_animation(a, workers, thin = 1, cores = 2, use_rgl = use_rgl,
                             video = FALSE, continue = TRUE, device = device)
stopifnot(identical(png::readPNG(file.path(workers, paths[2])), png::readPNG(file.path(serial, paths[2]))),
          identical(file.info(file.path(workers, paths[-2]))$mtime, before[-2]))
mismatch <- tryCatch({
  render_incremental_animation(a, workers, thin = 1, use_rgl = use_rgl, face_alpha = 0.2, continue = TRUE, device = device)
  FALSE
}, error = function(e) grepl(if (face_numbers) "require --rgl" else "settings differ", conditionMessage(e)))
stopifnot(mismatch)
if (face_numbers) {
  label_mismatch <- tryCatch({
    render_without_numbers(a, workers, thin = 1, use_rgl = TRUE,
                           face_alpha = 1, continue = TRUE, face_numbers = FALSE)
    FALSE
  }, error = function(e) grepl("settings differ", conditionMessage(e)))
  stopifnot(label_mismatch)
}

bad <- a
bad$hcubes_proj[[3]][1, 1] <- NA_real_
failure <- tryCatch({
  render_incremental_animation(bad, file.path(root, "failure"), thin = 1, cores = 2,
                               use_rgl = use_rgl, batch_size = 1, device = device)
  FALSE
}, error = function(e) grepl(if (face_numbers) "step 3" else "Frame 3", conditionMessage(e)))
stopifnot(failure, !file.exists(file.path(root, "failure", "rotation.mp4")),
          !file.exists(file.path(root, "failure", paths[3])))
cat("Serial/parallel equality, corrupt-frame recovery, settings protection, and worker failure checks passed.\n")
