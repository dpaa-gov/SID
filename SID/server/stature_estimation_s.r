# Results visibility flag — hidden until Estimate is pressed
results_visible_se <- reactiveVal(FALSE)
output$show_results_se <- reactive({
    results_visible_se()
})
outputOptions(output, "show_results_se", suspendWhenHidden = FALSE)

# Store results in a reactiveVal so the plot observer can access them
results_se <- reactiveVal(NULL)

# Populate reference group selector on startup
observe({
    default_se <- if ("Trotter white male" %in% stature_groups$group_label) "Trotter white male" else stature_groups$group_label[1]
    updateSelectizeInput(session, "reference_select_se",
        choices = stature_groups$group_label,
        selected = default_se
    )
})

# Render ALL stature estimation measurements (across all bones) on startup
observe({
    output$measurements_se <- renderUI({
        inputs <- lapply(seq_len(nrow(se_measurements)), function(i) {
            code <- se_measurements$ards[i]
            input_id <- paste0(code, "_se")
            tooltip <- measurement_tooltips[[tolower(code)]]
            if (is.null(tooltip)) tooltip <- code
            numericInput(input_id, label = tags$span(code, `data-tooltip` = tooltip, style = "cursor: help;"), value = "", min = 0, max = 999, step = 0.01)
        })
        do.call(tagList, inputs)
    })
})

# Process stature estimation
observeEvent(input$stature_estimate_se, {
    if (is.null(input$reference_select_se) || length(input$reference_select_se) == 0) {
        return()
    }
    if (is.null(input$side_se) || input$side_se == "") {
        return()
    }

    # Get all stature estimation measurement codes
    all_meas <- se_measurements$ards

    # Read input values
    case_values <- sapply(all_meas, function(code) {
        val <- input[[paste0(code, "_se")]]
        if (is.null(val) || is.na(val)) NA else val
    })

    if (all(is.na(case_values))) {
        show_error("Please enter at least one measurement")
        return(NULL)
    }

    # Build case data frame (only non-NA measurements)
    case_data_se <- as.data.frame(t(case_values))
    colnames(case_data_se) <- all_meas
    case_data_se <- case_data_se[, colSums(is.na(case_data_se)) == 0, drop = FALSE]
    colnames(case_data_se) <- tolower(colnames(case_data_se))

    if (ncol(case_data_se) == 0) {
        show_error("No valid measurements entered")
        return(NULL)
    }

    # Combine reference data for selected groups, filter by side
    combined <- do.call(dplyr::bind_rows, lapply(input$reference_select_se, function(g) reference_data[[g]]))
    combined <- combined[combined$side == input$side_se, ]

    if (nrow(combined) == 0) {
        show_error("No reference data available for this selection")
        return(NULL)
    }

    # Pivot to wide format: one row per accession with stature + all measurement columns
    meas_cols_available <- intersect(tolower(all_meas), colnames(combined))
    ref_wide <- combined[, c("accession", "stature", meas_cols_available), drop = FALSE]

    # Aggregate by accession (merge rows from different bones for same individual)
    ref_wide <- ref_wide %>%
        dplyr::group_by(accession) %>%
        dplyr::summarise(
            stature = dplyr::first(na.omit(stature)),
            dplyr::across(dplyr::all_of(meas_cols_available), ~ dplyr::first(na.omit(.))),
            .groups = "drop"
        )

    # Select only stature + case measurement columns
    ref_cols <- c("stature", colnames(case_data_se))
    ref_cols <- ref_cols[ref_cols %in% colnames(ref_wide)]
    reference_data_se <- as.data.frame(ref_wide[ref_cols])
    reference_data_se <- na.omit(reference_data_se)

    if (nrow(reference_data_se) == 0) {
        show_error("No reference data available for this selection")
        return(NULL)
    }

    # Convert stature to inches if needed
    if (input$metric_se == "Inches") {
        reference_data_se$stature <- reference_data_se$stature / 2.54
    }

    # Parse prediction interval
    prediction_interval_se <- switch(input$prediction_interval_se,
        "90%" = 0.9,
        "95%" = 0.95,
        "99%" = 0.99,
        0.95
    )

    # Run stature estimation and store in reactiveVal
    results_se(stature_estimate(reference = reference_data_se, case = case_data_se, prediction_interval = prediction_interval_se))
    results_visible_se(TRUE)

    # Data table output
    output$table_se <- DT::renderDataTable({
        DT::datatable(results_se()[[2]],
            selection = list(mode = "single", selected = which.min(results_se()[[2]]$PI)),
            options = list(dom = "t", ordering = TRUE, order = list(0, "asc")),
            rownames = FALSE
        )
    })
})

# Generate plotly on selected row from datatable — OUTSIDE the process observer
observeEvent(input$table_se_rows_selected, {
    req(results_se())
    output$plotly_se <- plotly::renderPlotly({
        if (is.numeric(input$table_se_rows_selected)) {
            sel <- input$table_se_rows_selected
            res <- results_se()
            ref_df <- res[[3]][[sel]]
            pi_df <- res[[1]][[sel]]
            stats <- res[[2]][sel, ]

            # Sort by Measurements for prediction interval lines
            ord <- order(ref_df$Measurements)
            ref_sorted <- ref_df[ord, ]
            pi_sorted <- pi_df[ord, ]

            p <- plotly::plot_ly() %>%
                plotly::add_markers(
                    data = ref_sorted, x = ~Measurements, y = ~Stature,
                    marker = list(color = "grey", size = 6),
                    hoverinfo = "text",
                    text = ~ paste("Measurement:", round(Measurements, 2), "<br>Stature:", round(Stature, 2))
                ) %>%
                plotly::add_lines(
                    x = ref_sorted$Measurements, y = pi_sorted[, 1],
                    line = list(color = "#d4a843", dash = "dash")
                ) %>%
                plotly::add_lines(
                    x = ref_sorted$Measurements, y = pi_sorted[, 2],
                    line = list(color = "black", dash = "dash")
                ) %>%
                plotly::add_lines(
                    x = ref_sorted$Measurements, y = pi_sorted[, 3],
                    line = list(color = "black", dash = "dash")
                ) %>%
                plotly::add_markers(
                    x = stats$value, y = stats$`point estimate`,
                    marker = list(color = "#d4a843", size = 12),
                    hoverinfo = "text",
                    text = paste("Measurement:", stats$value, "<br>Estimate:", stats$`point estimate`)
                ) %>%
                plotly::layout(
                    xaxis = list(title = list(text = "Measurements", font = list(size = 15))),
                    yaxis = list(title = list(text = "Stature", font = list(size = 15))),
                    showlegend = FALSE
                )
            p
        }
    })
})
