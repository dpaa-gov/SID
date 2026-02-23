# Results visibility flag — hidden until Estimate is pressed
results_visible_se <- reactiveVal(FALSE)
output$show_results_se <- reactive({
    results_visible_se()
})
outputOptions(output, "show_results_se", suspendWhenHidden = FALSE)

# Store results in a reactiveVal so the plot observer can access them
results_se <- reactiveVal(NULL)
groups_per_model_se <- reactiveVal(list())

# Populate reference group selector on startup
observe({
    default_se <- if ("Trotter white male" %in% stature_groups$group_label) "Trotter white male" else stature_groups$group_label[1]
    updateSelectizeInput(session, "reference_select_se",
        choices = stature_groups$group_label,
        selected = default_se
    )
})

# Cascade: reference selection -> available measurements
observeEvent(input$reference_select_se,
    {
        if (is.null(input$reference_select_se) || length(input$reference_select_se) == 0) {
            output$measurements_se <- renderUI({
                tagList()
            })
            return()
        }

        # Combine reference data for selected groups
        combined <- do.call(dplyr::bind_rows, lapply(input$reference_select_se, function(g) reference_data[[g]]))

        # Filter se_measurements to only those with at least one non-NA value in the reference data
        available_meas <- se_measurements[sapply(se_measurements$ards, function(code) {
            col <- tolower(code)
            col %in% colnames(combined) && any(!is.na(combined[[col]]))
        }), ]

        output$measurements_se <- renderUI({
            inputs <- lapply(seq_len(nrow(available_meas)), function(i) {
                code <- available_meas$ards[i]
                input_id <- paste0(code, "_se")
                tooltip <- measurement_tooltips[[tolower(code)]]
                if (is.null(tooltip)) tooltip <- code
                numericInput(input_id, label = tags$span(code, `data-tooltip` = tooltip, style = "cursor: help;"), value = "", min = 0, max = 999, step = 0.01)
            })
            do.call(tagList, inputs)
        })
    },
    ignoreNULL = FALSE
)

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

    # Pre-aggregate each group's data ONCE (same as main pipeline)
    group_agg <- lapply(input$reference_select_se, function(g) {
        gd <- reference_data[[g]]
        gd <- gd[gd$side == input$side_se, ]
        if (nrow(gd) == 0) {
            return(NULL)
        }
        agg_cols <- intersect(c("stature", colnames(case_data_se)), colnames(gd))
        if (!"stature" %in% agg_cols) {
            return(NULL)
        }
        gd_wide <- gd[, c("accession", agg_cols), drop = FALSE]
        gd_wide %>%
            dplyr::group_by(accession) %>%
            dplyr::summarise(
                dplyr::across(dplyr::all_of(agg_cols), ~ dplyr::first(na.omit(.))),
                .groups = "drop"
            )
    })
    names(group_agg) <- input$reference_select_se

    # Per-model reference groups: just check columns on pre-aggregated data (fast)
    per_model_groups <- list()
    m_names <- colnames(case_data_se)
    model_idx <- 1
    for (i in seq_along(m_names)) {
        c_i <- combn(m_names, i)
        for (j in seq_len(ncol(c_i))) {
            meas_combo <- c_i[, j]
            check_cols <- c("stature", meas_combo)
            groups_for_model <- Filter(function(g) {
                gd_agg <- group_agg[[g]]
                if (is.null(gd_agg)) {
                    return(FALSE)
                }
                if (!all(check_cols %in% colnames(gd_agg))) {
                    return(FALSE)
                }
                nrow(na.omit(gd_agg[check_cols])) > 0
            }, input$reference_select_se)
            per_model_groups[[model_idx]] <- groups_for_model
            model_idx <- model_idx + 1
        }
    }
    groups_per_model_se(per_model_groups)

    if (sum(!is.na(reference_data_se$stature)) == 0) {
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
    results_se(stature_estimate(reference = reference_data_se, case = case_data_se, prediction_interval = prediction_interval_se, bootstrap = input$bootstrap_se))

    # Check if any models survived the minimum sample size requirement
    if (nrow(results_se()[[2]]) == 0) {
        show_error("Insufficient reference data: all models require at least 10 individuals")
        results_visible_se(FALSE)
        return(NULL)
    }

    results_visible_se(TRUE)

    # Data table output with pagination
    output$table_se <- DT::renderDataTable({
        DT::datatable(results_se()[[2]],
            selection = list(mode = "single", selected = which.min(results_se()[[2]]$PI)),
            options = list(dom = "tp", ordering = TRUE, order = list(0, "asc"), pageLength = 10),
            rownames = FALSE
        )
    })
})

# Reactively update reference groups used based on selected model row
output$groups_used_se <- renderText({
    grps_list <- groups_per_model_se()
    sel <- input$table_se_rows_selected
    if (length(grps_list) == 0 || is.null(sel)) {
        return("")
    }
    grps <- grps_list[[sel]]
    if (is.null(grps) || length(grps) == 0) {
        return("Reference groups used: none")
    }
    paste("Reference groups used:", paste(grps, collapse = ", "))
})

# Generate plotly on selected row from datatable — OUTSIDE the process observer
observeEvent(input$table_se_rows_selected, {
    req(results_se())
    sel <- input$table_se_rows_selected
    if (!is.numeric(sel)) {
        return()
    }

    output$plotly_se <- plotly::renderPlotly({
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
    })
})
