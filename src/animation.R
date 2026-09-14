build_animation_plan <- function(k = 9, fps = 30, target_seconds = 48,
                                 base_turns = 3, seed = 11, wobble = 0.12) {
  check_number(k, "k", 1, 16, integer = TRUE)
  check_number(fps, "fps", 1, 240, integer = TRUE)
  check_number(target_seconds, "seconds", 0.1)
  check_number(base_turns, "turns", 1, integer = TRUE)
  check_number(seed, "seed", 0, 1e6, integer = TRUE)
  check_number(wobble, "wobble", 0, 0.25)
  n_frames <- round(fps * target_seconds)
  duration <- n_frames / fps
  schedule <- build_dimension_schedule(k, duration)
  if (min(schedule$end - schedule$start) * fps < 4) {
    stop("Duration/fps too low: each hold and transition needs at least four frames")
  }
  list(k = k, ambient = k + 1L, fps = fps, duration_seconds = duration,
       n_frames = n_frames, base_turns = base_turns, seed = seed,
       wobble = wobble, schedule = schedule)
}

animation_state <- function(plan, time) {
  check_number(time, "time")
  # Periodic evaluation also makes seam tests identical to internal-boundary tests.
  time <- time %% plan$duration_seconds
  phase <- time / plan$duration_seconds
  k <- plan$k
  m <- plan$ambient
  gates <- dimension_gates(time, plan$schedule, k)
  body <- diag(m)
  if (k >= 3L) {
    for (d in seq.int(3L, k)) {
      offset <- (d - 3) * pi * (3 - sqrt(5)) + plan$seed * 0.17
      azimuth <- pi / 4 + offset + 2 * plan$wobble * sin(2 * pi * phase + offset)
      tilt <- gates[d] * (atan(sqrt(2 / (d - 2))) +
                           plan$wobble * sin(2 * pi * phase + offset))
      body <- body %*% tilt_rotation(m, d, tilt, azimuth)
    }
  }
  if (k >= 2L) {
    # A spare, zero-valued coordinate hides axis 2 without deforming the cube.
    body <- body %*% plane_rotation(m, 2L, m, pi / 2 * (1 - gates[2]))
  }
  pose <- plane_rotation(m, 1L, 2L, 2 * pi * plan$base_turns * phase) %*% body
  row <- which(time < plan$schedule$end)[1L]
  stage <- plan$schedule[row, ]
  list(pose = pose, projection = t(pose[1:2, seq_len(k), drop = FALSE]),
       gates = gates, visible_dimension = max(which(gates > 0)),
       effective_dimension = sum(gates), stage = stage)
}

generate_hypercube_animation <- function(k = 9, fps = 30, target_seconds = 48,
                                         base_turns = 3, seed = 11, wobble = 0.12) {
  plan <- build_animation_plan(k, fps, target_seconds, base_turns, seed, wobble)
  # Save compact poses; vertices and faces are generated only for the visible cube.
  times <- seq.int(0L, plan$n_frames - 1L) / fps
  states <- lapply(times, function(time) animation_state(plan, time))
  list(config = plan, times = times, states = states)
}
