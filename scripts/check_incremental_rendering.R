#!/usr/bin/env Rscript
suppressPackageStartupMessages(library(foreach))
source("src/incremental/geometry.R")
args <- commandArgs(trailingOnly = TRUE)
source(if (length(args)) args[1] else "src/incremental/render.R")
scratch <- file.path("tmp", "output", paste0("incremental-edges-", Sys.getpid()))
dir.create(scratch, recursive = TRUE)

render_case <- function(name, k, projection) {
  cube <- generate_hypercube(k, 2)
  xy <- cube$vertices %*% projection
  extent <- sqrt(k) / 2
  a <- list(k = k, hcube = cube, axis_bounds = extent,
            hcubes_proj = list(xy, xy), depths_proj = list(rep(0, nrow(xy)), rep(0, nrow(xy))),
            n_dim_per_tim = c(k, k), face_col = "lightskyblue",
            face_cols = adjustcolor("lightskyblue", alpha.f = 1 / 1.25^k),
            seg_cols = "deepskyblue4")
  directory <- file.path(scratch, name)
  render_incremental_animation(a, directory, thin = 2, video = FALSE)
  raster <- png::readPNG(file.path(directory, "frames", "00001.png"))[, , 1:3]

  # The production PNG uses fixed square bounds with R's default 4% expansion.
  pixels <- cbind((0.5 + xy[, 1] / (2 * extent * 1.08)) * 800,
                  (0.5 - xy[, 2] / (2 * extent * 1.08)) * 800)
  edges <- cube$edges
  length_px <- sqrt(rowSums((pixels[edges[, 1], ] - pixels[edges[, 2], ])^2))
  edges <- edges[length_px > 10, , drop = FALSE]
  expected <- c(col2rgb("deepskyblue4")) / 255
  errors <- unlist(lapply(c(0.25, 0.5, 0.75), function(t) {
    samples <- (1 - t) * pixels[edges[, 1], , drop = FALSE] + t * pixels[edges[, 2], , drop = FALSE]
    apply(samples, 1, function(p) {
      cols <- pmax(1, pmin(800, round(p[1]) + (-2:2)))
      rows <- pmax(1, pmin(800, round(p[2]) + (-2:2)))
      patch <- matrix(raster[rows, cols, ], ncol = 3)
      # A 1.5-pixel Cairo stroke centered between rows covers about 3/4 of
      # each row. Test visible ink coverage, not an impossible opaque pixel.
      coverage <- max((1 - patch[, 1]) / (1 - expected[1]))
      max(0, 2 / 3 - coverage)
    })
  }))
  if (max(errors) > 1e-12) {
    stop(name, ": ", sum(errors > 1e-12), " edge samples lack their outline; inspect ", directory)
  }
  cat(name, ": ", length(errors), " edge samples visible\n", sep = "")
  invisible(raster)
}

render_case("line", 3, cbind(c(1, 0, 0), c(0, 0, 0)))
render_case("edge-on-faces", 3, cbind(c(0.8, 0.4, 0.2), c(0, 0, 0)))
render_case("square", 3, diag(3)[, 1:2])
render_case("coincident-square", 9, diag(9)[, 1:2])
for (k in c(3, 5, 9)) {
  rotation <- dkrot(k, seq(0.11, 1.3, length.out = choose(k, 2)))
  render_case(paste0("dense-k", k), k, rotation[, 1:2])
}
rotation <- dkrot(5, c(0.43, rep(1e-8, 9)))
render_case("near-collapse", 5, rotation[, 1:2])
cat("Incremental rendering checks passed. Images:", scratch, "\n")
