label_for_cube_dim <- function(d) {
  names <- c("line", "square", "cube", "tesseract", "penteract", "hexeract",
             "hepteract", "octeract", "enneaeract")
  if (d <= length(names)) sprintf("%s (%d-cube)", names[d], d) else sprintf("%d-cube", d)
}

build_render_geometry <- function(k, faces = TRUE) {
  lapply(seq_len(k), function(d) {
    list(vertices = generate_hypercube_vertices(d), edges = generate_hypercube_edges(d),
         fill = faces)
  })
}

animation_extent <- function(states) {
  # Exact support-function bounds, without retaining every projected vertex.
  1.12 * max(vapply(states, function(s) max(colSums(abs(s$projection))) / 2, numeric(1)))
}

render_animation_frame <- function(state, geometry, extent, file, width = 800,
                                    height = 800, supersample = 1L) {
  if (!capabilities("cairo")) stop("R needs Cairo support for headless PNG rendering")
  d <- state$visible_dimension
  graph <- geometry[[d]]
  xy <- graph$vertices %*% state$projection[seq_len(d), , drop = FALSE]
  eff <- state$effective_dimension
  edge_alpha <- -expm1(log1p(-0.94) / 2^(0.40 * max(0, eff - 4)))

  png(file, width = width * supersample, height = height * supersample,
      res = 96 * supersample, type = "cairo", bg = "white")
  on.exit(dev.off())
  par(mar = c(1, 0.5, 3, 0.5), xaxs = "i", yaxs = "i", lend = "round")
  plot.new()
  plot.window(xlim = c(-extent, extent), ylim = c(-extent, extent), asp = 1)

  if (graph$fill) {
    # A projected cube is convex. Fill its silhouette once so coincident faces
    # cannot change brightness as an axis becomes visible or disappears.
    hull <- chull(xy)
    if (length(hull) >= 3) polygon(xy[hull, ], border = NA,
                                 col = adjustcolor("lightskyblue", alpha.f = 0.28))
  }
  edges <- graph$edges
  edge_length2 <- rowSums((xy[edges[, 1], , drop = FALSE] -
                           xy[edges[, 2], , drop = FALSE])^2)
  # Zero-length closed paths can paint cap dots in Cairo at collapsed axes.
  edges <- edges[edge_length2 > 1e-24, , drop = FALSE]
  # Stroke one compound path: Cairo unions overlapping strokes before applying
  # opacity/antialiasing, including the duplicate edges at dimension boundaries.
  indices <- as.vector(t(cbind(edges, edges[, 1], NA_integer_)))
  indices <- indices[-length(indices)]
  polypath(xy[indices, 1], xy[indices, 2], col = NA,
           border = adjustcolor("deepskyblue4", alpha.f = edge_alpha),
           lwd = 2 / sqrt(max(1, eff - 2)))
  stage <- state$stage
  label <- if (stage$kind == "hold") label_for_cube_dim(stage$to) else
    sprintf("%d-cube  %s  %d-cube", stage$from,
            if (stage$kind == "unfold") "unfolding to" else "collapsing to", stage$to)
  mtext(label, side = 3, line = 1, cex = 0.95, font = 2, col = "#183B4A")
  invisible(file)
}

write_frames <- function(result, out_dir, width = 800, height = 800,
                         faces = TRUE, supersample = 1L) {
  check_number(width, "width", 128, 8192, integer = TRUE)
  check_number(height, "height", 128, 8192, integer = TRUE)
  check_number(supersample, "supersample", 1, 4, integer = TRUE)
  if (dir.exists(out_dir) && length(list.files(out_dir, all.files = TRUE, no.. = TRUE))) {
    stop("Frames directory is not empty; choose a fresh --out directory: ", out_dir)
  }
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  geometry <- build_render_geometry(result$config$k, faces)
  extent <- animation_extent(result$states)
  n <- length(result$states)
  for (i in seq_len(n)) {
    render_animation_frame(result$states[[i]], geometry, extent,
                           file.path(out_dir, sprintf("frame_%06d.png", i)),
                           width, height, supersample)
    if (i %% 100 == 0 || i == n) cat(sprintf("Rendered %d/%d frames\n", i, n))
  }
  invisible(list(out_dir = out_dir, n_frames = n, extent = extent))
}

compile_frames_ffmpeg <- function(frames_dir, output_file, fps, n_frames,
                                   width = 800, height = 800) {
  ffmpeg <- Sys.which("ffmpeg")
  if (!nzchar(ffmpeg)) stop("ffmpeg is missing; install it before rendering video")
  if (width %% 2 || height %% 2) stop("MP4 width and height must be even")
  if (file.exists(output_file)) stop("Refusing to overwrite video: ", output_file)
  args <- c("-hide_banner", "-loglevel", "error", "-nostdin", "-n",
            "-framerate", fps, "-start_number", 1,
            "-i", shQuote(file.path(frames_dir, "frame_%06d.png")),
            "-frames:v", n_frames, "-vf",
            shQuote(sprintf("scale=%d:%d:flags=lanczos", width, height)),
            "-c:v", "libx264", "-crf", 18, "-pix_fmt", "yuv420p",
            "-movflags", "+faststart", shQuote(output_file))
  status <- system2(ffmpeg, args)
  if (status != 0 || !file.exists(output_file)) stop("ffmpeg failed with status ", status)
  invisible(output_file)
}
