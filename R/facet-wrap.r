FacetWrap <- proto(Facet, {
  new <- function(., facets, nrow = NULL, ncol = NULL, scales = "fixed", as.table = TRUE) {
    scales <- match.arg(scales, c("fixed", "free_x", "free_y", "free"))
    free <- list(
      x = any(scales %in% c("free_x", "free")),
      y = any(scales %in% c("free_y", "free"))
    )
    
    .$proto(
      facets = as.quoted(facets), free = free, 
      scales = NULL, as.table = as.table,
      ncol = ncol, nrow = nrow
    )
  }
  
  conditionals <- function(.) {
    names(.$facets)
  }
  
  # Data shape
  
  initialise <- function(., data) {
    vars <- llply(data, function(df) {
      as.data.frame(eval.quoted(.$facets, df))
    })
    labels <- unique(do.call(rbind, vars))
    labels <- labels[do.call("order", labels), , drop = FALSE]
    n <- nrow(labels)
    
    .$shape <- matrix(NA, 1, n)
    attr(.$shape, "split_labels") <- labels
  }
  
  stamp_data <- function(., data) {
    data <- add_missing_levels(data, .$conditionals())
    lapply(data, function(df) {
      data.matrix <- dlply(add_group(df), .$facets, .drop = FALSE)
      data.matrix <- as.list(data.matrix)
      dim(data.matrix) <- c(1, length(data.matrix))
      data.matrix
    })
  }
  
  # Create grobs for each component of the panel guides
  add_guides <- function(., data, panels_grob, coord, theme) {
    aspect_ratio <- theme$aspect.ratio
    if (is.null(aspect_ratio)) aspect_ratio <- 1
    
    n <- length(.$scales$x)

    axes_h <- matrix(list(), nrow = 1, ncol = n)
    axes_v <- matrix(list(), nrow = 1, ncol = n)
    panels <- matrix(list(), nrow = 1, ncol = n)

    for (i in seq_len(n)) {
      scales <- list(
        x = .$scales$x[[i]]$clone(), 
        y = .$scales$y[[i]]$clone()
      ) 
      details <- coord$compute_ranges(scales)
      axes_h[[1, i]] <- coord$guide_axis_h(details, theme)
      axes_v[[1, i]] <- coord$guide_axis_v(details, theme)

      fg <- coord$guide_foreground(details, theme)
      bg <- coord$guide_background(details, theme)
      name <- paste("panel", i, sep = "_")
      panels[[1,i]] <- ggname(name, grobTree(bg, panels_grob[[1, i]], fg))
    }
    
    # Arrange 1d structure into a grid -------
    if (is.null(.$ncol) && is.null(.$nrow)) {
      ncol <- ceiling(sqrt(n))
      nrow <- ceiling(n / ncol)
    } else if (is.null(.$ncol)) {
      nrow <- .$nrow
      ncol <- ceiling(n / nrow)
    } else if (is.null(.$nrow)) {
      ncol <- .$ncol
      nrow <- ceiling(n / ncol)
    }
    stopifnot(nrow * ncol >= n)

    # Create a grid of interwoven strips and panels
    panelsGrid <- grobGrid(
      "panel", panels, nrow = nrow, ncol = ncol,
      heights = 1 * aspect_ratio, widths = 1,
      as.table = .$as.table
    )

    strips <- .$labels_default(.$shape, theme)
    strips_height <- max(do.call("unit.c", llply(strips, grobHeight)))
    stripsGrid <- grobGrid(
      "strip", strips, nrow = nrow, ncol = ncol,
      heights = convertHeight(strips_height, "cm"),
      widths = 1,
      as.table = .$as.table
    )
    
    axis_widths <- max(do.call("unit.c", llply(axes_v, grobWidth)))
    axis_widths <- convertWidth(axis_widths, "cm")
    if (.$free$y) {
      axesvGrid <- grobGrid(
        "axis_v", axes_v, nrow = nrow, ncol = ncol, 
        widths = axis_widths, 
        as.table = .$as.table
      )
    } else { 
      # When scales are not free, there is only really one scale, and this
      # should be shown only in the first column
      axesvGrid <- grobGrid(
        "axis_v", rep(axes_v[1], nrow), nrow = nrow, ncol = 1,
        widths = axis_widths[1], 
        as.table = .$as.table)
      if (ncol > 1) {
        axesvGrid <- cbind(axesvGrid, 
          spacer(nrow, ncol - 1, unit(0, "cm"), unit(1, "null")))
        
      }
    }
    
    axis_heights <- max(do.call("unit.c", llply(axes_h, grobHeight)))
    axis_heights <- convertHeight(axis_heights, "cm")
    if (.$free$x) {
      axeshGrid <- grobGrid(
        "axis_h", axes_h, nrow = nrow, ncol = ncol, 
        heights = axis_heights, 
        as.table = .$as.table
      )
    } else {
      grobs <- c(
        rep(list(nullGrob()), nrow * (ncol - 1)), 
        rep(axes_h[1], ncol)
      )
      axeshGrid <- grobGrid(
        "axis_h", grobs, nrow = nrow, ncol = ncol,
        heights = unit.c(unit(rep(0, nrow - 1), "cm"), axis_heights[1]), 
        as.table = .$as.table)
    }

    gap <- spacer(ncol, nrow, 0.5, 0.5)
    fill <- spacer(ncol, nrow, 1, 1, "null")
    all <- rweave(
      cweave(fill,      stripsGrid, fill),
      cweave(axesvGrid, panelsGrid, fill),
      cweave(fill,      axeshGrid,  fill),
      cweave(fill,      fill,       gap)
    )    
    
    all
  }
  
  labels_default <- function(., gm, theme) {
    labels_df <- attr(gm, "split_labels")
    labels_df[] <- llply(labels_df, format, justify = "none")
    labels <- apply(labels_df, 1, paste, collapse=", ")

    llply(labels, ggstrip, theme = theme)
  }
  
  # Position scales ----------------------------------------------------------
  
  position_train <- function(., data, scales) {
    fr <- .$free
    if (is.null(.$scales$x) && scales$has_scale("x")) {
      .$scales$x <- scales_list(scales$get_scales("x"), length(.$shape), fr$x)
    }
    if (is.null(.$scales$y) && scales$has_scale("y")) {
      .$scales$y <- scales_list(scales$get_scales("y"), length(.$shape), fr$y)
    }

    lapply(data, function(l) {
      for(i in seq_along(.$scales$x)) {
        .$scales$x[[i]]$train_df(l[[1, i]], fr$x)
      }
      for(i in seq_along(.$scales$y)) {
        .$scales$y[[i]]$train_df(l[[1, i]], fr$y)
      }
    })
  }
  
  position_map <- function(., data, scales) {
    lapply(data, function(l) {
      for(i in seq_along(.$scales$x)) {
        l[1, i] <- lapply(l[1, i], function(old) {
          new <- .$scales$x[[i]]$map_df(old)
          if (!is.null(.$scales$y[[i]])) {
            new <- cbind(new, .$scales$y[[i]]$map_df(old))
          }
          
          
          cunion(new, old)
        }) 
      }
      l
    })
  }
  
  make_grobs <- function(., data, layers, coord) {
    lapply(seq_along(data), function(i) {
      layer <- layers[[i]]
      layerd <- data[[i]]
      grobs <- matrix(list(), nrow = nrow(layerd), ncol = ncol(layerd))

      for(i in seq_along(.$scales$x)) {
        scales <- list(
          x = .$scales$x[[i]]$clone(), 
          y = .$scales$y[[i]]$clone()
        )
        details <- coord$compute_ranges(scales)
        grobs[[1, i]] <- layer$make_grob(layerd[[1, i]], details, coord)
      }
      grobs
    })
  }
  
  calc_statistics <- function(., data, layers) {
    lapply(seq_along(data), function(i) {
      layer <- layers[[i]]
      layerd <- data[[i]]
      grobs <- matrix(list(), nrow = nrow(layerd), ncol = ncol(layerd))

      for(i in seq_along(.$scales$x)) {
        scales <- list(
          x = .$scales$x[[i]], 
          y = .$scales$y[[i]]
        )
        grobs[[1, i]] <- layer$calc_statistic(layerd[[1, i]], scales)
      }
      grobs
    })
  }
  

  # Documentation ------------------------------------------------------------

  objname <- "wrap"
  desc <- "Wrap a 1d ribbon of panels into 2d."
  
  desc_params <- list(
    nrow = "number of rows",
    ncol = "number of colums", 
    facet = "formula specifying variables to facet by",
    scales = "should scales be fixed, free, or free in one dimension (\\code{free_x}, \\code{free_y}) "
  )

  
  
  examples <- function(.) {
    d <- ggplot(diamonds, aes(carat, price, fill = ..density..)) + 
      xlim(0, 2) + stat_binhex(na.rm = TRUE) + opts(aspect.ratio = 1)
    d + facet_wrap(~ color)
    d + facet_wrap(~ color, ncol = 1)
    d + facet_wrap(~ color, ncol = 4)
    d + facet_wrap(~ color, nrow = 1)
    d + facet_wrap(~ color, nrow = 3)
    
    # Using multiple variables continues to wrap the long ribbon of 
    # plots into 2d - the ribbon just gets longer
    # d + facet_wrap(~ color + cut)

    # You can choose to keep the scales constant across all panels
    # or vary the x scale, the y scale or both:
    p <- qplot(price, data = diamonds, geom = "histogram", binwidth = 1000)
    p + facet_wrap(~ color)
    p + facet_wrap(~ color, scales = "free_y")
    
    p <- qplot(displ, hwy, data = mpg)
    p + facet_wrap(~ cyl)
    p + facet_wrap(~ cyl, scales = "free") 
    
    # Add data that does not contain all levels of the faceting variables
    cyl6 <- subset(mpg, cyl == 6)
    p + geom_point(data = cyl6, colour = "red", size = 1) + 
      facet_wrap(~ cyl)
    p + geom_point(data = transform(cyl6, cyl = 7), colour = "red") + 
      facet_wrap(~ cyl)
    
  }
  
  pprint <- function(., newline=TRUE) {
    cat("facet_", .$objname, "(", paste(names(.$facets), collapse = ", "), ")", sep="")
    if (newline) cat("\n")
  }
  
})

