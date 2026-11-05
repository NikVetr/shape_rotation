#!/usr/bin/env Rscript
# Export a solved trajectory for the vetr.dev hypercube viewer, which replays it in
# the browser instead of rendering video. Every integration step's projected
# vertices and depths are linear in the base cube's vertices, [x y depth] = V A,
# including the square/line tilt stages, so a step ships as its k x 3 matrix A
# (float32). The export also carries each step's stage dimension and the
# face-number plan of --face-numbers (initial numbers and change events).
#
#   Rscript scripts/export_web_plan.R <animation.rds> <plan.json> [--thin=2]
#     [--frames=1,67,...] [--frames-out=frames.json]
#
# --frames-out writes R's own data for the listed steps, for parity tests of a
# port: projected vertices and depths (to 1e-10), the base renderer's face
# drawing order (1-based face rows), and face visibility and numbers as strings
# with one character per face (numbers comma-separated above k = 9).
args <- commandArgs(trailingOnly = TRUE)
options <- list(thin = "2", frames = "", "frames-out" = "")
positional <- character()
for (arg in args) {
  if (!startsWith(arg, "--")) { positional <- c(positional, arg); next }
  pair <- strsplit(sub("^--", "", arg), "=", fixed = TRUE)[[1]]
  if (length(pair) != 2 || !pair[1] %in% names(options)) stop("Unknown argument: ", arg)
  options[[pair[1]]] <- pair[2]
}
if (length(positional) != 2) {
  stop("Usage: Rscript scripts/export_web_plan.R <animation.rds> <plan.json> [--thin=2] [--frames=...] [--frames-out=...]")
}
if (!requireNamespace("jsonlite", quietly = TRUE)) stop("Install R package: jsonlite")
entry <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1])
root <- dirname(dirname(normalizePath(entry)))
for (file in c("geometry.R", "face_labels.R")) source(file.path(root, "src", "incremental", file))

animation <- readRDS(positional[1])
k <- animation$k
steps <- length(animation$hcubes_proj)
thin <- as.integer(options$thin)
if (!is.finite(thin) || thin < 1 || steps %% thin != 0) stop("--thin must divide the trajectory length (", steps, ")")
vertices <- animation$hcube$vertices
stopifnot(length(animation$depths_proj) == steps, length(animation$n_dim_per_tim) == steps)

# The base vertices are orthogonal columns of +-0.5, so V'V = 2^k / 4 I and the
# least-squares fit is a single product. Refuse anything that is not linear.
coordinates <- function(i) cbind(animation$hcubes_proj[[i]], animation$depths_proj[[i]])
maps <- lapply(seq_len(steps), function(i) crossprod(vertices, coordinates(i)) * 4 / nrow(vertices))
residual <- vapply(seq_len(steps), function(i) max(abs(coordinates(i) - vertices %*% maps[[i]])), numeric(1))
if (max(residual) > 1e-8) stop("Step ", which.max(residual), " is not linear in the base vertices: ", max(residual))
projection <- unlist(lapply(maps, function(a) as.vector(t(a))))
float32 <- writeBin(projection, raw(), size = 4, endian = "little")
rounding <- max(abs(projection - readBin(float32, "double", length(projection), size = 4, endian = "little")))

started <- proc.time()[[3]]
labels <- plan_face_numbers(animation[c("k", "hcube", "hcubes_proj", "depths_proj", "n_dim_per_tim")])
numbers <- labels$numbers
changed <- which(numbers[, -1, drop = FALSE] != numbers[, -steps, drop = FALSE], arr.ind = TRUE)
changed <- changed[order(changed[, 2], changed[, 1]), , drop = FALSE]
# Events are (step, face, number) triples, 1-based as in R, as little-endian uint16.
events <- as.vector(rbind(changed[, 2] + 1L, changed[, 1], numbers[cbind(changed[, 1], changed[, 2] + 1L)]))
if (length(events) && max(events) > 65535) stop("Face-number events exceed uint16")
label_seconds <- proc.time()[[3]] - started

runs <- rle(as.integer(animation$n_dim_per_tim))
ends <- cumsum(runs$lengths)
stages <- data.frame(dimension = runs$values, start = ends - runs$lengths + 1L, length = runs$lengths)
face_rgba <- col2rgb(animation$face_cols[1], alpha = TRUE)
face_hex <- sprintf("#%02X%02X%02X", face_rgba[1], face_rgba[2], face_rgba[3])
face_alpha <- face_rgba[4] / 255
commit <- tryCatch(system2("git", c("-C", shQuote(root), "rev-parse", "--short", "HEAD"), stdout = TRUE),
                   error = function(e) NA_character_, warning = function(w) NA_character_)

plan <- list(
  format = "hypercube-plan", version = 1L,
  k = k, seed = animation$seed, nrots = animation$nrots, thin = thin, stepsPerSecond = 60L,
  frames = steps, axisBounds = animation$axis_bounds,
  colors = list(face = face_hex, edge = animation$seg_cols[1], faceAlpha = face_alpha),
  stages = stages,
  projection = list(encoding = "float32le-base64", shape = c(steps, k, 3L),
                    maxLinearResidual = max(residual), maxFloat32Rounding = rounding,
                    data = jsonlite::base64_enc(float32)),
  faceNumbers = list(camera = labels$camera, tolerance = labels$tolerance,
                     initial = as.integer(numbers[, 1]), eventCount = nrow(changed),
                     events = list(encoding = "uint16le-base64", fields = c("step", "face", "number"),
                                   data = jsonlite::base64_enc(writeBin(as.integer(events), raw(), size = 2, endian = "little")))),
  collapses = lapply(animation$backwards_rotations, function(f) list(
    dimension = ncol(f$hcube_end), steps = f$n_steps, selectedCandidate = f$selected_candidate,
    alignmentError = f$alignment_error)),
  source = list(repository = "https://github.com/NikVetr/shape_rotation", commit = commit,
                exporter = "scripts/export_web_plan.R")
)
jsonlite::write_json(plan, positional[2], auto_unbox = TRUE, digits = NA, dataframe = "rows")
cat(sprintf("k=%d: %d steps, %d face-number events, linear residual %.2g, float32 rounding %.2g, label plan %.1fs -> %s (%.0f KB)\n",
            k, steps, nrow(changed), max(residual), rounding, label_seconds, positional[2],
            file.size(positional[2]) / 1024))

if (nzchar(options$frames)) {
  if (!nzchar(options[["frames-out"]])) stop("--frames needs --frames-out")
  selected <- as.integer(strsplit(options$frames, ",", fixed = TRUE)[[1]])
  if (anyNA(selected) || any(selected < 1 | selected > steps)) stop("--frames must list steps from 1 to ", steps)
  faces <- animation$hcube$faces
  frames <- lapply(selected, function(i) {
    xy <- animation$hcubes_proj[[i]]
    depth <- animation$depths_proj[[i]]
    # The same hulls, filter and order as draw_incremental_projection in render.R.
    hulls <- lapply(seq_len(nrow(faces)), function(f) faces[f, chull(xy[faces[f, ], , drop = FALSE])])
    drawn <- which(lengths(hulls) >= 3)
    depths <- vapply(hulls[drawn], function(v) mean(depth[v]), numeric(1))
    list(step = i, dimension = as.integer(animation$n_dim_per_tim[i]),
         xyz = round(unname(coordinates(i)), 10),
         drawOrder = drawn[order(depths, decreasing = TRUE)],
         visible = paste(as.integer(labels$visible[, i]), collapse = ""),
         numbers = paste(numbers[, i], collapse = if (k > 9) "," else ""))
  })
  faces_text <- paste(apply(faces, 1, paste, collapse = ","), collapse = ";")
  edges_text <- paste(apply(animation$hcube$edges, 1, paste, collapse = ","), collapse = ";")
  hash <- function(text) {
    path <- tempfile()
    on.exit(unlink(path))
    writeLines(text, path, sep = "")
    unname(tools::md5sum(path))
  }
  out <- list(k = k, frames = steps, topology = list(facesMd5 = hash(faces_text), edgesMd5 = hash(edges_text),
                                                     firstFaces = unname(faces[1:min(6, nrow(faces)), ])),
              steps = frames)
  jsonlite::write_json(out, options[["frames-out"]], auto_unbox = TRUE, digits = NA)
  cat(sprintf("Parity frames %s -> %s (%.0f KB)\n", paste(selected, collapse = " "), options[["frames-out"]],
              file.size(options[["frames-out"]]) / 1024))
}
