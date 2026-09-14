# Rendering copied from deprecated/rotate_hypercube.R.
draw_incremental_projection <- function(xy, depth, faces, edges, face_col, edge_col) {
  projected_faces <- lapply(seq_len(nrow(faces)), function(i) {
    vertices <- faces[i, ]
    vertices[chull(xy[vertices, , drop = FALSE])]
  })
  projected_faces <- Filter(function(vertices) length(vertices) >= 3, projected_faces)
  face_depths <- vapply(projected_faces, function(vertices) mean(depth[vertices]), numeric(1))
  for (i in order(face_depths, decreasing = TRUE)) {
    polygon(xy[projected_faces[[i]], , drop = FALSE], col = face_col, border = NA)
  }

  # Edges survive even when their incident faces project to lines. Draw them
  # after all fills so repeated translucent faces cannot erase the outlines.
  delta <- xy[edges[, 1], , drop = FALSE] - xy[edges[, 2], , drop = FALSE]
  edges <- edges[rowSums(delta^2) > 1e-24, , drop = FALSE]
  if (nrow(edges)) {
    # One compound stroke keeps coincident copies from darkening antialiasing.
    indices <- as.vector(t(cbind(edges, edges[, 1], NA_integer_)))
    indices <- indices[-length(indices)]
    polypath(xy[indices, 1], xy[indices, 2], col = NA, border = edge_col,
             lwd = 2, xpd = NA)
  }
}

render_base_frame <- function(data, i, filename) {
  if (identical(data$base_device, "ragg16")) {
    ragg::agg_png(filename, width = 800, height = 800, pointsize = 35, bitsize = 16)
  } else {
    png(filename, width = 800, height = 800, type = "cairo", pointsize = 35)
  }
  on.exit(dev.off())
  par(mar = c(0, 0, 0, 0))
  plot.new()
  plot.window(xlim = c(-data$axis_bounds, data$axis_bounds),
              ylim = c(-data$axis_bounds, data$axis_bounds), asp = 1)
  draw_incremental_projection(data$hcubes_proj[[i]], data$depths_proj[[i]],
    data$hcube$faces, data$hcube$edges, data$face_cols[min(i, length(data$face_cols))],
    data$seg_cols[min(i, length(data$seg_cols))])
}

valid_rendered_png <- function(path) {
  if (!file.exists(path)) return(FALSE)
  tryCatch({
    dimensions <- dim(png::readPNG(path))
    identical(dimensions[1:2], c(800L, 800L))
  }, error = function(e) FALSE)
}

render_frame_batch <- function(numbers, context) {
  vapply(numbers, function(number) {
    i <- context$indices[number]
    target <- file.path(context$frames_dir, sprintf("%05d.png", number))
    temporary <- paste0(target, ".partial.png")
    started <- proc.time()[[3]]
    tryCatch({
      if (any(!is.finite(context$data$hcubes_proj[[i]])) ||
          any(!is.finite(context$data$depths_proj[[i]]))) stop("Non-finite projected coordinates")
      if (context$use_rgl) render_rgl_frame(context$data, i, temporary) else
        render_base_frame(context$data, i, temporary)
      if (!valid_rendered_png(temporary)) stop("Invalid or incomplete PNG")
      if (!file.rename(temporary, target)) stop("Cannot publish completed frame")
    }, error = function(e) stop("Frame ", number, " (step ", i, "): ", conditionMessage(e)))
    proc.time()[[3]] - started
  }, numeric(1))
}

# Keep this closure outside the orchestrator so dispatch does not serialize
# the entire animation environment again for every batch.
render_worker_batch <- function(numbers) render_frame_batch(numbers, context)

close_render_browser <- function() {
  if ("chromote" %in% loadedNamespaces() && chromote::has_default_chromote_object()) {
    chromote::default_chromote_object()$close()
  }
  invisible(NULL)
}

render_incremental_animation <- function(animation, out, thin = 2L, cores = 1L,
    use_rgl = FALSE, video = TRUE, face_alpha = NULL, continue = FALSE, batch_size = NULL,
    device = "cairo") {
  stopifnot(cores >= 1, thin >= 1)
  if (length(animation$hcubes_proj) %% thin != 0) {
    stop("--thin must divide the saved trajectory length; use --thin=1 or solve with the desired --thin")
  }
  if (!is.null(face_alpha) && (!is.finite(face_alpha) || face_alpha < 0 || face_alpha > 1)) {
    stop("--face-alpha must be between 0 and 1")
  }
  if (is.null(batch_size)) batch_size <- if (use_rgl) 2L else 16L
  stopifnot(batch_size >= 1)
  data <- animation[c("k", "hcube", "axis_bounds", "hcubes_proj", "depths_proj",
                       "n_dim_per_tim", "face_cols", "seg_cols")]
  if (!is.null(face_alpha)) {
    colors <- col2rgb(data$face_cols) / 255
    data$face_cols <- rgb(colors[1, ], colors[2, ], colors[3, ], alpha = face_alpha)
  }
  data$face_alpha <- face_alpha
  if (!use_rgl) {
    if (!device %in% c("cairo", "ragg16")) stop("Unknown base graphics device: ", device)
    if (device == "ragg16" && !requireNamespace("ragg", quietly = TRUE)) stop("Install R package: ragg")
    data$base_device <- device
  }
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  out <- normalizePath(out)
  frames_dir <- file.path(out, "frames")
  dir.create(frames_dir, showWarnings = FALSE)
  settings <- list(version = 3L, thin = thin, use_rgl = use_rgl, face_alpha = face_alpha)
  if (!use_rgl) settings$device <- device
  manifest <- file.path(out, "render-settings.rds")
  input <- file.path(out, "render-input.rds")
  if (continue) {
    if (!file.exists(manifest) || !file.exists(input) ||
        !identical(readRDS(manifest), settings) || !identical(readRDS(input), data)) {
      stop("Cannot continue: trajectory or rendering settings differ from the saved run")
    }
  } else {
    if (file.exists(manifest) || length(list.files(frames_dir))) stop("Render output already exists; use --continue")
    saveRDS(settings, manifest)
    saveRDS(data, input)
  }
  if (use_rgl) {
    if (!exists("render_rgl_frame", mode = "function")) stop("Load src/incremental/render_rgl.R first")
    check_rgl_dependencies()
    data$labels <- prepare_rgl_labels(data$k, out)
  }
  indices <- seq(1L, length(data$hcubes_proj), by = thin)
  paths <- file.path(frames_dir, sprintf("%05d.png", seq_along(indices)))
  complete <- vapply(paths, valid_rendered_png, logical(1))
  pending <- which(!complete)
  cat(sprintf("%s rendering: %d frames, %d cached, %d workers\n",
              if (use_rgl) "RGL/WebGL" else device, length(indices), sum(complete), cores))
  context <- list(data = data, indices = indices, frames_dir = frames_dir, use_rgl = use_rgl)
  timings <- rep(NA_real_, length(indices))
  timing_path <- file.path(out, "render-times.csv")
  if (continue && file.exists(timing_path)) timings <- read.csv(timing_path)$seconds
  cl <- NULL
  on.exit({
    if (!is.null(cl)) {
      if (use_rgl) try(parallel::clusterCall(cl, close_render_browser), silent = TRUE)
      parallel::stopCluster(cl)
    } else if (use_rgl) close_render_browser()
  }, add = TRUE)
  if (length(pending) && cores > 1) {
    cl <- parallel::makePSOCKcluster(min(cores, length(pending)), outfile = file.path(out, "workers.log"))
    helpers <- c("render_base_frame", "draw_incremental_projection", "valid_rendered_png", "render_frame_batch")
    if (use_rgl) helpers <- c(helpers, "render_rgl_frame", "build_rgl_scene", "check_rgl_dependencies")
    parallel::clusterExport(cl, c(helpers, "context"), envir = environment())
  }
  started <- proc.time()[[3]]
  batches <- split(pending, ceiling(seq_along(pending) / batch_size))
  for (first in seq.int(1L, max(1L, length(batches)), by = cores)) {
    if (!length(batches)) break
    jobs <- batches[seq.int(first, min(length(batches), first + cores - 1L))]
    result <- if (is.null(cl)) lapply(jobs, render_frame_batch, context = context) else
      parallel::parLapplyLB(cl, jobs, render_worker_batch)
    for (j in seq_along(jobs)) {
      timings[jobs[[j]]] <- result[[j]]
      complete[jobs[[j]]] <- TRUE
    }
    write.csv(data.frame(frame = seq_along(indices), step = indices, seconds = timings),
              timing_path, row.names = FALSE)
    cat(sprintf("Rendered %d/%d frames (%.1fs elapsed)\n", sum(complete), length(indices), proc.time()[[3]] - started))
    flush.console()
  }
  if (!all(vapply(paths, valid_rendered_png, logical(1)))) stop("Incomplete frame sequence; encoding refused")
  if (use_rgl) {
    highest <- which(data$n_dim_per_tim == data$k)
    if (!length(highest)) highest <- which.max(data$n_dim_per_tim)
    scene <- build_rgl_scene(data, highest[ceiling(length(highest) / 2)])
    htmlwidgets::saveWidget(rgl::rglwidget(scene, width = 800, height = 800,
      fastTransparency = FALSE), file.path(out, "scene.html"), selfcontained = FALSE,
      title = paste0("Interactive ", data$k, "-cube"))
  }
  if (video) {
    target <- file.path(out, "rotation.mp4")
    if (file.exists(target) && !continue) stop("Video already exists")
    if (!file.exists(target) || length(pending)) {
      temporary <- file.path(out, "rotation.partial.mp4")
      status <- system2("ffmpeg", c("-hide_banner", "-loglevel", "error", "-nostdin", "-y",
        "-framerate", 60 / thin, "-start_number", "1", "-i", shQuote(file.path(frames_dir, "%05d.png")),
        "-frames:v", length(indices), "-c:v", "libx264", "-crf", "20", "-pix_fmt", "yuv420p",
        "-movflags", "+faststart", shQuote(temporary)))
      if (status != 0 || !file.rename(temporary, target)) stop("ffmpeg encoding failed")
    }
  }
  invisible(out)
}
