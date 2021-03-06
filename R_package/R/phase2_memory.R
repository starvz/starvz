#' @include starvz_data.R

events_memory_chart <- function(data = NULL, globalEndTime = NULL, combined = FALSE, tstart = NULL, tend = NULL) {
  if (is.null(data)) stop("data provided to memory_chart is NULL")

  loginfo("Entry of events_memory_chart")

  memory_states <- c("Allocating Async Start", "Allocating Async End", "Allocating Start", "Allocating End", "WritingBack Start", "WritingBack End", "Free Start", "Free End")
  memory_states_start <- c("Allocating Async Start", "Allocating Start", "WritingBack Start", "Free Start")

  # Filter
  dfwapp <- data$Events_memory %>%
    filter(.data$Type %in% memory_states) %>%
    group_by(.data$Container, .data$Handle, .data$Tid, .data$Src) %>%
    arrange(.data$Start) %>%
    mutate(End = lead(.data$Start)) %>%
    filter(.data$Type %in% memory_states_start) %>%
    mutate(Duration = .data$End - .data$Start) %>%
    mutate(Type = gsub(" Start", "", .data$Type))

  # Plot
  gow <- ggplot() +
    default_theme(data$config$base_size, data$config$expand)

  # Add states and outliers if requested
  gow <- gow + geom_events(data, dfwapp, combined = combined, tstart = tstart, tend = tend)
  if (combined) {
    gow <- gow + geom_links(data,
      combined = TRUE, tstart = tstart, tend = tend,
      state_height = data$config$state$height,
      arrow_active = data$config$memory$transfers$arrow,
      border_active = data$config$memory$transfers$border,
      total_active = data$config$memory$transfers$total
    )
  }

  loginfo("Exit of events_memory_chart")
  return(gow)
}


link_chart <- function(data = NULL, tstart = NULL, tend = NULL) {
  if (is.null(data)) stop("data provided to memory_chart is NULL")

  loginfo("Entry of link_chart")

  # Plot
  gow <- ggplot() +
    default_theme(data$config$base_size, data$config$expand)

  # Add states and outliers if requested
  gow <- gow + geom_links(data,
    tstart = tstart, tend = tend,
    state_height = data$config$state$height,
    arrow_active = data$config$memory$transfers$arrow,
    border_active = data$config$memory$transfers$border,
    total_active = data$config$memory$transfers$total
  )

  # gow = gow + scale_fill_manual(values = starpu_colors());

  loginfo("Exit of link_chart")
  return(gow)
}

geom_events <- function(main_data = NULL, data = NULL,
                        combined = FALSE, tstart = NULL,
                        tend = NULL) {
  if (is.null(data)) stop("data is NULL when given to geom_events")

  loginfo("Starting geom_events")

  dfw <- data

  dfl <- main_data$Link

  col_pos_1 <- data.frame(Container = unique(dfl$Dest)) %>%
    arrange(.data$Container) %>%
    rowid_to_column("Position")

  col_pos_2 <- data.frame(Container = unique(dfw$Container)) %>%
    arrange(.data$Container) %>%
    rowid_to_column("Position")

  if (nrow(col_pos_1) > nrow(col_pos_2)) {
    col_pos <- col_pos_1
  } else {
    col_pos <- col_pos_2
  }

  col_pos[2] <- data.frame(lapply(col_pos[2], as.character), stringsAsFactors = FALSE)
  dfw <- dfw %>% left_join(col_pos, by = c("Container" = "Container"))

  ret <- list()

  dfw$Height <- 1

  # Y axis breaks and their labels
  # Hardcoded here because yconf is specific to Resources Workers
  yconfm <- dfw %>%
    unnest() %>%
    ungroup() %>%
    select(.data$Container, .data$Position, .data$Height) %>%
    distinct() %>%
    group_by(.data$Container) %>%
    arrange(.data$Container) %>%
    ungroup()

  yconfm <- yconfm %>%
    unnest() %>%
    arrange(.data$Container)

  if (!combined) {
    ret[[length(ret) + 1]] <- scale_y_continuous(breaks = yconfm$Position + (yconfm$Height / 3), labels = yconfm$Container, expand = c(main_data$config$expand, 0))
  } else {
    dfw$Position <- dfw$Position - 0.3
  }

  # Y label
  ret[[length(ret) + 1]] <- ylab("Mem Managers")


  border <- 0
  if (main_data$config$memory$state$border) {
    border <- 1
  }

  # Add states
  ret[[length(ret) + 1]] <- geom_rect(
    data = dfw,
    aes(fill = .data$Type, xmin = .data$Start, xmax = .data$End, ymin = .data$Position, ymax = .data$Position + (2.0 - 0.2 - .data$Height)), color = "black", linetype = border, size = 0.4, alpha = 0.5
  )



  if (main_data$config$memory$state$text) {
    dx <- dfw %>%
      filter(.data$Type == "Allocating") %>%
      left_join(main_data$Data_handles, by = c("Handle" = "Handle")) %>%
      select(-.data$Tid, -.data$Src, -.data$Value)
    dx$Coordinates <- gsub(" ", "x", dx$Coordinates)

    ret[[length(ret) + 1]] <- geom_text(
      data = dx, colour = "black", fontface = "bold",
      aes(
        x = .data$Start + .data$Duration / 2, y = .data$Position + (2.0 - 0.2 - .data$Height) / 2,
        label = .data$Coordinates
      ), size = 5, alpha = 1.0,
      angle = main_data$config$memory$state$angle, show.legend = FALSE
    )
  }

  ret[[length(ret) + 1]] <- theme(
    legend.spacing.x = unit(2, "mm")
  )

  if (main_data$config$memory$state$total) {
    select <- main_data$config$memory$state$select
    ms <- dfw %>%
      filter(.data$Type == select, .data$Start < tend, .data$End > tstart) %>%
      mutate(Start = ifelse(.data$Start < tstart, tstart, .data$Start)) %>%
      mutate(End = ifelse(.data$End > tend, tend, .data$End))

    # Calculate selected state % in time
    total_time <- tend - tstart

    ms <- ms %>%
      group_by(.data$Container, .data$Position) %>%
      summarize(percent_time = round((sum(.data$End - .data$Start) / total_time) * 100, 2))
    if (nrow(ms) != 0) {
      # ms[2] <- data.frame(lapply(ms[2], as.character), stringsAsFactors=FALSE);
      # ms <- ms %>% left_join(col_pos, by=c("ResourceId" = "ResourceId"));
      ms$Value <- select
      globalEndTime <- tend - (tend - tstart) * 0.05
      ms$percent_time <- paste0(ms$percent_time, "%")
      ret[[length(ret) + 1]] <- geom_label(
        data = ms, x = globalEndTime, colour = "black", fontface = "bold",
        aes(y = .data$Position + 0.4, label = .data$percent_time, fill = .data$Value), alpha = 1.0, show.legend = FALSE, size = 5
      )
    }
  }

  loginfo("Finishing geom_events")

  return(ret)
}

geom_links <- function(data = NULL, combined = FALSE,
                       tstart = NULL, tend = NULL,
                       state_height = 1,
                       arrow_active = FALSE,
                       border_active = FALSE,
                       total_active = FALSE) {
  if (is.null(data)) stop("data is NULL when given to geom_links")

  # Get the start info on states because link dont have nodes & Position

  dfl <- data$Link

  loginfo("Starting geom_links")

  col_pos <- as.tibble(data.frame(ResourceId = unique(dfl$Dest)) %>% arrange(.data$ResourceId) %>% rowid_to_column("Position"))
  col_pos[2] <- data.frame(lapply(col_pos[2], as.character), stringsAsFactors = FALSE)

  if (combined) {
    col_pos$Position <- col_pos$Position * state_height
  }

  ret <- list()

  dfl <- dfl %>%
    left_join(col_pos, by = c("Origin" = "ResourceId")) %>%
    rename(O_Position = .data$Position) %>%
    left_join(col_pos, by = c("Dest" = "ResourceId")) %>%
    rename(D_Position = .data$Position)
  stride <- 0.3

  dfl$Height <- 1

  yconfm <- dfl %>%
    select(.data$Origin, .data$O_Position, .data$Height) %>%
    distinct() %>%
    group_by(.data$Origin) %>%
    arrange(.data$Origin) %>%
    ungroup()

  yconfm$Height <- 1
  yconfm$Origin <- lapply(yconfm$Origin, function(x) gsub("MEMMANAGER", "MM", x))

  if (combined) {
    stride <- stride * state_height
    ret[[length(ret) + 1]] <- scale_y_continuous(breaks = yconfm$O_Position, labels = yconfm$Origin, expand = c(0.10, 0.1))
    stride <- 0.0
  }

  if (!combined) {

    # dfw <- dfw %>% select(-Position) %>% left_join(col_pos, by=c("ResourceId" = "ResourceId"));
    # Hardcoded here because yconf is specific to Resource Workers

    ret[[length(ret) + 1]] <- scale_y_continuous(breaks = yconfm$D_Position, labels = yconfm$Dest, expand = c(0.10, 0.5))

    # Color mapping
    # ret[[length(ret)+1]] <- scale_fill_manual(values = extract_colors(dfw));

    # Y label
    ret[[length(ret) + 1]] <- ylab("Transfers")
    stride <- 0.0
  }
  dfl$O_Position <- dfl$O_Position + stride
  dfl$D_Position <- dfl$D_Position + stride
  arrow_g <- NULL
  if (arrow_active) {
    arrow_g <- arrow(length = unit(0.15, "cm"))
  }
  if (border_active) {
    ret[[length(ret) + 1]] <- geom_segment(
      data = dfl,
      aes(x = .data$Start, xend = .data$End, y = .data$O_Position, yend = .data$D_Position), arrow = arrow_g, alpha = 0.5, size = 1.5, color = "black"
    )
  }

  ret[[length(ret) + 1]] <- geom_segment(data = dfl, aes(
    x = .data$Start, xend = .data$End,
    y = .data$O_Position, yend = .data$D_Position, color = .data$Origin
  ), arrow = arrow_g, alpha = 1.0)
  selected_dfl <- dfl %>%
    filter(.data$End > tstart) %>%
    filter(.data$Start < tend)

  # ret[[length(ret)+1]] <- geom_text(data=dfl, colour = "black", fontface = "bold", aes(x = Start, y = O_Position, label=Key), size = 3, alpha=1.0, show.legend = FALSE);
  if (total_active) {
    total_links <- data.frame(with(selected_dfl, table(Origin)))
    if (nrow(total_links) != 0 & !combined) {
      total_links[1] <- data.frame(lapply(total_links[1], as.character), stringsAsFactors = FALSE)
      total_links <- total_links %>% left_join(col_pos, by = c("Origin" = "ResourceId"))

      globalEndTime <- tend - (tend - tstart) * 0.05

      ret[[length(ret) + 1]] <- geom_label(
        data = total_links, x = globalEndTime, colour = "white", fontface = "bold",
        aes(y = .data$Position, label = .data$Freq, fill = .data$Origin), alpha = 1.0, show.legend = FALSE
      )
    }
  }
  loginfo("Finishing geom_links")

  return(ret)
}

handles_presence_states <- function(data) {
  # Selecting only the data state events
  data$Events_data %>%
    filter(.data$Type == "data state invalid" |
      .data$Type == "data state owner" |
      .data$Type == "data state shared") %>%
    select(.data$Container, .data$Start, .data$Type, .data$Value) -> data_state_events

  end <- max(data$Starpu$End)

  fini_end <- unlist(end)

  data_state_events %>%
    group_by(.data$Value, .data$Container) %>%
    mutate(rep = case_when(
      .data$Type == "data state owner" ~ 1,
      .data$Type == "data state invalid" ~ 2,
      TRUE ~ 5
    )) %>%
    mutate(flow = c(1, diff(.data$rep)), t_diff = c(diff(.data$Start), 1)) %>%
    mutate(need = .data$flow != 0 & .data$t_diff > 0.001) %>%
    filter(.data$need == TRUE) %>%
    mutate(flow = c(1, diff(.data$rep))) %>%
    mutate(need = .data$flow != 0) %>%
    filter(.data$need == TRUE) %>%
    mutate(End = lead(.data$Start, default = unlist(fini_end))) %>%
    filter(.data$Type != "data state invalid") %>%
    select(-.data$rep, -.data$flow, -.data$t_diff, -.data$need) %>%
    ungroup() %>%
    group_by(.data$Value, .data$Container) -> f_data

  return(f_data)
}

data_name_coordinates <- function(df) {
  df %>% mutate(Value = paste0("Memory Block ", .data$Coordinates, ""))
}

data_name_tag <- function(df) {
  if ("MPITag" %in% names(df)) {
    df %>% mutate(Value = paste0("Memory Block ", as.character(.data$MPITag), "")) -> ret
  } else {
    df %>% mutate(Value = paste0("Memory Block ", as.character(.data$Tag), "")) -> ret
  }
  return(ret)
}

data_name_handle <- function(df) {
  df %>% mutate(Value = paste0("Memory Block ", .data$Handle, ""))
}

pre_handle_gantt <- function(data, name_func = NULL) {
  # If not user defined lets try to select the best
  # function to give name to our handles
  # We will try first to use coordinates
  # good case in linear algebra where block dont repeat coordinates
  # if not available it will fail to TAGs, this is safe in recent
  # StarPU versions but may be unavailable
  # if these two fail the only option is to assume the handle address
  # that will not match between MPI executions...
  if (is.null(name_func)) {
    use_coord <- FALSE
    if ("Coordinates" %in% names(data$Data_handles)) {
      data$Data_handles %>% .$Coordinates -> cc
      if (!is.null(cc[[1]]) && !is.na(cc[[1]]) && cc[[1]] != "") {
        use_coord <- TRUE
      }
    }
    name_func <- data_name_handle
    if ("MPITag" %in% names(data$Data_handles)) {
      name_func <- data_name_tag
    }
    if (use_coord) {
      name_func <- data_name_coordinates
    }
  }

  data$Events_memory <- data$Events_memory %>%
    mutate(Type = as.character(.data$Type)) %>%
    mutate(Type = case_when(
      .data$Type == "Allocating Start" ~ "Allocation Request",
      .data$Type == "Request Created" ~ "Transfer Request",
      TRUE ~ .data$Type
    ))

  if (is.null(data$handle_states)) {
    data$handle_states <- handles_presence_states(data)
  }

  position <- data$handle_states %>%
    ungroup() %>%
    select(.data$Container) %>%
    distinct() %>%
    arrange(.data$Container) %>%
    mutate(y1 = 1:n())

  p_data <- data$handle_states %>%
    mutate(Colour = ifelse(.data$Type == "data state owner", "Owner", "Shared")) %>%
    inner_join(position, by = c("Container" = "Container")) %>%
    select(.data$Container, .data$Start, .data$End, .data$Value, .data$y1, .data$Colour)


  p_data %>%
    select(.data$Container, .data$Value, .data$y1) %>%
    distinct() -> pre_p_data

  data$Task_handles %>%
    filter(!is.na(.data$JobId)) %>%
    inner_join(data$Tasks %>% filter(!is.na(.data$JobId)), by = c("JobId" = "JobId")) %>%
    select(.data$JobId, .data$Handles, .data$MPIRank, .data$MemoryNode) %>%
    mutate(sContainer = paste0(.data$MPIRank, "_MEMMANAGER", .data$MemoryNode)) -> job_handles

  job_handles %>%
    inner_join(pre_p_data, by = c("Handles" = "Value")) %>%
    select(.data$Container, .data$sContainer, .data$JobId, .data$Handles, .data$y1, .data$MemoryNode) %>%
    filter(.data$sContainer == .data$Container) %>%
    mutate(JobId = as.character(.data$JobId)) %>%
    inner_join(data$Application, by = c("JobId" = "JobId")) %>%
    select(.data$Container, .data$JobId, .data$Handles, .data$Start, .data$End, .data$y1, .data$Value) %>%
    rename(Colour = .data$Value) %>%
    rename(Value = .data$Handles) -> jobs_p_data
  p_data$size <- 0.8
  jobs_p_data$size <- 0.6

  all_st_m_data <- bind_rows(p_data, jobs_p_data) %>%
    inner_join(data$Data_handle, by = c("Value" = "Handle")) %>%
    ungroup() %>%
    name_func() %>%
    select(.data$Container, .data$Start, .data$End, .data$Value, .data$y1, .data$Colour, .data$size, .data$JobId) %>%
    group_by(.data$Value, .data$Container)

  # Processing the Events: Request & Allocation

  data$Events_memory %>% filter(.data$Type == "Transfer Request") -> TR
  if (TR %>% nrow() > 0) {
    TR %>%
      mutate(P = substring(.data$Tid, 5)) %>%
      mutate(G = substr(.data$Container, 1, nchar(as.character(.data$Container)) - 1)) %>%
      mutate(Container = paste0(.data$G, .data$P)) %>%
      select(-.data$P, -.data$G) %>%
      select(-.data$Tid) %>%
      inner_join(data$Data_handle, by = c("Handle" = "Handle")) %>%
      inner_join(position, by = c("Container" = "Container")) %>%
      name_func() %>%
      select(.data$Container, .data$Type, .data$Start, .data$Value, .data$Info, .data$y1) %>%
      filter(.data$Type == "Transfer Request") %>%
      mutate(Pre = as.character(.data$Info)) -> request_events
  } else {
    request_events <- NULL
  }

  data$Task_handles %>%
    select(.data$Handles) %>%
    distinct() %>%
    .$Handles -> h_used
  data$Events_memory %>%
    filter(.data$Handle %in% h_used) %>%
    select(-.data$Tid) %>%
    inner_join(data$Data_handle, by = c("Handle" = "Handle")) %>%
    inner_join(position, by = c("Container" = "Container")) %>%
    name_func() %>%
    select(.data$Container, .data$Type, .data$Start, .data$Value, .data$Info, .data$y1) %>%
    filter(.data$Type == "Allocation Request") -> allocation_events

  allocation_events %>%
    group_by(.data$Value, .data$Container, .data$Type) %>%
    mutate(Old = lag(.data$Start, default = -5), R = abs(.data$Start - .data$Old)) %>%
    filter(.data$R > 1) %>%
    select(-.data$Old, -.data$R) -> allocation_events_filtered

  allocation_events_filtered$Pre <- "0"

  events_points <- bind_rows(request_events, allocation_events_filtered)

  # Processing Links (Transfers)
  data$Events_memory %>%
    filter(.data$Type == "DriverCopy Start") %>%
    select(.data$Handle, .data$Info, .data$Container) %>%
    mutate(Info = as.integer(.data$Info)) -> links_handles

  links <- data$Link %>%
    filter(.data$Type == "Intra-node data Fetch" |
      .data$Type == "Intra-node data PreFetch") %>%
    select(-.data$Container, -.data$Size) %>%
    mutate(Con = as.integer(substring(.data$Key, 5))) %>%
    select(-.data$Key)

  final_links <- links %>%
    inner_join(links_handles, by = c("Con" = "Info", "Dest" = "Container")) %>%
    inner_join(position, by = c("Origin" = "Container")) %>%
    rename(origin_y = .data$y1) %>%
    inner_join(position, by = c("Dest" = "Container")) %>%
    rename(dest_y = .data$y1) %>%
    inner_join(data$Data_handle, by = c("Handle" = "Handle")) %>%
    name_func() %>%
    select(.data$Type, .data$Start, .data$End, .data$Value, .data$origin_y, .data$dest_y) %>%
    rename(Transfer = .data$Type)

  if ("MPI communication" %in% unique(data$Link$Type)) {
    mpi_links <- data$Link %>%
      filter(.data$Type == "MPI communication") %>%
      select(-.data$Container, -.data$Size) %>%
      mutate(Origin = str_replace(.data$Origin, "mpict", "MEMMANAGER0")) %>%
      mutate(Dest = str_replace(.data$Dest, "mpict", "MEMMANAGER0")) %>%
      inner_join(position, by = c("Origin" = "Container")) %>%
      rename(origin_y = .data$y1) %>%
      inner_join(position, by = c("Dest" = "Container")) %>%
      rename(dest_y = .data$y1) %>%
      mutate(Tag = as.numeric(as.character(.data$Tag))) %>%
      inner_join(data$Data_handle, by = c("Tag" = "MPITag")) %>%
      name_func() %>%
      select(.data$Type, .data$Start, .data$End, .data$Value, .data$origin_y, .data$dest_y) %>%
      rename(Transfer = .data$Type) %>%
      unique()
   
    all_links <- bind_rows(mpi_links, final_links)
  } else {
    all_links <- final_links
  }
    
  return(list(
    all_st_m_data = all_st_m_data,
    events_points = events_points,
    final_links = all_links,
    position = position,
    name_func = name_func
  ))
}

handles_gantt <- function(data, JobId = NA, lines = NA, lHandle = NA) {
  if (is.null(data$handle_gantt_data)) {
    data$handle_gantt_data <- pre_handle_gantt(data)
  }

  if (is.na(JobId) && is.na(lHandle)) {
    final_st_data <- data$handle_gantt_data$all_st_m_data
    final_events_data <- data$handle_gantt_data$events_points
    final_links_data <- data$handle_gantt_data$final_links
  } else if (!is.na(lHandle)) {
    final_st_data <- data$handle_gantt_data$all_st_m_data %>% filter(.data$Value %in% lHandle)
    final_events_data <- data$handle_gantt_data$events_points %>% filter(.data$Value %in% lHandle)
    final_links_data <- data$handle_gantt_data$final_links %>% filter(.data$Value %in% lHandle)
  } else {
    myjobid <- JobId
    data$Task_handles %>%
      filter(.data$JobId == myjobid) %>%
      inner_join(data$Data_handle, by = c("Handles" = "Handle")) %>%
      ungroup() -> xx
    data$handle_gantt_data$name_func(xx) %>%
      .$Value -> selected_handles

    final_st_data <- data$handle_gantt_data$all_st_m_data %>% filter(.data$Value %in% selected_handles)
    final_events_data <- data$handle_gantt_data$events_points %>% filter(.data$Value %in% selected_handles)
    final_links_data <- data$handle_gantt_data$final_links %>% filter(.data$Value %in% selected_handles)
  }

  events_colors <- brewer.pal(n = 6, name = "Dark2")

  extra <- c(
    "Owner" = "darksalmon",
    "Shared" = "steelblue1",
    " " = "white"
  )

  data$Colors %>% select(.data$Value, .data$Color) -> lc

  lc %>%
    .$Color %>%
    setNames(lc %>% .$Value) -> fc

  fills <- append(fc, extra)

  colors <- c(
    "Allocation Request" = events_colors[[1]],
    "Transfer Request" = events_colors[[2]],
    "Intra-node data Fetch" = events_colors[[3]],
    "Intra-node data PreFetch" = events_colors[[4]],
    "MPI communication" = events_colors[[5]],
    "Last Job on same Worker" = events_colors[[6]]
  )

  arrow_g <- arrow(length = unit(0.1, "cm"))

  p <- ggplot(data = final_st_data) +
    theme_bw(base_size = 16) +
    geom_point(
      data = final_events_data,
      aes(
        x = .data$Start,
        y = .data$y1 + 0.4,
        colour = .data$Type,
        shape = .data$Pre
      ),
      size = 2.5, stroke = 1
    ) +
    geom_rect(aes(
      xmin = .data$Start,
      xmax = .data$End,
      fill = .data$Colour,
      ymin = .data$y1 + ifelse(is.na(JobId), 0, 0.2),
      ymax = .data$y1 + .data$size
    ),
    colour = "black",
    size = 0.1
    ) +
    scale_fill_manual(
      name = "State         Task", values = fills,
      drop = FALSE,
      limits = names(fills),
      guide = guide_legend(
        nrow = 3, title.position = "top", order = 1,
        override.aes =
          list(shape = NA, colour = NA)
      )
    ) +
    scale_colour_manual(
      name = "Event", values = colors,
      drop = FALSE,
      breaks = c(
        "Allocation Request",
        "Transfer Request",
        "Intra-node data Fetch",
        "Intra-node data PreFetch",
        "MPI communication"
      ),
      limits = c(
        "Allocation Request",
        "Transfer Request",
        "Intra-node data Fetch",
        "Intra-node data PreFetch",
        "MPI communication"
      ),
      guide = guide_legend(
        nrow = 5, title.position = "top", order = 0,
        override.aes =
          list(
            arrow = NA, linetype = 0, shape = c(19, 19, 15, 15, 15),
            yintercept = NA
          )
      )
    ) +
    scale_shape_manual(
      name = "Event Type", labels = c("Fetch", "Prefetch", "Idle Fetch"), values = c(19, 21, 23),
      guide = guide_legend(nrow = 3, title.position = "top")
    ) +
    # Arrow Border
    geom_segment(
      data = final_links_data,
      aes(
        x = .data$Start,
        xend = .data$End,
        y = .data$origin_y + 0.4,
        yend = .data$dest_y + 0.4
      ),
      arrow = arrow_g,
      colour = "black",
      alpha = 0.8,
      size = 1.2
    ) +
    geom_segment(
      data = final_links_data,
      aes(
        x = .data$Start,
        xend = .data$End,
        y = .data$origin_y + 0.4,
        yend = .data$dest_y + 0.4,
        colour = .data$Transfer
      ),
      arrow = arrow_g,
      size = 0.6, show.legend = FALSE
    ) +
    geom_segment(
      data = final_links_data,
      aes(
        x = .data$Start,
        xend = .data$End,
        y = .data$origin_y + 0.4,
        yend = .data$dest_y + 0.4,
        colour = .data$Transfer
      ),
      size = 0.6
    ) +
    scale_y_continuous(
      breaks = data$handle_gantt_data$position$y1 + 0.4,
      labels = data$handle_gantt_data$position$Container
    ) +
    # geom_segment(data=handle_end_m,
    #             aes(x = End, y = MemoryNode+1, xend = End, yend = MemoryNode+1.8), color = "red") +
    facet_wrap(.data$Value ~ ., strip.position = "top", ncol = 1) +
    scale_x_continuous(
      expand = c(0, 0),
      # breaks = c(5000, 5185, 5486, 5600, 5676, 5900),
      labels = function(x) format(x, big.mark = "", scientific = FALSE)
    ) +
    # coord_cartesian(xlim=c(5000, 6000)) +
    # scale_color_manual(values=c("red"="red", "blue"="blue")) +
    # scale_colour_identity() +
    theme(
      strip.text.y = element_text(angle = 0),
      legend.box.margin = margin(-10, -10, -16, -10),
      legend.background = element_rect(fill = "transparent"),
      legend.position = "top"
    ) +
    labs(x = "Time [ms]", y = "Memory Manager")


  if (!is.na(lines)) {
    p <- p + geom_vline(data = lines, aes(xintercept = .data$x, color = .data$colors), alpha = 0.7, size = 1)
  }
  # if(!is.na(JobId)){
  #   my_job <- JobId
  #   data$Starpu %>% filter(JobId==my_job) %>% .$Start -> job_start
  #   data$Starpu %>% filter(JobId==my_job) %>% .$Duration -> job_dur
  #   data$Tasks %>% filter(JobId==my_job) %>% .$ MemoryNode -> job_node
  #   text <- data.frame(x=c(job_start+job_dur/2), y=c(job_node+1.4), text=c(my_job))
  #   p <- p + geom_text(data=text, aes(x=x, y=y, label=my_job), color="black", size=2,
  # 		  fontface="bold",
  # 	  alpha=0.8)
  # }
  return(p)
}


pre_snap <- function(data, f_data) {
  data$Data_handles %>%
    separate(.data$Coordinates, c("Y", "X")) %>%
    mutate(X = as.numeric(.data$X), Y = as.numeric(.data$Y)) -> new_handles


  new_handles %>% select(.data$Handle, .data$X, .data$Y) -> hand

  f_data %>%
    ungroup() %>%
    select(.data$Container) %>%
    distinct() %>%
    .$Container -> cont
  hand <- hand %>% mutate(Container = list(cont))
  hand %>% unnest() -> hand

  f_data %>% mutate(st = ifelse(.data$Type == "data state owner", "Owner", "Shared")) -> d_presence

  data$Application %>%
    mutate(JobId = .data$JobId) %>%
    inner_join(data$Tasks, by = c("JobId" = "JobId")) %>%
    select(.data$Start, .data$End, .data$Value, .data$JobId, .data$MemoryNode, .data$MPIRank, .data$Color) %>%
    inner_join(data$Task_handles, by = c("JobId" = "JobId")) %>%
    mutate(Container = ifelse(.data$MPIRank >= 0, paste0(.data$MPIRank, "_MEMMANAGER", .data$MemoryNode), paste0("MEMMANAGER", .data$MemoryNode))) %>%
    select(.data$Handles, .data$Modes, .data$Start, .data$End, .data$Value, .data$JobId, .data$Container, .data$Color) -> tasks

  return(list(d_presence, hand, tasks))
}

memory_snap <- function(data, selected_time, step, tasks_size = 30) {
  data[[3]] %>%
    select(.data$Value, .data$Color) %>%
    distinct() -> c_info

  colors <- c("darksalmon", "steelblue1")

  colors <- c(colors, c_info$Color)

  c_names <- c("Owner", "Shared")
  c_names <- c(c_names, c_info$Value)

  data[[1]] %>%
    filter(.data$Start < selected_time, .data$End > selected_time) %>%
    right_join(data[[2]], by = c("Value" = "Handle", "Container" = "Container")) -> d_presence

  task_presence <- data[[3]] %>%
    filter(.data$Start <= selected_time, .data$End >= selected_time) %>%
    inner_join(data[[2]], by = c("Handles" = "Handle", "Container" = "Container"))

  task_presence_alpha <- data[[3]] %>%
    filter(.data$Start > selected_time - step, .data$End <= selected_time) %>%
    inner_join(data[[2]], by = c("Handles" = "Handle", "Container" = "Container"))

  max_x <- data[[2]] %>%
    arrange(-.data$X) %>%
    slice(1) %>%
    .$X %>%
    unlist()

  p <- ggplot(d_presence, aes(.data$Y, .data$X)) +
    geom_tile(aes(fill = .data$st),
      colour = "white"
    ) +
    geom_point(
      data = task_presence_alpha,
      aes(
        fill = .data$Value,
        x = .data$Y,
        y = .data$X,
        shape = .data$Modes
      ),
      colour = "black",
      size = (tasks_size / max_x), stroke = 0.2, alpha = 0.3
    ) +
    geom_point(
      data = task_presence,
      aes(
        fill = .data$Value,
        x = .data$Y,
        y = .data$X,
        shape = .data$Modes
      ),
      colour = "black",
      size = (tasks_size / max_x), stroke = 0.2
    ) +
    scale_shape_manual(
      values = c("R" = 21, "W" = 22, "RW" = 22), drop = FALSE,
      limits = c("R", "RW"),
      guide = guide_legend(title.position = "top")
    ) +
    scale_fill_manual(
      name = "State", values = colors, drop = FALSE,
      limits = c_names,
      guide = guide_legend(
        title.position = "top", override.aes =
          list(shape = NA, stroke = 1)
      )
    ) +
    scale_y_reverse(limits = c(max_x + 0.6, -0.6), expand = c(0, 0)) +
    scale_x_continuous(limits = c(-0.6, max_x + 0.6), expand = c(0, 0)) +
    facet_wrap(~Container) +
    labs(x = "Block X Coordinate", y = "Block Y Coordinate") +
    theme_bw(base_size = 16) +
    theme(
      legend.position = "top",
      plot.margin = unit(c(0, 10, 0, 0), "mm"),
      legend.box.margin = margin(-5, 0, -16, 0),
      strip.text.x = element_text(margin = margin(.1, 0, .1, 0, "cm")),
      legend.background = element_rect(fill = "transparent"),
      panel.grid.major = element_blank(),
      panel.grid.minor = element_blank(),
      panel.spacing = unit(1, "mm")
    )

  return(p)
}

multiple_snaps <- function(snap_data, start, end, step, path) {
  se <- seq(start, end, step)
  se <- c(se, end)
  i <- 1
  for (time in se) {
    p <- memory_snap(snap_data, time, step, tasks_size = 40)
    p <- p + ggtitle(paste0("Time: ", as.character(time)))
    ggsave(paste0(path, i, ".png"), plot = p, scale = 4, width = 4, height = 3, units = "cm")
    i <- i + 1
  }
}

handles_help <- function() {
  print("To accelerate the process:")
  print("data$handle_states <- handles_presence_states(data)")
  print("data$handle_gantt_data <- pre_handle_gantt(data)")
  print("To Select time:")
  print("handles_gantt(data, JobId=c(jobid)) + coord_cartesian(xlim=c(start, end))")
  print("snap_data <- pre_snap(data, data$handle_states)")
  print("memory_snap(snap_data, 1000, tasks_size=200, step=1)")
}
