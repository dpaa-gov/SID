stature_association_ui <- tabPanel("Stature Association",
    icon = icon("chart-line", lib = "font-awesome"),
    sidebarLayout(
        sidebarPanel(
            tags$div(class = "sidebar-section-label", "REFERENCE"),
            fluidRow(
                column(
                    12,
                    selectizeInput(inputId = "reference_select_as", label = NULL, choices = NULL, multiple = TRUE)
                )
            ),
            tags$div(class = "sidebar-section-label", "ELEMENT"),
            fluidRow(
                column(
                    12,
                    selectInput(inputId = "bone_as", label = NULL, choices = NULL)
                )
            ),
            tags$div(class = "sidebar-section-label", "SIDE"),
            fluidRow(
                column(
                    12,
                    radioButtons(
                        inputId = "side_as", label = NULL, inline = TRUE,
                        choices = c("\u2190 left" = "left", "right \u2192" = "right"), selected = "left"
                    )
                )
            ),
            tags$div(class = "sidebar-section-label", "SETTINGS"),
            fluidRow(
                column(
                    12,
                    radioButtons(inputId = "prediction_interval_as", label = "Prediction Interval", inline = TRUE, choices = c("90%", "95%", "99%"), selected = "95%")
                ),
                column(
                    12,
                    radioButtons(inputId = "metric_as", label = "Stature Metric", inline = TRUE, choices = c("Inches", "Centimeters"), selected = "Inches")
                )
            ),
            tags$div(class = "sidebar-section-label", "KNOWN STATURE"),
            fluidRow(
                column(
                    12,
                    numericInput(inputId = "known_stature_as", label = NULL, value = "", min = 0, max = 999, step = 0.01)
                )
            ),
            tags$div(class = "sidebar-section-label", "MEASUREMENTS"),
            fluidRow(
                column(
                    12,
                    uiOutput("measurements_as")
                )
            ),
            hr(),
            fluidRow(
                column(
                    12,
                    actionButton("stature_associate_as", "Associate", icon = icon("gears"))
                )
            ),
            width = 3
        ),
        mainPanel(
            conditionalPanel(
                condition = "output.show_results_as",
                tags$div(
                    style = "margin-bottom: 10px; font-style: italic; color: #888;",
                    textOutput("groups_used_as")
                ),
                tags$div(
                    style = "border: 1px solid #ccc; padding: 15px; border-radius: 4px;",
                    tags$div(class = "main-section-label", "Plot"),
                    plotly::plotlyOutput("plotly_as")
                ),
                br(),
                tags$div(
                    style = "border: 1px solid #ccc; padding: 15px; border-radius: 4px;",
                    tags$div(class = "main-section-label", "Results"),
                    tableOutput("table_as")
                )
            ),
            width = 9
        )
    )
)
