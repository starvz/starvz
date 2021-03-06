#' @include starvz_data.R

#' Create a space time visualization as a Gantt chart    
#'
#' Use the Application trace data to plot the task computations by ResourceId
#' over the execution time. 
#'
#' @param data starvz_data with trace data
#' @param ST.Outliers enable/disable the anomalous task highlighting
#' @param base_size base_size base font size
#' @param expand_x expand size for scale_x_continuous padding
#' @param expand_y expand size for scale_y_continuous padding
#' @param selected_nodes select only some nodes in some plots
#' @param labels control resources labels: [ALL, 1CPU_per_NODE, 1GPU_per_NODE]
#' @param alpha alpha value for non anomalous tasks
#' @param idleness enable/disable idleness percentages in the plot
#' @param taskdeps enable/disable task deps path highlighting
#' @param tasklist list of JobIds to highlight the dependencies
#' @param levels number of dependencies to be shown
#' @param makespan enable/disable application makespan at the end of the plot
#' @param abe enable/disable ABE metric
#' @param pmtoolbounds enable/disable pmtool theoretical bounds 
#' @param cpb enable/disable critical path bound makespan metric
#' @param cpb_mpi enable/disable critical path bound makespan considering MPI
#' @param StarPU.View TODO I think we should create a separated function for it
#' @param legend enable/disable legends
#' @return A ggplot object
#' @examples
#' panel_st_raw(data=starvz_data)
#' @export
panel_st_raw <- function(data = NULL, ST.Outliers = TRUE, base_size=22, expand_x=0.05,
  expand_y=0.05, selected_nodes = NULL, labels="ALL", alpha=0.25, idleness=TRUE, 
  taskdeps=FALSE, tasklist = NULL,  levels=10, makespan=TRUE, abe=FALSE, pmtoolbounds=FALSE,
  cpb = FALSE, cpb_mpi = FALSE, legend=TRUE, StarPU.View = FALSE) {
  if (is.null(data)) stop("data provided to state_chart is NULL")

  # Obtain time interval
  tstart <- data$Application$Start %>% min()
  tend <- data$Application$End %>% max()

  # Plot
  gow <- ggplot() +
    default_theme(base_size, expand_x)

  App <- data$Application
  # Select Nodes
  if (!is.null(selected_nodes)) {
    data$Y %>%
      separate(.data$Parent, into = c("Node"), remove = FALSE, extra="drop") %>%
      filter(.data$Node %in% selected_nodes) %>%
      arrange(.data$Position) %>%
      mutate(New = cumsum(lag(.data$Height, default = 0))) %>%
      select(.data$Parent, .data$New) -> new_y
    if (StarPU.View) {
      data$Starpu <- data$Starpu %>%
        left_join(new_y, by = c("ResourceId" = "Parent")) %>%
        mutate(Position = if_else(is.na(.data$New), -3, .data$New)) %>%
        select(-.data$New)
    } else {
      data$Application <- data$Application %>%
        left_join(new_y, by = c("ResourceId" = "Parent")) %>%
        mutate(Position = if_else(is.na(.data$New), -3, .data$New)) %>%
        mutate(Height = if_else(is.na(.data$New), 0, .data$Height)) %>%
        select(-.data$New)
      App <- data$Application %>%
        filter(.data$Position >= 0)
    }
  }

  # Add states and outliers if requested
  if (StarPU.View) {
    gow <- gow + geom_states(data$Starpu,
      ST.Outliers, StarPU.View, data$Colors,
      labels = labels,
      expand = expand_y,
      rect_outline = data$config$st$rect_outline,
      alpha_value = alpha
    )
  } else {
    gow <- gow + geom_states(App,
      ST.Outliers, StarPU.View, data$Colors,
      labels = labels,
      expand = expand_y,
      rect_outline = data$config$st$rect_outline,
      alpha_value = alpha
    )
  }

  if (!StarPU.View) {

    # add idleness
    if (idleness) gow <- gow + geom_idleness(data)

    # check if task dependencies should be added
    if (taskdeps) {
      tasksel <- gaps_backward_deps(
        data = data,
        tasks = tasklist,
        levels = levels
      )
      if (nrow(tasksel)>0 & !is.null(selected_nodes)) {
        tasksel <- tasksel %>%
          left_join(new_y, by = c("ResourceId" = "Parent")) %>%
          mutate(Position = if_else(is.na(.data$New), -3, .data$New)) %>%
          select(-.data$New)
      }

      gow <- gow + geom_path_highlight(tasksel)
    }

    # add Global CPB
    if (cpb || cpb_mpi) gow <- gow + geom_cpb(data)

    # The per-node ABE
    if (abe) gow <- gow + geom_abe(data)

    # add pmtool bound
    if (pmtoolbounds) gow <- gow + geom_pmtool_bounds(data)

    # add makespan
    if (makespan) gow <- gow + geom_makespan(App, bsize = base_size)
  }

  if(!legend) {
    gow <- gow + theme(legend.position = "none")
  }

  return(gow)
}

geom_states <- function(dfw = NULL, Show.Outliers = FALSE, StarPU = FALSE, Colors = NULL,
                        labels = "1",
                        expand = 0.05,
                        rect_outline = FALSE,
                        alpha_value = 0.5) {
  if (is.null(dfw)) stop("data is NULL when given to geom_states")
  if (is.null(Colors)) stop("data is NULL when given to geom_states")

  ret <- list()

  # Color mapping
  if (StarPU) {
    ret[[length(ret) + 1]] <- scale_fill_manual(values = starpu_colors())
  } else {
    ret[[length(ret) + 1]] <- scale_fill_manual(values = extract_colors(dfw, Colors))
  }

  # Y axis breaks and their labels
  yconfm <- yconf(dfw, labels)
  ret[[length(ret) + 1]] <- scale_y_continuous(
    breaks = yconfm$Position + (yconfm$Height / 3), labels = yconfm$ResourceId,
    expand = c(expand, 0)
  )
  # Y label
  ret[[length(ret) + 1]] <- ylab(ifelse(StarPU, "StarPU Workers", "Application Workers"))

  # Add states
  ret[[length(ret) + 1]] <-
    geom_rect(
      data = dfw, aes(
        fill = .data$Value,
        xmin = .data$Start,
        xmax = .data$End,
        ymin = .data$Position,
        ymax = .data$Position + .data$Height - 0.2
      ),
      color = ifelse(rect_outline, "black", NA),
      alpha = ifelse(Show.Outliers && !StarPU, alpha_value, 1.0)
    )

  # Add outliers conditionally
  if (Show.Outliers && !StarPU) {
    ret[[length(ret) + 1]] <-
      geom_rect(
        data = (dfw %>% filter(.data$Outlier == TRUE)),
        aes(
          fill = .data$Value,
          xmin = .data$Start,
          xmax = .data$End,
          ymin = .data$Position,
          ymax = .data$Position + .data$Height - 0.2
        ),
        color = ifelse(rect_outline, "black", NA),
        alpha = 1
      )
  }

  return(ret)
}

geom_path_highlight <- function(paths = NULL) {
  if (is.null(paths)) stop("paths is NULL when given to gaps_backward_deps")
  if ((paths %>% nrow()) == 0) {
    return(list())
  }

  # paths is identical to data$Starpu, but with an additional column called Path

  ret <- list()

  # highlight the tasks involved in the path
  ret[[length(ret) + 1]] <- geom_rect(
    data = paths,
    size = 1,
    aes(
      color = .data$Path,
      xmin = .data$Start,
      xmax = .data$End,
      ymin = .data$Position,
      ymax = .data$Position + .data$Height - 0.2
    ), alpha = 0
  )

  # let's draw lines connecting tasks in the path

  # collect each JobId coordinates
  paths %>%
    select(.data$JobId, .data$Start, .data$End, .data$Position, .data$Height) %>%
    unique() -> x1
  # gather coordinates for the lines
  paths %>%
    select(.data$Path, .data$JobId, .data$Dependent) %>%
    left_join(x1, by = c("JobId" = "JobId")) %>%
    left_join(x1, by = c("Dependent" = "JobId")) %>%
    na.omit() -> pathlines

  ret[[length(ret) + 1]] <- geom_segment(
    data = pathlines,
    aes(
      x = .data$Start.x,
      xend = .data$End.y,
      y = .data$Position.x + (.data$Height.x / 2),
      yend = .data$Position.y + (.data$Height.y / 2),
      color = .data$Path
    )
  )
  return(ret)
}

node_aggregation <- function(data) {
  step <- 100
  df <- time_aggregation_prep(data$Application)
  df <- time_aggregation_do(df %>%
    group_by(.data$Node, .data$ResourceId, .data$ResourceType, .data$Task), step)
  df.spatial <- node_spatial_aggregation(df)

  space.within <- 0.01
  space.between <- 0.0
  space <- space.between
  df.spatial %>%
    mutate(Node = as.integer(as.character(.data$Node))) %>%
    select(.data$Node, .data$ResourceType) %>%
    unique() %>%
    mutate(ResourceType.Height = 1) %>%
    arrange(-.data$Node) %>%
    mutate(ResourceType.Position = cumsum(lag(.data$ResourceType.Height, default = 0) + space) - space) %>%
    as.data.frame() -> df.node_position

  df.spatial %>%
    mutate(Start = .data$Slice, End = .data$Start + .data$Duration) %>%
    mutate(Node = as.integer(as.character(.data$Node))) %>%
    left_join(df.node_position, by = c("Node", "ResourceType")) %>%
    group_by(.data$Node, .data$ResourceType, .data$Slice) %>%
    arrange(-.data$Node) %>%
    mutate(Position = .data$ResourceType.Position + cumsum(.data$Activity) - .data$Activity) %>%
    mutate(Height = 1) %>%
    ungroup() -> df.spatial_prep

  hl_per_node_ABE(data$Application) %>%
    mutate(Node = as.integer(as.character(.data$Node))) %>%
    select(-.data$MinPosition, -.data$MaxPosition) %>%
    left_join(df.node_position %>% select(.data$Node, .data$ResourceType.Position, .data$ResourceType.Height) %>% unique(), by = c("Node")) %>%
    select(.data$Node, .data$Result, .data$ResourceType.Position, .data$ResourceType.Height) %>%
    arrange(-.data$Node) %>%
    group_by(.data$Node, .data$Result) %>%
    summarize(
      Node.Position = min(.data$ResourceType.Position),
      Node.Height = sum(.data$ResourceType.Height)
    ) %>%
    ungroup() %>%
    mutate(MinPosition = .data$Node.Position) %>%
    mutate(MaxPosition = .data$Node.Position + .data$Node.Height + space.between) -> df.pernodeABE

  df.node_position %>%
    group_by(.data$Node) %>%
    summarize(Node.Position = min(.data$ResourceType.Position) + sum(.data$ResourceType.Height)) %>%
    mutate(Label = .data$Node) -> yconf

  new_state_plot <- df.spatial_prep %>%
    ggplot() +
    default_theme(data$config$base_size, data$config$expand) +
    xlab("Time [ms]") +
    scale_fill_manual(values = extract_colors(df.spatial_prep %>% rename(Value = .data$Task), data$Colors)) +
    scale_y_continuous(
      breaks = yconf$Node.Position,
      labels = yconf$Label, expand = c(data$config$expand, 0)
    ) +
    ylab("Node Ocupation") +
    geom_rect(aes(
      fill = .data$Task,
      xmin = .data$Start,
      xmax = .data$End,
      ymin = .data$Position,
      ymax = .data$Position + .data$Activity
    ), alpha = .5)

  if (data$config$st$makespan) new_state_plot <- new_state_plot + geom_makespan(df.spatial_prep, bsize = data$config$base_size)

  if (data$config$st$abe$active) {
    new_state_plot <- new_state_plot +
      geom_abe_internal(df.pernodeABE,
        base_size = data$config$base_size,
        abesize = data$config$st$abe$size,
        bar_color = data$config$st$abe$bar_color,
        text = data$config$st$abe$text,
        label = data$config$st$abe$label
      )
  }

  if (data$config$st$cpb || data$config$st$cpb_mpi$active) {
    cpbs <- hl_global_cpb(data)
  }
  if (data$config$st$cpb) {
    new_state_plot <- new_state_plot + geom_cpb_internal(df.spatial_prep, cpbs$CPB, "CPB:", bsize = data$config$base_size)
  }
  if (data$config$st$cpb_mpi$active) {
    if (is.na(data$config$st$cpb_mpi$tile_size)) {
      logwarn("CPB_MPI is active and st$cpb_mpi$tile_size is NULL")
    }
    if (is.na(data$config$st$cpb_mpi$bandwidth)) {
      logwarn("CPB_MPI is active and st$cpb_mpi$bandwidth is NULL")
    }
    tile_size <- data$config$st$cpb_mpi$tile_size
    bandwidth <- data$config$st$cpb_mpi$bandwidth
    cpbmpit <- cpbs$CPB + cpbs$NMPI * (tile_size * tile_size * 8) / bandwidth / 1000000

    new_state_plot <- new_state_plot + geom_cpb_internal(df.spatial_prep, cpbs$CPBMPI, "CPB-MPI:", bsize = data$config$base_size)

    if (data$config$st$cpb_mpi$theoretical) {
      new_state_plot <- new_state_plot + geom_cpb_internal(df.spatial_prep, cpbmpit, "CPB-MPI*:", bsize = data$config$base_size)
    }
  }

  return(new_state_plot)
}
