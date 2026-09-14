args <- grep("^--file=", commandArgs(), value = TRUE)
root <- dirname(dirname(normalizePath(sub("^--file=", "", args[1]))))
for (file in c("rotation_math", "dimension_schedule", "animation", "render_frames")) {
  source(file.path(root, "src", paste0(file, ".R")))
}
magick <- Sys.which("magick")
if (!nzchar(magick)) stop("Install ImageMagick to run the raster continuity tests")
scratch <- file.path(root, "tmp", "output", paste0("render-tests-", Sys.getpid()))
dir.create(scratch, recursive = TRUE)
plan <- build_animation_plan(9)
geometry <- build_render_geometry(9)
transitions <- subset(plan$schedule, kind != "hold")
errors <- numeric(2 * nrow(transitions))
index <- 0L
for (i in seq_len(nrow(transitions))) {
  for (t in c(transitions$start[i], transitions$end[i])) {
    index <- index + 1L
    files <- file.path(scratch, paste0("boundary-", index, c("-left.png", "-right.png")))
    boundary <- animation_state(plan, t)
    for (side in 1:2) {
      state <- animation_state(plan, t + c(-1, 1)[side] * 1e-7)
      # Compare the two graph representations at the SAME limiting coordinates.
      # Real motion across a raster subpixel boundary is not an opacity jump.
      state$projection <- boundary$projection
      state$effective_dimension <- boundary$effective_dimension
      # Labels intentionally change at stages; compare only the actual geometry.
      state$stage <- plan$schedule[1, ]
      render_animation_frame(state, geometry, 2, files[side], 640, 640)
    }
    metric <- suppressWarnings(system2(magick,
      c("compare", "-metric", "RMSE", shQuote(files), "null:"), stdout = TRUE, stderr = TRUE))
    status <- attr(metric, "status")
    if (!is.null(status) && status != 1L) stop(paste(metric, collapse = "\n"))
    match <- regmatches(metric, regexec("\\(([0-9.eE+-]+)\\)", metric))
    if (length(match) != 1 || length(match[[1]]) != 2) stop("Unrecognized ImageMagick metric")
    errors[index] <- as.numeric(match[[1]][2])
    if (!is.finite(errors[index]) || errors[index] > 5e-5) {
      stop(sprintf("Raster discontinuity at %.6fs: RMSE = %.6g; inspect %s", t, errors[index], scratch))
    }
  }
}
cat(sprintf("All %d render boundaries passed; maximum normalized RGB RMSE: %.3g\n",
            length(errors), max(errors)))
cat("Test images: ", scratch, "\n", sep = "")
