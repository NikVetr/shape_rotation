# Based on deprecated/rotate_hypercube.R; archive is never sourced at runtime.
smooth_tilt <- function(t) t - sin(2 * pi * t) / (2 * pi)

generate_incremental_animation <- function(k = 5L, nrots = 720L,
    nrots_per_full_rot = 120, seed = 1L, nrep = 10L, cores = 1L,
    checkpoint_dir = NULL, loop_multiple = 2L) {
  stopifnot(k >= 3, k == as.integer(k), nrots >= 20 * k, nrep >= 1, cores >= 1)
#### define unit hypercube ####
set.seed(seed)
hcube <- generate_hypercube(k, face_dim = 2)
axis_bounds <- sqrt(k*0.5^2)

#now rotate it

#specify rotation
thetas <- runif(choose(k, 2), 3*pi/4, 3*pi/2)
rotmat <- dkrot(k, thetas)
poss_pt <- c(axis_bounds, rep(0, k-1))
pp_rot <- c(rotmat %*% poss_pt)
angle <- acos(sum(poss_pt * pp_rot) / axis_bounds^2)
prop_full_rot <- 1 / (2 * pi / angle)

#identify fractional rotation matrix
rm_log  <- logm(rotmat)
rm_factor <- nrots_per_full_rot * prop_full_rot
rm_frac <- expm(1/rm_factor * rm_log)
rm_fracs <- c(list(diag(k)), extract_subrotations(rm_frac), list(rm_frac))

#set view direction (ie, plane to project to)
M <- matrix(rnorm(k * k), nrow = k)
Q <- qr.Q(qr(M))
plane_vectors <- Q[, 1:2, drop=FALSE]
plane_vectors <- cbind(c(1, rep(0,k-1)),
                       c(0, 1, rep(0,k-2)))
view_dir <- qr.Q(qr(plane_vectors), complete=TRUE)[, 3, drop = F]

#colors
face_alpha <- 1 / 1.25^k
# face_alpha <- 1
face_col <- "lightskyblue"
t0_face_col <- "lightskyblue"
face_cols <- adjustcolor(colorRampPalette(c(t0_face_col, face_col))(nrots), face_alpha)
face_cols <- c(face_cols, rev(face_cols))
# face_col <- "lightgrey"
polyborder_col <- adjustcolor(1, alpha.f = 1)
polyborder_col <- NA
seg_col <- "deepskyblue4"
t0_seg_col <- "deepskyblue4"
seg_cols <- colorRampPalette(c(t0_seg_col, seg_col))(nrots)
seg_cols <- c(seg_cols, rev(seg_cols))

#specify gradual expansion of the dimensions of rotation
dim_break_pts <- head(floor(seq(1, nrots, length.out = k+2)), k) #linear unfolding
dim_break_pts <- head(ceiling(nrots - seq(sqrt(nrots), 1, length.out = k+2)^2 + 1), k) #quadratic unfolding
pow_breaks <- 2
dim_break_pts <- head(ceiling(nrots - seq(nrots^(1/pow_breaks), 1, length.out = k+2)^pow_breaks + 1), k) #quadratic unfolding
dim_break_pts <- c(dim_break_pts, nrots+1)
dim_break_pts[1] <- 1
frac_1d2d_shift <- 0.75
frac_2d1d_shift <- 1 - frac_1d2d_shift
weight_ord <- (sin(-50:50/100*pi) + 1) / 2
n_dim_per_tim <- rep(1:k, diff(dim_break_pts))

#### compute forward rotation ####
rot_hcube <- hcube
rot_mats <- list()
cumrot_mats <- list()
full_hcubes <- list()
hcubes_proj <- list()
depths_proj <- list()
for(i in 1:nrots){

  #find which dims to rotate in
  ndim2r <- true_ndim <- sum(i >= dim_break_pts)
  if(ndim2r == 1){
    ndim2r <- 2
  }
  bordering_breaks <- dim_break_pts[sum(i >= dim_break_pts) + c(0,1)]
  trans_prop <- (i - bordering_breaks[1]) / (diff(bordering_breaks) - 1)
  trans_ind <- floor(trans_prop * 100) + 1
  wnd <- weight_ord[trans_ind]

  # Blend incremental Givens angles, retaining the original subrotations.
  # The cosine velocity blend has zero acceleration at both joins.
  if (ndim2r <= 2) {
    rm_to_use <- rm_fracs[[2]]
  } else {
    w <- (1 - cos(pi * trans_prop)) / 2
    previous <- undokrot(rm_fracs[[ndim2r - 1]])
    current <- undokrot(rm_fracs[[ndim2r]])
    rm_to_use <- dkrot(k, previous + w * (current - previous))
  }

  #compute rotation and project to the viewing plane
  rot_hcube$vertices <- t(rm_to_use %*% t(rot_hcube$vertices))
  full_hcubes[[i]] <- rot_hcube$vertices
  hcubes_proj[[i]] <- full_hcubes[[i]] %*% plane_vectors
  depths_proj[[i]] <- full_hcubes[[i]] %*% view_dir

  #record the rotation matrix that got us here
  rot_mats[[i]] <- rm_to_use
  if(i==1){
    cumrot_mats[[i]] <- rm_to_use
  } else {
    cumrot_mats[[i]] <- rm_to_use %*% cumrot_mats[[i-1]]
  }

  #get a rotating line in there too
  if(true_ndim == 1){
    # square_verts <- cbind(hcubes_proj[[i]][duplicated(hcubes_proj[[i]]),], 0)
    square_verts <- cbind(hcubes_proj[[i]][tail(rot_hcube$faces, 1),], 0)
    v1 <- square_verts[1,]
    v2 <- square_verts[4,]
    rotation_axis <- v2 - v1
    rotation_axis <- rotation_axis / sqrt(sum(rotation_axis^2)) # normalize
    if(trans_prop > frac_1d2d_shift){
      sq_ra <- pi / 2  -
        smooth_tilt((trans_prop - frac_1d2d_shift) / (1 - frac_1d2d_shift)) * pi / 2
    } else {
      sq_ra <- pi / 2
    }
    sq_rm <- rotation_matrix(rotation_axis, sq_ra)
    rot_sq <- t(sq_rm %*% t(square_verts))[,1:2]
    hcubes_proj[[i]] <- matrix(c(t(rot_sq)),
                               nrow = nrow(hcubes_proj[[i]]),
                               ncol = ncol(hcubes_proj[[i]]),
                               byrow = T)
  }
}

#### compute backward rotation ####
backwards_rotations <- list()
for(di in 1:(k-1)){

  #initialize target settings
  if(di == 1){

    nrots_curr <- nrots
    hcube_init <- tail(full_hcubes, 1)[[1]]
    R_init <- tail(rot_mats, 1)[[1]]
    target_n_steps <- tail(diff(dim_break_pts), 1)

  } else {

    nrots_curr <- length(full_hcubes)
    d2r <- (k-di+2):k
    hcube_init_full <- tail(full_hcubes, 1)[[1]][,-d2r]
    # Pick one face using the original vertex bits. Decimal rounding can split
    # coincident copies on opposite sides of a rounding boundary.
    all_vertices <- tail(full_hcubes, 1)[[1]]
    edge_axes <- sweep(all_vertices[2^(0:(k - 1)) + 1, , drop = FALSE],
                       2, all_vertices[1, ])
    hidden_axes <- apply(abs(edge_axes[, d2r, drop = FALSE]), 2, which.max)
    if (anyDuplicated(hidden_axes)) stop("Hidden dimensions do not identify distinct cube edges")
    sub_verts <- rowSums(hcube$vertices[, hidden_axes, drop = FALSE] > 0) == 0
    hcube_init <- hcube_init_full[sub_verts,]
    # The optimizer already ends with zero velocity in each hidden plane.
    # Keep the actual surviving block instead of re-projecting it with QR.
    R_init <- tail(rot_mats, 1)[[1]][seq_len(k - di + 1), seq_len(k - di + 1)]
    target_n_steps <- diff(dim_break_pts)[k - di + 1]
  }

  #perform optimization and extract rotation matrices
  if((k-di) > 1){
    collapsed_hcube <- collapse_hcube(hcube_init, R_init,
                                      n_steps = target_n_steps,
                                      n_p = 2, nrep = nrep, cores = cores)
    backwards_rotations[[length(backwards_rotations) + 1]] <- collapsed_hcube
    if (!is.null(checkpoint_dir)) {
      saveRDS(list(input = hcube_init, R_init = R_init, result = collapsed_hcube),
              file.path(checkpoint_dir, sprintf("collapse-%02d.rds", ncol(hcube_init))))
    }
    n_steps <- collapsed_hcube$n_steps
    n_dim_per_tim <- c(n_dim_per_tim, rep(k - di + 1, n_steps))
    rm2use <- collapsed_hcube$R_mats
  } else {
    n_steps <- target_n_steps
    n_dim_per_tim <- c(n_dim_per_tim, rep(2, n_steps))
    rm2use <- lapply(seq_len(n_steps), function(foo) R_init)
  }

  #pad these to have identity on outside
  if(di != 1){
    rm2use <- lapply(rm2use, function(x){
      new_rm <- diag(k)
      new_rm[1:dim(x)[1], 1:dim(x)[1]] <- x
      new_rm
    })
  }

  #compute projected coordinates
  for(i in (nrots_curr+1):(nrots_curr+n_steps)){
    #construct rotation matrix
    rm_to_use <- rm2use[[i-nrots_curr]]

    #compute rotation and project to the viewing plane
    rot_hcube$vertices <- t(rm_to_use %*% t(rot_hcube$vertices))
    full_hcubes[[i]] <- rot_hcube$vertices
    hcubes_proj[[i]] <- full_hcubes[[i]] %*% plane_vectors
    depths_proj[[i]] <- full_hcubes[[i]] %*% view_dir

    #record the rotation matrix that got us here
    rot_mats[[i]] <- rm_to_use
    cumrot_mats[[i]] <- rm_to_use %*% cumrot_mats[[i-1]]
  }
}

#collapse square to line
nrots_curr <- length(full_hcubes)
n_steps <- diff(dim_break_pts[1:2])
n_dim_per_tim <- c(n_dim_per_tim, ifelse(seq_len(n_steps) / n_steps <= frac_2d1d_shift, 2L, 1L))
for(i in (nrots_curr+1):(nrots_curr+n_steps)){

  #update rot_hcube with constant rotation from last step
  rot_hcube$vertices <- t(rm_to_use %*% t(rot_hcube$vertices))

  #recover rotation axis
  hd_hcube <- rot_hcube$vertices[,1:2]
  square_verts <- cbind(hd_hcube[!duplicated(round(hd_hcube, 5)),], 0)
  v1 <- square_verts[1,]
  v2 <- square_verts[4,]
  rotation_axis <- v2 - v1
  rotation_axis <- rotation_axis / sqrt(sum(rotation_axis^2)) # normalize

  #identify position in line rotation
  trans_prop <- (i - nrots_curr) / n_steps

  # Same edge-on square geometry; gradual tilt velocity at each end.
  sq_ra <- smooth_tilt(min(1, trans_prop / frac_2d1d_shift)) * pi / 2

  #rotate square into line
  sq_rm <- rotation_matrix(rotation_axis, sq_ra)
  rot_sq <- t(sq_rm %*% t(square_verts))[,1:2]

  #record variables
  hcubes_proj[[i]] <- matrix(c(t(rot_sq)),
                             nrow = nrow(hcubes_proj[[i-1]]),
                             ncol = ncol(hcubes_proj[[i-1]]),
                             byrow = T)
  full_hcubes[[i]] <- rot_hcube$vertices
  depths_proj[[i]] <- full_hcubes[[i]] %*% view_dir
  rot_mats[[i]] <- rm_to_use
  cumrot_mats[[i]] <- rm_to_use %*% cumrot_mats[[i-1]]
}

#keep rotating line until we have returned to start

#compute rotation matrices
curr_line <- rot_sq[c(which.min(rot_sq[,1]), which.max(rot_sq[,1])),]
starting_rot_sq <- hcubes_proj[[1]][!duplicated(round(hcubes_proj[[1]], 5)),]
starting_line <- starting_rot_sq[c(which.min(starting_rot_sq[,1]), which.max(starting_rot_sq[,1])),]
curr_rot_mat <- rm_to_use[1:2,1:2]
curr_rot_angle <- -atan2(curr_rot_mat[2,1], curr_rot_mat[1,1])
curr_rot_angle <- undokrot(rm_to_use)[1]
starting_rot_mat <- rot_mats[[1]][1:2, 1:2]
starting_rot_angle <- -atan2(starting_rot_mat[2,1], starting_rot_mat[1,1])
starting_rot_angle <- undokrot(rot_mats[[1]])[1]
abs(sum(apply(curr_line, 2, diff)^2) - sum(apply(starting_line, 2, diff)^2)) < 1E-6
rots_so_far <- sapply(lapply(rot_mats, undokrot), head, 1)
# plot(rots_so_far, type = "l"); abline(h = 0, col = 2)

#identify necessary rotation matrix and intermediate steps
rotation_needed <- find_min_directed_rotation(curr_line, starting_line, curr_rot_angle)
# The encoded loop excludes its duplicate endpoint. Target one step before
# frame 1 so the transition back to frame 1 is an ordinary rotation step.
rotation_needed <- rotation_needed - starting_rot_angle
while (rotation_needed * curr_rot_angle <= 0 || abs(rotation_needed) < 8 * abs(curr_rot_angle)) {
  rotation_needed <- rotation_needed + sign(curr_rot_angle) * pi
}
rotation_steps <- generate_smooth_rotation_steps(curr_rot_angle, starting_rot_angle, rotation_needed,
                                                step_multiple = loop_multiple,
                                                existing_steps = length(full_hcubes))
if (any(!is.finite(rotation_steps))) stop("Line-loop closure failed")

#### return to start ####
#rotate line to start
nrots_curr <- length(full_hcubes)
n_steps <- length(rotation_steps)
n_dim_per_tim <- c(n_dim_per_tim, rep(1, n_steps))
for(i in (nrots_curr+1):(nrots_curr+n_steps)){

  #update rot_hcube with constant rotation from last step
  rotation_angle <- rotation_steps[i-nrots_curr]
  rm_to_use <- pad_with_identity(d2rot(rotation_angle), k)
  rot_hcube$vertices <- t(rm_to_use %*% t(rot_hcube$vertices))

  #recover rotation axis
  hd_hcube <- rot_hcube$vertices[,1:2]
  square_verts <- cbind(hd_hcube[!duplicated(round(hd_hcube, 5)),], 0)
  v1 <- square_verts[1,]
  v2 <- square_verts[4,]
  rotation_axis <- v2 - v1
  rotation_axis <- rotation_axis / sqrt(sum(rotation_axis^2)) # normalize

  #identify position in line rotation
  sq_ra <- pi / 2

  #rotate square into line
  sq_rm <- rotation_matrix(rotation_axis, sq_ra)
  rot_sq <- t(sq_rm %*% t(square_verts))[,1:2]

  #record variables
  hcubes_proj[[i]] <- matrix(c(t(rot_sq)),
                             nrow = nrow(hcubes_proj[[i-1]]),
                             ncol = ncol(hcubes_proj[[i-1]]),
                             byrow = T)
  full_hcubes[[i]] <- rot_hcube$vertices
  depths_proj[[i]] <- full_hcubes[[i]] %*% view_dir
  rot_mats[[i]] <- rm_to_use
  cumrot_mats[[i]] <- rm_to_use %*% cumrot_mats[[i-1]]
}



  stopifnot(length(n_dim_per_tim) == length(hcubes_proj))
  list(k = k, nrots = nrots, seed = seed, hcube = hcube,
       axis_bounds = axis_bounds, dim_break_pts = dim_break_pts,
       n_dim_per_tim = n_dim_per_tim, rot_mats = rot_mats,
       full_hcubes = full_hcubes, hcubes_proj = hcubes_proj,
       depths_proj = depths_proj, backwards_rotations = backwards_rotations,
       face_col = face_col, face_cols = face_cols, seg_cols = seg_cols)
}
