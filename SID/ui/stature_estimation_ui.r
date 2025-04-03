stature_estimation_ui <- tabPanel("Stature Estimation",icon = icon("ruler-vertical", lib="font-awesome"),
    sidebarLayout(
        sidebarPanel(
            fluidRow(
                column(12,
                    shinyBS::bsTooltip("reference_select_se", "Defaults to left measurements", trigger = "hover", placement = "top"),
                    selectizeInput(inputId = "reference_select_se", label = "Reference", choices = c("DPAA Black Males", "DPAA White Males", "Trotter Black Males", "Trotter White Males", "CMNH White Males", "CMNH Black Males", "SI-Terry White Males", "SI-Terry Black Males", "UT White Males", "UT Black Males"), multiple = TRUE, selected = "Trotter White Males"),
                ),
                column(12,
                    radioButtons(inputId = "prediction_interval_se", label = "Prediction Interval", inline=TRUE, choices = c("90%", "95%", "99%"), selected = "95%")
                ),
                column(12,
                    radioButtons(inputId = "metric_se", label = "Stature Metric", inline=TRUE, choices = c("Inches", "Centimeters"), selected = "Inches")
                ),
                column(12,
                    shinyBS::bsTooltip("Hum_01_se", "Maximum Length of the Humerus: The distance from the most superior point on the head of the humerus to the most inferior point on the trochlea (Moore-Jansen et al. 1994, #40; Langley et al. 2016:74, #45)", trigger = "hover"),
                    numericInput("Hum_01_se", label = "Hum_01", value = "", min=0,max=999,step=0.01)
                ),
                column(12,
                    shinyBS::bsTooltip("Uln_01_se", "Maximum Length of the Ulna: The distance between the most proximal point on the olecranon and the most distal point on the styloid process (Moore-Jansen et al. 1994, #48; Langley et al. 2016:75-76, #54)", trigger = "hover"),
                    numericInput("Uln_01_se", label = "Uln_01", value = "", min=0,max=999,step=0.01)
                ),
                column(12,
                    shinyBS::bsTooltip("Rad_01_se", "Maximum Length of the Radius: The distance from the most proximally positioned point on the head of the radius to the tip of the styloid process without regard to the long axis of the bone (Moore-Jansen et al. 1994, #45; Langley et al. 2016:75, #50)", trigger = "hover"),
                    numericInput("Rad_01_se", label = "Rad_01", value = "", min=0,max=999,step=0.01)
                ),
                column(12,
                    shinyBS::bsTooltip("Fem_01_se", "Maximum Length of the Femur: The distance from the most proximal point on the head of the femur to the most distal point on the medial or lateral femoral condyle (Moore-Jansen et al. 1994, #60; Langley et al. 2016:78, #75)", trigger = "hover"),
                    numericInput("Fem_01_se", label = "Fem_01", value = "", min=0,max=999,step=0.01)
                ),
                column(12,
                    shinyBS::bsTooltip("Fem_02_se", "Bicondylar Length of the Femur: The distance from the most proximal point on the head of the femur to a plane drawn between the inferior surfaces of the distal condyles (Moore-Jansen et al. 1994, #61; Langley et al. 2016:78, #76)", trigger = "hover"),
                    numericInput("Fem_02_se", label = "Fem_02", value = "", min=0,max=999,step=0.01)
                ),
                column(12,
                    shinyBS::bsTooltip("Tib_01_se", "Length of the Tibia: The distance from the superior articular surface of the lateral condyle of the tibia to the tip of the medial malleolus (Moore-Jansen et al. 1994, #69; Langley et al. 2016:81, #86)", trigger = "hover"),
                    numericInput("Tib_01_se", label = "Tib_01", value = "", min=0,max=999,step=0.01)
                ),
                column(12,
                    shinyBS::bsTooltip("Fib_01_se", "Maximum Length of the Fibula: The maximum distance between the most superior point on the fibular head and the most inferior point on the lateral malleolus (Moore-Jansen et al. 1994, #75; Langley et al. 2016:82, #92)", trigger = "hover"),
                    numericInput("Fib_01_se", label = "Fib_01", value = "", min=0,max=999,step=0.01)
                ),
                column(6,
                    textInput(inputId = 'case_id_se', label = 'Case ID', value = '2024-123')
                ),
                column(6,
                    textInput(inputId = 'analyst_se', label = 'Analyst', value = 'Trotter')
                ),
                column(6,
                    downloadButton("save_results_se","Save ", icon = icon("floppy-disk"))
                ),
                column(6,
                    actionButton("stature_estimate_se","Estimate", icon=icon("gears"))
                )
            ),
            tags$style(type = "text/css", "#stature_estimate_se { width:100%; font-size:100%; background-color:#126a8f }"),
            tags$style(type = "text/css", "#save_results_se { width:100%; font-size:100%; background-color:#126a8f }"),
            width=2
        ), #sidebarPanel
        mainPanel(
            plotOutput('ggplot_se'),
            br(),
            DT::dataTableOutput('table_se'),
            tags$style(HTML('table.dataTable tr.selected td, table.dataTable tr.selected {box-shadow: inset 0 0 0 9999px #126a8f !important;}'))
        ) #mainPanel
    )#sidebarLayout
)