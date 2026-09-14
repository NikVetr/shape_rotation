# Endpoint constraints are solved by construction, rather than a penalty search.
# Each gate and its first two derivatives vanish outside its active interval.
build_dimension_schedule <- function(k, target_seconds, transition_weight = 1.6,
                                     hold_weight = 1) {
  rows <- list()
  append_phase <- function(kind, from, to, weight) {
    rows[[length(rows) + 1L]] <<- data.frame(kind, from, to, weight)
  }
  append_phase("hold", 1L, 1L, hold_weight)
  if (k >= 2L) {
    for (d in seq.int(2L, k)) {
      append_phase("unfold", d - 1L, d, transition_weight)
      append_phase("hold", d, d, hold_weight)
    }
    for (d in seq.int(k, 2L)) {
      append_phase("collapse", d, d - 1L, transition_weight)
      append_phase("hold", d - 1L, d - 1L, hold_weight)
    }
  }
  schedule <- do.call(rbind, rows)
  schedule$end <- cumsum(schedule$weight) / sum(schedule$weight) * target_seconds
  schedule$start <- c(0, schedule$end[-nrow(schedule)])
  schedule
}

dimension_gates <- function(time, schedule, k) {
  gates <- rep(1, k)
  if (k >= 2L) {
    for (d in seq.int(2L, k)) {
      rise <- schedule[schedule$kind == "unfold" & schedule$to == d, ]
      fall <- schedule[schedule$kind == "collapse" & schedule$from == d, ]
      gates[d] <- smoothstep01((time - rise$start) / (rise$end - rise$start)) *
        (1 - smoothstep01((time - fall$start) / (fall$end - fall$start)))
    }
  }
  gates
}
