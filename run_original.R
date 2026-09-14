#!/usr/bin/env Rscript
# Standalone working copy of the incremental-rotation pipeline.
args <- commandArgs(trailingOnly = TRUE)
if ("--help" %in% args) {
  cat("Rscript run_original.R [--k=9] [--nrots=720] [--seed=1] [--nrep=10]\n",
      "  [--cores=1] [--thin=2] [--out=output/name] [--plan-only] [--no-video] [--rgl]\n",
      "  [--resume=output/name/animation.rds] (render a saved trajectory into a new output)\n")
  quit(status = 0)
}
values <- list(k = "5", nrots = "720", seed = "1", nrep = "10", cores = "1", thin = "2",
               out = file.path("output", paste0("incremental-", format(Sys.time(), "%Y%m%d-%H%M%S"))),
               resume = "")
flags <- c("--plan-only", "--no-video", "--rgl")
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
for (package in c("expm", "foreach", "doParallel", "png")) {
  if (!requireNamespace(package, quietly = TRUE)) stop("Install R package: ", package)
}
suppressPackageStartupMessages({ library(expm); library(foreach); library(grid) })
for (file in c("optimization.R", "geometry.R", "text.R", "animation.R", "render.R", "diagnostics.R")) {
  source(file.path(root, "src", "incremental", file))
}
out <- values$out
if (dir.exists(out) && length(list.files(out, all.files = TRUE, no.. = TRUE))) {
  stop("Output directory must be new or empty: ", out)
}
dir.create(out, recursive = TRUE, showWarnings = FALSE)
animation <- if (nzchar(values$resume)) readRDS(values$resume) else {
  generate_incremental_animation(values$k, values$nrots, seed = values$seed,
                                 nrep = values$nrep, cores = values$cores, checkpoint_dir = out,
                                 loop_multiple = values$thin)
}
saveRDS(animation, file.path(out, "animation.rds"))
capture.output(sessionInfo(), file = file.path(out, "sessionInfo.txt"))
validate_incremental_animation(animation, out)
if (!"--plan-only" %in% args) {
  render_incremental_animation(animation, out, thin = values$thin, cores = values$cores,
                               use_rgl = "--rgl" %in% args, video = !"--no-video" %in% args)
}
cat("Saved to", normalizePath(out), "\n")
