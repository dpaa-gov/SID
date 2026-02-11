stature_estimation_ui <- tabPanel("Stature Estimation",
    icon = icon("ruler-vertical", lib = "font-awesome"),
    sidebarLayout(
        sidebarPanel(
            tags$div(class = "sidebar-section-label", "REFERENCE"),
            fluidRow(
                column(
                    12,
                    selectizeInput(inputId = "reference_select_se", label = NULL, choices = NULL, multiple = TRUE)
                )
            ),
            tags$div(class = "sidebar-section-label", "SIDE"),
            fluidRow(
                column(
                    12,
                    radioButtons(
                        inputId = "side_se", label = NULL, inline = TRUE,
                        choices = c("\u2190 left" = "left", "right \u2192" = "right"), selected = "left"
                    )
                )
            ),
            tags$div(class = "sidebar-section-label", "SETTINGS"),
            fluidRow(
                column(
                    12,
                    radioButtons(inputId = "prediction_interval_se", label = "Prediction Interval", inline = TRUE, choices = c("90%", "95%", "99%"), selected = "95%")
                ),
                column(
                    12,
                    radioButtons(inputId = "metric_se", label = "Stature Metric", inline = TRUE, choices = c("Inches", "Centimeters"), selected = "Inches")
                ),
                column(
                    12,
                    checkboxInput(inputId = "bootstrap_se", label = "Bootstrap (n < 100)", value = FALSE)
                )
            ),
            tags$div(class = "sidebar-section-label", "MEASUREMENTS"),
            fluidRow(
                column(
                    12,
                    uiOutput("measurements_se")
                )
            ),
            hr(),
            fluidRow(
                column(
                    12,
                    actionButton("stature_estimate_se", "Estimate", icon = icon("gears"))
                )
            ),
            width = 2
        ),
        mainPanel(
            conditionalPanel(
                condition = "output.show_results_se",
                tags$div(
                    style = "border: 1px solid #ccc; padding: 15px; border-radius: 4px;",
                    tags$div(class = "main-section-label", "Plot"),
                    plotly::plotlyOutput("plotly_se")
                ),
                br(),
                tags$div(
                    style = "border: 1px solid #ccc; padding: 15px; border-radius: 4px;",
                    tags$div(class = "main-section-label", "Results"),
                    DT::dataTableOutput("table_se"),
                    tags$style(HTML("
                        table.dataTable tbody tr.selected td,
                        table.dataTable tbody td.selected {
                            border-top-color: white !important;
                            box-shadow: inset 0 0 0 9999px #d4a843 !important;
                        }

                        table.dataTable tbody tr:active td {
                            background-color: #d4a843 !important;
                        }

                        :root {
                            --dt-row-selected: transparent !important;
                        }

                        table.dataTable tbody tr:hover, table.dataTable tbody tr:hover td {
                            background-color: rgba(212, 168, 67, 0.3) !important;
                        }
                    "))
                )
            ),
            width = 10
        )
    )
)
