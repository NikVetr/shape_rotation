args <- commandArgs(trailingOnly = TRUE)
if ("--help" %in% args) {
  cat(paste(
    "Usage: Rscript run.R [options]",
    "  --k=9 --fps=30 --seconds=48 --turns=3 --seed=11 --wobble=0.12",
    "  --width=800 --height=800 --supersample=1 --out=output/<new-directory>",
    "  --wireframe       omit the pale blue silhouette fill",
    "  --no-video        write PNG frames and data only",
    "  --no-frames       write compact animation data and diagnostics only",
    "  --test-only       run geometry, continuity, and regression tests",
    "  --skip-tests      skip the automatic local checks",
    "Dimensions 1..16 are supported; rendering cost grows exponentially.",
    "The output directory must be new or empty. No existing output is removed.",
    sep = "\n"), "\n")
  quit(status = 0)
}
keys <- c("k", "fps", "seconds", "turns", "seed", "wobble", "width", "height",
          "supersample", "out")
flags <- c("--wireframe", "--no-video", "--no-frames", "--test-only", "--skip-tests")
arg_keys <- sub("=.*$", "", sub("^--", "", args))
valid <- args %in% flags | (startsWith(args, "--") & grepl("=", args) & arg_keys %in% keys)
if (any(!valid)) stop("Unknown argument(s): ", paste(args[!valid], collapse = ", "))
if (anyDuplicated(arg_keys)) stop("Repeated arguments are not allowed")
value <- function(key, default) {
  hit <- args[startsWith(args, paste0("--", key, "="))]
  if (length(hit)) substring(hit, nchar(key) + 4L) else default
}
number <- function(key, default) as.numeric(value(key, as.character(default)))

script_arg <- grep("^--file=", commandArgs(), value = TRUE)
root <- dirname(normalizePath(sub("^--file=", "", script_arg[1L])))
for (file in c("rotation_math", "dimension_schedule", "animation", "diagnostics",
               "render_frames", "tests")) {
  source(file.path(root, "src", paste0(file, ".R")))
}
if ("--test-only" %in% args || !("--skip-tests" %in% args)) run_unit_tests()
if ("--test-only" %in% args) quit(status = 0)

width <- number("width", 800)
height <- number("height", 800)
supersample <- number("supersample", 1)
check_number(width, "width", 128, 8192, integer = TRUE)
check_number(height, "height", 128, 8192, integer = TRUE)
check_number(supersample, "supersample", 1, 4, integer = TRUE)
write_png <- !("--no-frames" %in% args)
write_video <- write_png && !("--no-video" %in% args)
if (write_video && (!nzchar(Sys.which("ffmpeg")) || width %% 2 || height %% 2)) {
  stop("Video requires ffmpeg and even width/height")
}
out <- value("out", file.path(root, "output", paste0("smooth-", format(Sys.time(), "%Y%m%d-%H%M%S"))))
if (!nzchar(out)) stop("--out must not be empty")
if (dir.exists(out) && length(list.files(out, all.files = TRUE, no.. = TRUE))) {
  stop("Output directory must be new or empty: ", out)
}

cat("Generating smooth rotation path...\n")
result <- generate_hypercube_animation(k = number("k", 9), fps = number("fps", 30),
  target_seconds = number("seconds", 48), base_turns = number("turns", 3),
  seed = number("seed", 11), wobble = number("wobble", 0.12))
diagnostics <- print_animation_diagnostics(result)
dir.create(out, recursive = TRUE, showWarnings = FALSE)
saveRDS(result, file.path(out, "animation.rds"))
write.csv(result$config$schedule, file.path(out, "schedule.csv"), row.names = FALSE)
write.csv(diagnostics, file.path(out, "continuity.csv"), row.names = FALSE)
writeLines(c(capture.output(sessionInfo()), "", paste("Command:", paste(commandArgs(), collapse = " "))),
           file.path(out, "sessionInfo.txt"))
if (write_png) {
  frames_dir <- file.path(out, "frames")
  write_frames(result, frames_dir, width, height, !("--wireframe" %in% args), supersample)
  if (write_video) {
    compile_frames_ffmpeg(frames_dir, file.path(out, "rotation.mp4"), result$config$fps,
                          result$config$n_frames, width, height)
  }
}
cat("Saved output to ", normalizePath(out), "\n", sep = "")
