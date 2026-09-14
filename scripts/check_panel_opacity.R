#!/usr/bin/env Rscript
source("src/incremental/geometry.R")
source("src/incremental/render.R")
if (!requireNamespace("ragg", quietly = TRUE)) stop("Install ragg for the 16-bit compositing check")
cube <- generate_hypercube(9, 2)
xy <- cube$vertices[, 1:2]
a <- list(k = 9, hcube = cube, axis_bounds = 1.5,
          hcubes_proj = list(xy, xy), depths_proj = list(rep(0, 512), rep(0, 512)),
          n_dim_per_tim = c(2, 2), face_cols = "#87CEFA22", seg_cols = "deepskyblue4")
root <- file.path("tmp", "output", paste0("opacity-check-", Sys.getpid()))
color <- c(col2rgb("lightskyblue")) / 255
for (alpha in c(0.004, 0.01, 0.134)) {
  out <- file.path(root, paste0("alpha-", alpha))
  render_incremental_animation(a, out, video = FALSE, face_alpha = alpha, device = "ragg16")
  raster <- png::readPNG(file.path(out, "frames", "00001.png"))
  # R color strings encode alpha in eight bits; compositing must accumulate
  # those 128 layers in higher precision without changing their color.
  encoded_alpha <- round(alpha * 255) / 255
  expected <- 1 + (color - 1) * (1 - (1 - encoded_alpha)^128)
  error <- max(abs(raster[400, 400, 1:3] - expected))
  stopifnot(error < 0.003)
  cat("128 layers at alpha", alpha, "match compositing formula; max RGB error", error, "\n")
}
cat("Panel compositing checks passed.\n")
