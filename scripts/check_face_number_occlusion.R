#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) stop("Usage: Rscript scripts/check_face_number_occlusion.R animation.rds")
source("src/incremental/geometry.R")
source("src/incremental/face_labels.R")
source("src/incremental/render.R")
source("src/incremental/render_rgl.R")
library(grid)
data <- readRDS(args[1])
data$face_alpha <- 1
data$face_numbers <- plan_face_numbers(data)
out <- file.path("tmp", "output", paste0("face-number-occlusion-", Sys.getpid()))
dir.create(out, recursive = TRUE)
data$labels <- prepare_rgl_labels(data$k, out)
data$number_textures <- prepare_face_number_textures(data$k, out)
n <- ncol(data$face_numbers$numbers)
previous <- c(n, seq_len(n - 1L))
changes <- colSums(data$face_numbers$numbers != data$face_numbers$numbers[, previous])
events <- which(changes > 0)
if (!length(events)) stop("Trajectory has no label changes to test")
steps <- unique(c(events[round(seq(1, length(events), length.out = 5))], which.max(changes)))
tryCatch({
  for (i in steps) {
    before <- data
    before$face_numbers$numbers[, i] <- data$face_numbers$numbers[, previous[i]]
    old <- file.path(out, sprintf("%04d-before.png", i))
    new <- file.path(out, sprintf("%04d-after.png", i))
    render_rgl_frame(before, i, old)
    render_rgl_frame(data, i, new)
    stopifnot(identical(png::readPNG(old), png::readPNG(new)))
    cat(sprintf("Step %d: %d concealed face changes leave identical pixels.\n", i, changes[i]))
  }
}, finally = close_render_browser())
cat("Rendered hidden-label changes are invisible. Images:", out, "\n")
