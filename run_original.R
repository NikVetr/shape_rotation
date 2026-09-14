#!/usr/bin/env Rscript
# Standalone working copy of the incremental-rotation pipeline.
args <- commandArgs(trailingOnly = TRUE)
if ("--help" %in% args) {
  cat("Rscript run_original.R [--k=9] [--nrots=720] [--seed=1] [--nrep=10]\n",
      "  [--cores=1] [--thin=2] [--out=output/name] [--plan-only] [--no-video] [--rgl]\n",
      "  [--face-alpha=0.004] [--continue] (continue requires the same rendering settings)\n",
      "  [--device=cairo|ragg16] (ragg16 preserves very faint panel colors)\n",
      "  [--resume=output/name/animation.rds] (render a saved trajectory into a new output)\n")
  quit(status = 0)
}
values <- list(k = "5", nrots = "720", seed = "1", nrep = "10", cores = "1", thin = "2",
               out = file.path("output", paste0("incremental-", format(Sys.time(), "%Y%m%d-%H%M%S"))),
               resume = "", "face-alpha" = "", device = "cairo")
flags <- c("--plan-only", "--no-video", "--rgl", "--continue")
for (arg in setdiff(args, flags)) {
  pair <- strsplit(sub("^--", "", arg), "=", fixed = TRUE)[[1]]
  if (length(pair) != 2 || !pair[1] %in% names(values)) stop("Unknown argument: ", arg)
  values[[pair[1]]] <- pair[2]
}
for (name in c("k", "nrots", "seed", "nrep", "cores", "thin")) {
  number <- as.numeric(values[[name]])
  if (!is.finite(number) || number != as.integer(number) || number < 1) stop("Invalid --", name)
  values[[name]] <- as.integer(number)
}
entry <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1])
root <- dirname(normalizePath(entry))
face_alpha <- if (nzchar(values[["face-alpha"]])) as.numeric(values[["face-alpha"]]) else NULL
if (!is.null(face_alpha) && (!is.finite(face_alpha) || face_alpha < 0 || face_alpha > 1)) stop("Invalid --face-alpha")
for (package in c("expm", "png")) {
  if (!requireNamespace(package, quietly = TRUE)) stop("Install R package: ", package)
}
suppressPackageStartupMessages({ library(expm); library(grid) })
for (file in c("optimization.R", "geometry.R", "text.R", "animation.R", "render.R", "render_rgl.R", "diagnostics.R")) {
  source(file.path(root, "src", "incremental", file))
}
out <- values$out
continuing <- "--continue" %in% args
if (!continuing && dir.exists(out) && length(list.files(out, all.files = TRUE, no.. = TRUE))) {
  stop("Output directory must be new or empty: ", out)
}
dir.create(out, recursive = TRUE, showWarnings = FALSE)
animation <- if (continuing) {
  saved <- readRDS(file.path(out, "animation.rds"))
  if (nzchar(values$resume) && !identical(saved, readRDS(values$resume))) stop("Cannot continue with a different trajectory")
  saved
} else if (nzchar(values$resume)) readRDS(values$resume) else {
  generate_incremental_animation(values$k, values$nrots, seed = values$seed,
                                 nrep = values$nrep, cores = values$cores, checkpoint_dir = out,
                                 loop_multiple = values$thin)
}
if (!continuing) saveRDS(animation, file.path(out, "animation.rds"))
validate_incremental_animation(animation, out)
if (!"--plan-only" %in% args) {
  render_incremental_animation(animation, out, thin = values$thin, cores = values$cores,
                               use_rgl = "--rgl" %in% args, video = !"--no-video" %in% args,
                               face_alpha = face_alpha, continue = continuing, device = values$device)
}
capture.output(sessionInfo(), file = file.path(out, "sessionInfo.txt"))
cat("Saved to", normalizePath(out), "\n")
