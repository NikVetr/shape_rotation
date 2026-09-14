args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1) stop("Usage: Rscript scripts/preview.R <animation output directory>")
script <- grep("^--file=", commandArgs(), value = TRUE)
root <- dirname(dirname(normalizePath(sub("^--file=", "", script[1]))))
for (file in c("rotation_math", "dimension_schedule", "animation", "render_frames")) {
  source(file.path(root, "src", paste0(file, ".R")))
}
magick <- Sys.which("magick")
if (!nzchar(magick)) stop("Install ImageMagick to create the storyboard")
out <- normalizePath(args[1], mustWork = TRUE)
result <- readRDS(file.path(out, "animation.rds"))
plan <- result$config
preview <- file.path(out, "preview")
dir.create(preview, showWarnings = FALSE)
geometry <- build_render_geometry(plan$k)
extent <- animation_extent(result$states)
holds <- subset(plan$schedule, kind == "hold")
files <- file.path(preview, sprintf("milestone_%02d.png", seq_len(nrow(holds))))
for (i in seq_len(nrow(holds))) {
  state <- animation_state(plan, mean(c(holds$start[i], holds$end[i])))
  render_animation_frame(state, geometry, extent, files[i], 480, 480)
}
rows <- split(files, ceiling(seq_along(files) / 5))
row_files <- file.path(preview, sprintf("row_%02d.png", seq_along(rows)))
for (i in seq_along(rows)) {
  status <- system2(magick, c(shQuote(rows[[i]]), "-resize", "320x320", "+append", shQuote(row_files[i])))
  if (status != 0) stop("ImageMagick failed to assemble a storyboard row")
}
status <- system2(magick, c(shQuote(row_files), "-background", "white", "-gravity", "NorthWest",
                            "-append", shQuote(file.path(out, "storyboard.png"))))
if (status != 0) stop("ImageMagick failed to assemble the storyboard")

times <- seq(0, plan$duration_seconds, length.out = 600)
h <- 0.001
motion <- vapply(times, function(t) {
  prev <- animation_state(plan, t - h)$projection
  curr <- animation_state(plan, t)$projection
  next_p <- animation_state(plan, t + h)$projection
  c(dimension = sum(animation_state(plan, t)$gates),
    speed = sqrt(sum(((next_p - prev) / (2 * h))^2)) / 2,
    acceleration = sqrt(sum(((next_p - 2 * curr + prev) / h^2)^2)) / 2)
}, numeric(3))
png(file.path(out, "motion.png"), width = 1200, height = 900, res = 120, type = "cairo")
par(mfrow = c(3, 1), mgp = c(2.8, 0.8, 0))
labels <- c("Dimension sequence (smooth transition progress)", "RMS projected vertex speed",
            "RMS projected vertex acceleration")
units <- c("dimension", "edge lengths / second", "edge lengths / second^2")
for (i in 1:3) {
  par(mar = c(if (i == 3) 4.5 else 2.5, 4.8, 2.3, 1))
  plot(times, motion[i, ], type = "n", xlab = if (i == 3) "Time (seconds)" else "",
       ylab = units[i], main = labels[i])
  abline(v = plan$schedule$start, col = "grey90", lty = 3)
  lines(times, motion[i, ], col = "deepskyblue4", lwd = 2)
}
dev.off()
cat("Saved storyboard.png and motion.png in ", out, "\n", sep = "")
