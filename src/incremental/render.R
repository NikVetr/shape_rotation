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

render_incremental_animation <- function(animation, out, thin = 2L, cores = 1L,
                                         use_rgl = FALSE, video = TRUE) {
  list2env(animation, environment())
  if (length(hcubes_proj) %% thin != 0) {
    stop("--thin must divide the saved trajectory length for a uniformly sampled loop; use --thin=1 or solve with the desired --thin")
  }
  rot_hcube <- hcube
  frames_dir <- paste0(out, "/frames/")
  dir.create(frames_dir, recursive = TRUE, showWarnings = FALSE)
if (cores > 1) {
  cl <- parallel::makeCluster(cores)
  on.exit(parallel::stopCluster(cl), add = TRUE)
  doParallel::registerDoParallel(cl)
} else {
  foreach::registerDoSEQ()
}

#find plotting ranges
max_val <- cummax(sapply(lapply(hcubes_proj, abs), max))

#get opacity variable
opa <- rep(1, length(hcubes_proj))

#generate PNGs for label with fancy R
hypercube_names <- c(
  "point (ℝ⁰)",
  "line segment (ℝ¹)",
  "square (ℝ²)",
  "cube (ℝ³)",
  "tesseract (ℝ⁴)",
  "penteract (ℝ⁵)",
  "hexeract (ℝ⁶)",
  "hepteract (ℝ⁷)",
  "octeract (ℝ⁸)",
  "ennearact (ℝ⁹)"
)
hypercube_names <- setNames(hypercube_names, sapply(strsplit(hypercube_names, " "), head, 1))
if (k > 9) {
  extra <- seq.int(10L, k)
  hypercube_names <- c(hypercube_names, setNames(paste0(extra, "-cube"), paste0("cube", extra)))
}
labels_dir <- paste0(out, "/labels/")
if (!dir.exists(labels_dir)) dir.create(labels_dir, recursive = TRUE)
label_paths <- paste0(labels_dir, names(hypercube_names), ".png")

#render png labels and recover dimension info
label_dims <- cbind(w = rep(0, length(hypercube_names)),
                    h = rep(0, length(hypercube_names)))
if (use_rgl) for (i in seq_along(hypercube_names)) {
  name <- names(hypercube_names)[i]
  label <- hypercube_names[[name]]
  label_dims[i,] <- unlist(render_label_png(label, label_paths[i], fontsize = 48, dpi = 96, padding_factor = 0.25))
}

#### draw static pictures ####
plotting_inds <- seq(1, length(hcubes_proj), by = thin)
n_plotting_inds <- length(plotting_inds)
if(use_rgl){
  if (!requireNamespace("rgl", quietly = TRUE)) stop("Install rgl to use --rgl")
  library(rgl)
  rgl_r_version <- function(){}
  # foo <- foreach(i=1:length(hcubes_proj), .packages=c("rgl")) %dopar% {
  # foo <- foreach(i=1:10, .packages=c("rgl")) %dopar% {
  for(pi in 1:n_plotting_inds){

    i <- plotting_inds[pi]

    #report on progress
    if (pi %% 100 == 0) cat("Rendered frame", pi, "of", n_plotting_inds, "\n")

    # Recover hcube vertices for this frame
    hcube_proj <- hcubes_proj[[i]]
    depth_proj <- depths_proj[[i]]

    #rgl setup
    if (i == 1) {
      open3d()
      bg3d("white")
      par3d(windowRect = c(0, 0, 800, 800))

      # Dummy points to fix bounding box
      dummy_pts <- expand.grid(
        x = c(-1, 1) * axis_bounds,
        y = c(-1, 1) * axis_bounds,
        z = c(-1, 1) * axis_bounds
      )
      points3d(dummy_pts$x, dummy_pts$y, dummy_pts$z, alpha = 0)

      # Remove default light and add overhead light
      clear3d("lights")
      light3d(x = 2, y = 2, z = 2,
              diffuse = "white",
              specular = "white",
              ambient = "white",
              viewpoint.rel = T
      )

      # set a view and lock
      view3d(theta = 0, phi = 0, fov = 0, zoom = 0.75)
      fixed_matrix <- par3d("userMatrix")

    }

    #set material properties
    material3d(
        color = face_col,
        alpha = opa[i],
        ambient = "black",
        specular = "white",
        emission = "black",
        shininess = 50,
        lit = TRUE,
        smooth = TRUE
      )
    points3d(dummy_pts$x, dummy_pts$y, dummy_pts$z, alpha = 0)

    #recover face coords in 3D
    verts <- hcube_proj[!duplicated(round(hcube_proj, 9)),]
    nverts <- nrow(verts)
    if(nverts >= 4){

      face_coords <- lapply(1:nrow(rot_hcube$faces), function(fi){
        f_inds <- rot_hcube$faces[fi, chull(hcube_proj[rot_hcube$faces[fi, ], ])]
        if(length(f_inds) == 4){
          return(cbind(hcube_proj[f_inds, ], depth_proj[f_inds]))
        } else {
          return(NA)
        }
      })
      face_coords <- Filter(function(x) is.matrix(x) && all(is.finite(x)), face_coords)

      #recover order of faces
      face_depths <- sapply(face_coords, function(x) mean(x[,3]))
      face_order <- order(face_depths, decreasing=T)  # farthest to nearest

    } else {
      #here we have a line, so we can just plot it once?
      face_coords <- list(verts)
      face_order <- 1
    }

    # Filter out any NAs or improperly formed faces
    valid_face_indices <- !sapply(face_coords, function(x) any(is.na(x)))
    face_coords <- face_coords[valid_face_indices]

    #recover only the unique face_coords
    face_coords <- unique(face_coords)

    #and also just the ones that are actual polygons and not eg points
    face_coords <- face_coords[sapply(face_coords, function(fcs){
      mean(apply(fcs, 2, var)) > 1E-4
    })]

    # plot faces

    #one face at a time
    # for (face_matrix in face_coords) {
    #   quads3d(face_matrix, col = current_face_col, alpha = 1)
    # }

    #all faces together
    if (length(face_coords) > 0) {
      # Combine all vertices into one matrix for quads3d
      all_face_vertices <- do.call(rbind, face_coords)

      # Determine face color for this frame
      current_face_col <- face_cols[min(i, length(face_cols))]
      current_seg_col <- seg_cols[min(i, length(seg_cols))]

      # Plot opaque quads. Color is recycled for all vertices.
      if(nrow(all_face_vertices) < 4){
        all_face_vertices <- cbind(all_face_vertices, 0)
        lines3d(all_face_vertices, col = current_seg_col, lwd = 4)
      } else {
        quads3d(all_face_vertices)#, col = current_face_col, alpha = 1)
        #outline the faces
        num_quads <- nrow(all_face_vertices) / 4
        indices <- t(matrix(1:(num_quads * 4), nrow = 4)) # Rows: quad vertex indices (1,2,3,4), (5,6,7,8), ...
        seg_indices <- c(t(cbind(indices[,1], indices[,2], indices[,2], indices[,3],
                                 indices[,3], indices[,4], indices[,4], indices[,1])))
        segments3d(all_face_vertices[seg_indices, ], lwd = 4)#, col = current_seg_col) # Adjust color/lwd
      }
    }

    #write in text for shape

    #first recover text properties and location
    text_pos <- c(-axis_bounds, axis_bounds, axis_bounds)
    num_dim <- n_dim_per_tim[i]
    label_dim = label_dims[num_dim + 1,]
    label_ar <- label_dim["w"] / label_dim["h"]
    label_h_prop_bounds <- 0.075
    label_h <- label_h_prop_bounds * axis_bounds * 2
    label_bounds <- list(
      x = -axis_bounds + c(0, label_h, label_h, 0) * label_ar,
      y = axis_bounds - c(0, 0, label_h, label_h)
    )

    # Now add the textured quad
    quads3d(
      x = label_bounds$x,
      y = label_bounds$y,
      z = c(0,0,0,0),
      texcoords = list(
        x = c(0,1,1,0),
        y = c(1,1,0,0)
      ),
      texture = label_paths[num_dim+1],
      lit     = T,
      alpha   = 1,
      blend   = c("src_alpha","one_minus_src_alpha"),
      textype = "rgba",             # Use RGBA (alpha included)
      texmode = "replace",          # Don’t multiply texture by object color
      color   = "white"
    )

    #reset view angle
    view3d(theta = 0, phi = 0, fov = 0, zoom = 0.75, userMatrix = fixed_matrix)

    #plot to file
    output_filename <- paste0(frames_dir, paste0(rep(0, 5 - nchar(pi)), collapse = ""), pi, ".png")
    rgl.snapshot(filename = output_filename, fmt = "png")

    #now clear the plotting pane to prepare for the next one
    clear3d("shapes")

    if(pi == n_plotting_inds){
     close3d()
    }

  }
} else {
  base_r_version <- function(){}
  foo <- foreach(pi=1:n_plotting_inds, .packages=c("png"),
                 .export = "draw_incremental_projection") %dopar% {

    i <- plotting_inds[pi]

    #report on progress
    if (pi %% 100 == 0) cat("Rendered frame", pi, "of", n_plotting_inds, "\n")

    #recover hcube vertices
    hcube_proj <- hcubes_proj[[i]]
    depth_proj <- depths_proj[[i]]

    #write to file
    png(filename = paste0(frames_dir, paste0(rep(0, 5 - nchar(pi)), collapse = ""), pi, ".png"),
        width = 800, height = 800, type = "cairo", pointsize = 35)

    par(mar = c(0,0,0,0))
    plot.new()
    plot.window(xlim = c(-axis_bounds, axis_bounds),
                ylim = c(-axis_bounds, axis_bounds), asp = 1)
    # plot.window(xlim = c(-max_val[i], max_val[i]),
    #             ylim = c(-max_val[i], max_val[i]), asp = 1)


    draw_incremental_projection(hcube_proj, depth_proj, rot_hcube$faces, rot_hcube$edges,
                                face_cols[min(i, length(face_cols))],
                                seg_cols[min(i, length(seg_cols))])

    dev.off()
  }

}


if (video) {
  target <- file.path(out, "rotation.mp4")
  status <- system2("ffmpeg", c("-hide_banner", "-loglevel", "error", "-n",
    "-framerate", 60 / thin, "-i", shQuote(paste0(frames_dir, "%05d.png")),
    "-c:v", "libx264", "-crf", "20", "-pix_fmt", "yuv420p", shQuote(target)))
  if (status != 0) stop("ffmpeg encoding failed")
}
invisible(out)
}
