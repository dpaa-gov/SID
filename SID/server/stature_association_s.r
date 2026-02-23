# Results visibility flag — hidden until Associate is pressed
results_visible_as <- reactiveVal(FALSE)
output$show_results_as <- reactive({
    results_visible_as()
})
outputOptions(output, "show_results_as", suspendWhenHidden = FALSE)

# Populate reference group selector on startup
observe({
    default_as <- if ("Trotter white male" %in% stature_groups$group_label) "Trotter white male" else stature_groups$group_label[1]
    updateSelectizeInput(session, "reference_select_as",
        choices = stature_groups$group_label,
        selected = default_as
    )
})

# Cascade: reference selection -> available bones (all bones for association)
observeEvent(input$reference_select_as,
    {
        if (is.null(input$reference_select_as) || length(input$reference_select_as) == 0) {
            return()
        }

        combined <- do.call(dplyr::bind_rows, lapply(input$reference_select_as, function(g) reference_data[[g]]))
        if (nrow(combined) == 0) {
            return()
        }

        available_bones <- intersect(as_bones, unique(combined$element))
        updateSelectInput(session, "bone_as", choices = available_bones)
    },
    ignoreNULL = FALSE
)

# Cascade: bone or reference selection -> render measurement inputs (side is static)
observeEvent(list(input$bone_as, input$reference_select_as), {
    if (is.null(input$bone_as) || input$bone_as == "") {
        return()
    }

    # Filter to measurements that have data in the reference for this bone
    combined <- do.call(dplyr::bind_rows, lapply(input$reference_select_as, function(g) reference_data[[g]]))
    bone_data <- combined[combined$element == input$bone_as, ]
    bone_meas <- as_measurements[as_measurements$bone == input$bone_as, ]

    # Only show measurements that have at least one non-NA value in the reference data
    available_meas <- bone_meas[sapply(bone_meas$ards, function(code) {
        col <- tolower(code)
        col %in% colnames(bone_data) && any(!is.na(bone_data[[col]]))
    }), ]

    output$measurements_as <- renderUI({
        inputs <- lapply(seq_len(nrow(available_meas)), function(i) {
            code <- available_meas$ards[i]
            input_id <- paste0(code, "_as")
            tooltip <- measurement_tooltips[[tolower(code)]]
            if (is.null(tooltip)) tooltip <- code
            numericInput(input_id, label = tags$span(code, `data-tooltip` = tooltip, style = "cursor: help;"), value = "", min = 0, max = 999, step = 0.01)
        })
        do.call(tagList, inputs)
    })
})

# Process stature association
observeEvent(input$stature_associate_as, {
    if (is.null(input$bone_as) || input$bone_as == "") {
        return()
    }
    if (is.null(input$side_as) || input$side_as == "") {
        return()
    }

    # Get ALL measurement codes for this bone
    bone_meas <- as_measurements[as_measurements$bone == input$bone_as, "ards"]

    # Read input values
    case_values <- sapply(bone_meas, function(code) {
        val <- input[[paste0(code, "_as")]]
        if (is.null(val) || is.na(val)) NA else val
    })

    if (all(is.na(case_values))) {
        show_error("Please enter at least one measurement")
        return(NULL)
    }

    # Build case data frame
    case_data_as <- as.data.frame(t(case_values))
    colnames(case_data_as) <- bone_meas
    case_data_as <- case_data_as[, colSums(is.na(case_data_as)) == 0, drop = FALSE]
    colnames(case_data_as) <- tolower(colnames(case_data_as))

    if (ncol(case_data_as) == 0) {
        show_error("No valid measurements entered")
        return(NULL)
    }

    if (is.na(input$known_stature_as)) {
        show_error("Please enter a known stature")
        return(NULL)
    }

    # Combine reference data for selected groups
    combined <- do.call(dplyr::bind_rows, lapply(input$reference_select_as, function(g) reference_data[[g]]))

    # Filter by bone and side
    ref_filtered <- combined[combined$element == input$bone_as & combined$side == input$side_as, ]
    ref_cols <- c("stature", colnames(case_data_as))
    ref_cols <- ref_cols[ref_cols %in% colnames(ref_filtered)]
    reference_data_as <- ref_filtered[ref_cols]
    reference_data_as <- na.omit(reference_data_as)

    # Track which groups actually contributed rows after full filtering
    groups_used_as_list <- Filter(function(g) {
        gd <- reference_data[[g]]
        gd_filtered <- gd[gd$element == input$bone_as & gd$side == input$side_as, ]
        if (nrow(gd_filtered) == 0) {
            return(FALSE)
        }
        gd_cols <- ref_cols[ref_cols %in% colnames(gd_filtered)]
        nrow(na.omit(gd_filtered[gd_cols])) > 0
    }, input$reference_select_as)

    if (nrow(reference_data_as) == 0) {
        show_error("No reference data available for this selection")
        return(NULL)
    }

    if (nrow(reference_data_as) < 10) {
        show_error("Insufficient reference data: at least 10 individuals required")
        return(NULL)
    }

    # Convert stature to inches if needed
    if (input$metric_as == "Inches") {
        reference_data_as$stature <- reference_data_as$stature / 2.54
    }

    # Parse prediction interval
    prediction_interval_as <- switch(input$prediction_interval_as,
        "90%" = 0.9,
        "95%" = 0.95,
        "99%" = 0.99,
        0.95
    )

    # Run stature association
    results_as <- stature_associate(
        known_stature = input$known_stature_as, reference = reference_data_as,
        case = case_data_as, prediction_interval = prediction_interval_as
    )
    results_visible_as(TRUE)

    # Display which reference groups contributed data
    output$groups_used_as <- renderText({
        paste("Reference groups used:", paste(groups_used_as_list, collapse = ", "))
    })

    # Table output
    output$table_as <- renderTable(
        results_as[[2]],
        striped = TRUE, bordered = TRUE, hover = TRUE, width = "100%"
    )

    # Plotly output
    output$plotly_as <- plotly::renderPlotly({
        ref_df <- results_as[[3]]
        pi_df <- results_as[[1]]
        stats <- results_as[[2]]

        # Sort by Stature for prediction interval lines
        ord <- order(ref_df$Stature)
        ref_sorted <- ref_df[ord, ]
        pi_sorted <- pi_df[ord, ]

        p <- plotly::plot_ly() %>%
            plotly::add_markers(
                data = ref_sorted, x = ~Stature, y = ~Measurements,
                marker = list(color = "grey", size = 6),
                hoverinfo = "text",
                text = ~ paste("Stature:", round(Stature, 2), "<br>Measurement:", round(Measurements, 2))
            ) %>%
            plotly::add_lines(
                x = ref_sorted$Stature, y = pi_sorted[, 1],
                line = list(color = "#d4a843", dash = "dash")
            ) %>%
            plotly::add_lines(
                x = ref_sorted$Stature, y = pi_sorted[, 2],
                line = list(color = "black", dash = "dash")
            ) %>%
            plotly::add_lines(
                x = ref_sorted$Stature, y = pi_sorted[, 3],
                line = list(color = "black", dash = "dash")
            ) %>%
            plotly::add_markers(
                x = input$known_stature_as, y = stats$value,
                marker = list(color = "#d4a843", size = 12),
                hoverinfo = "text",
                text = paste("Known Stature:", input$known_stature_as, "<br>Measurement:", stats$value)
            ) %>%
            plotly::layout(
                xaxis = list(title = list(text = "Stature", font = list(size = 15))),
                yaxis = list(title = list(text = "Measurements", font = list(size = 15))),
                showlegend = FALSE
            )
        p
    })
})
