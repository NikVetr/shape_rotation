# RGL scene construction based on the original lit-face and PNG-label renderer.
check_rgl_dependencies <- function() {
  options(rgl.useNULL = TRUE, rgl.fastTransparency = FALSE)
  for (package in c("rgl", "webshot2", "chromote")) {
    if (!requireNamespace(package, quietly = TRUE)) stop("Install R package: ", package)
  }
  chrome <- chromote::find_chrome()
  if (!nzchar(chrome)) stop("RGL snapshots require Chrome; set CHROMOTE_CHROME to its executable")
  invisible(chrome)
}

prepare_rgl_labels <- function(k, out) {
  names <- c("line segment", "square", "cube", "tesseract", "penteract",
             "hexeract", "hepteract", "octeract", "ennearact")
  superscripts <- strsplit("⁰¹²³⁴⁵⁶⁷⁸⁹", "")[[1]]
  directory <- file.path(out, "labels")
  dir.create(directory, showWarnings = FALSE)
  lapply(seq_len(k), function(d) {
    name <- if (d <= length(names)) names[d] else paste0(d, "-cube")
    power <- paste0(superscripts[as.integer(strsplit(as.character(d), "")[[1]]) + 1L], collapse = "")
    path <- file.path(directory, sprintf("dimension-%02d.png", d))
    dims <- render_label_png(paste0(name, " (ℝ", power, ")"), path, fontsize = 48,
                             fontfamily = "Arial Unicode MS")
    list(path = path, aspect = dims$width / dims$height)
  })
}

build_rgl_scene <- function(data, i) {
  bounds <- data$axis_bounds
  device <- rgl::open3d(useNULL = TRUE, windowRect = c(0, 0, 800, 800))
  on.exit(rgl::close3d(device))
  rgl::bg3d("white")
  rgl::points3d(as.matrix(expand.grid(rep(list(c(-bounds, bounds)), 3))), alpha = 0)
  rgl::clear3d("lights")
  rgl::light3d(x = 2, y = 2, z = 2, diffuse = "white", specular = "white",
               ambient = "white", viewpoint.rel = TRUE)
  xyz <- cbind(data$hcubes_proj[[i]], data$depths_proj[[i]])
  faces <- data$hcube$faces[, c(1, 2, 4, 3), drop = FALSE]
  a <- xyz[faces[, 2], ] - xyz[faces[, 1], ]
  b <- xyz[faces[, 4], ] - xyz[faces[, 1], ]
  area2 <- rowSums(a^2) * rowSums(b^2) - rowSums(a * b)^2
  faces <- faces[area2 > 1e-24, , drop = FALSE]
  color <- col2rgb(data$face_cols[min(i, length(data$face_cols))], alpha = TRUE) / 255
  alpha <- if (is.null(data$face_alpha)) color[4] else data$face_alpha
  if (nrow(faces)) {
    rgl::quads3d(xyz[as.vector(t(faces)), ], color = rgb(color[1], color[2], color[3]),
      alpha = alpha, ambient = "black", specular = "white", emission = "black",
      shininess = 50, lit = TRUE, smooth = FALSE, depth_mask = FALSE,
      polygon_offset = 1, tag = "panels")
  }
  edges <- data$hcube$edges
  delta <- xyz[edges[, 1], ] - xyz[edges[, 2], ]
  edges <- edges[rowSums(delta^2) > 1e-24, , drop = FALSE]
  if (nrow(edges)) rgl::segments3d(xyz[as.vector(t(edges)), ],
    color = data$seg_cols[min(i, length(data$seg_cols))], lwd = 2,
    lit = FALSE, depth_mask = FALSE, tag = "edges")
  label <- data$labels[[data$n_dim_per_tim[i]]]
  height <- 0.15 * bounds
  rgl::quads3d(x = -bounds + c(0, height, height, 0) * label$aspect,
    y = bounds - c(0, 0, height, height), z = rep(1.1 * bounds, 4),
    texcoords = cbind(c(0, 1, 1, 0), c(1, 1, 0, 0)),
    texture = label$path, lit = FALSE, color = "white", alpha = 1,
    textype = "rgba", texmode = "replace", depth_test = "always",
    depth_mask = FALSE, ignoreExtent = TRUE, tag = "label")
  rgl::view3d(theta = 0, phi = 0, fov = 0, zoom = 0.75)
  rgl::scene3d()
}

render_rgl_frame <- function(data, i, filename) {
  check_rgl_dependencies()
  scene <- build_rgl_scene(data, i)
  widget <- rgl::rglwidget(scene, width = 800, height = 800, fastTransparency = FALSE)
  # Fail on browser problems instead of snapshot3d's native-window fallback.
  withCallingHandlers(rgl::snapshot3d(filename, scene = widget, webshot = TRUE,
    width = 800, height = 800), warning = function(w) stop(conditionMessage(w)))
  invisible(filename)
}
