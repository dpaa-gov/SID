pdf_as <- reactiveValues(plot=NULL, table=NULL, params=NULL)

observeEvent(input$stature_associate_as, {
    if(input$bone_as == "humerus") {
        if(all(is.na(input$Hum_01_as), is.na(input$Hum_02_as), is.na(input$Hum_03_as), is.na(input$Hum_04_as), is.na(input$Hum_05_as), is.na(input$Hum_06_as), is.na(input$Hum_07_as), is.na(input$Hum_08_as), is.na(input$Hum_09_as))){
            shinyalert(title = "ERROR!", text="There was an error with the measurements",type = "error", closeOnClickOutside = TRUE, showConfirmButton = TRUE, confirmButtonText="Dismiss")
            return(NULL)
        }
        case_data_as <- data.frame(Hum_01 = input$Hum_01_as, Hum_02 = input$Hum_02_as, Hum_03 = input$Hum_03_as, Hum_04 = input$Hum_04_as, Hum_05 = input$Hum_05_as, Hum_06 = input$Hum_06_as, Hum_07 = input$Hum_07_as, Hum_08 = input$Hum_08_as, Hum_09 = input$Hum_09_as)
    } else if (input$bone_as == "ulna") {
        if(all(is.na(input$Uln_01_as), is.na(input$Uln_02_as), is.na(input$Uln_03_as), is.na(input$Uln_04_as), is.na(input$Uln_05_as), is.na(input$Uln_06_as), is.na(input$Uln_08_as), is.na(input$Uln_09_as), is.na(input$Uln_10_as))){
            shinyalert(title = "ERROR!", text="There was an error with the measurements",type = "error", closeOnClickOutside = TRUE, showConfirmButton = TRUE, confirmButtonText="Dismiss")
            return(NULL)
        }
        case_data_as <- data.frame(Uln_01 = input$Uln_01_as, Uln_02 = input$Uln_02_as, Uln_03 = input$Uln_03_as, Uln_04 = input$Uln_04_as, Uln_05 = input$Uln_05_as, Uln_06 = input$Uln_06_as, Uln_08 = input$Uln_08_as, Uln_09 = input$Uln_09_as, Uln_10 = input$Uln_10_as)
    } else if (input$bone_as == "Radius") {
        if(all(is.na(input$Rad_01_as), is.na(input$Rad_02_as), is.na(input$Rad_03_as), is.na(input$Rad_04_as), is.na(input$Rad_05_as), is.na(input$Rad_06_as), is.na(input$Rad_07_as), is.na(input$Rad_08_as), is.na(input$Rad_09_as), is.na(input$Rad_10_as))){
            shinyalert(title = "ERROR!", text="There was an error with the measurements",type = "error", closeOnClickOutside = TRUE, showConfirmButton = TRUE, confirmButtonText="Dismiss")
            return(NULL)
        }
        case_data_as <- data.frame(Rad_01 = input$Rad_01_as, Rad_02 = input$Rad_02_as, Rad_03 = input$Rad_03_as, Rad_04 = input$Rad_04_as, Rad_05 = input$Rad_05_as, Rad_06 = input$Rad_06_as, Rad_07 = input$Rad_07_as, Rad_08 = input$Rad_08_as, Rad_09 = input$Rad_09_as, Rad_10 = input$Rad_10_as)
    } else if (input$bone_as == "femur") {
        if(all(is.na(input$Fem_01_as), is.na(input$Fem_02_as), is.na(input$Fem_03_as), is.na(input$Fem_04_as), is.na(input$Fem_05_as), is.na(input$Fem_06_as), is.na(input$Fem_07_as), is.na(input$Fem_08_as), is.na(input$Fem_09_as), is.na(input$Fem_10_as), is.na(input$Fem_12_as), is.na(input$Fem_13_as), is.na(input$Fem_14_as), is.na(input$Fem_15_as), is.na(input$Fem_16_as), is.na(input$Fem_17_as))){
            shinyalert(title = "ERROR!", text="There was an error with the measurements",type = "error", closeOnClickOutside = TRUE, showConfirmButton = TRUE, confirmButtonText="Dismiss")
            return(NULL)
        }
        case_data_as <- data.frame(Fem_01 = input$Fem_01_as, Fem_02 = input$Fem_02_as, Fem_03 = input$Fem_03_as, Fem_04 = input$Fem_04_as, Fem_05 = input$Fem_05_as, Fem_06 = input$Fem_06_as, Fem_07 = input$Fem_07_as, Fem_08 = input$Fem_08_as, Fem_09 = input$Fem_09_as, Fem_10 = input$Fem_10_as, Fem_12 = input$Fem_12_as, Fem_13 = input$Fem_13_as, Fem_14 = input$Fem_14_as, Fem_15 = input$Fem_15_as, Fem_16 = input$Fem_16_as, Fem_17 = input$Fem_17_as)
    } else if (input$bone_as == "tibia") {
        if(all(is.na(input$Tib_01_as), is.na(input$Tib_02_as), is.na(input$Tib_03_as), is.na(input$Tib_04_as), is.na(input$Tib_05_as), is.na(input$Tib_07_as), is.na(input$Tib_08_as), is.na(input$Tib_10_as), is.na(input$Tib_11_as), is.na(input$Tib_12_as))){
            shinyalert(title = "ERROR!", text="There was an error with the measurements",type = "error", closeOnClickOutside = TRUE, showConfirmButton = TRUE, confirmButtonText="Dismiss")
            return(NULL)
        }
        case_data_as <- data.frame(Tib_01 = input$Tib_01_as, Tib_02 = input$Tib_02_as, Tib_03 = input$Tib_03_as, Tib_04 = input$Tib_04_as, Tib_05 = input$Tib_05_as, Tib_07 = input$Tib_07_as, Tib_08 = input$Tib_08_as, Tib_10 = input$Tib_10_as, Tib_10 = input$Tib_11_as, Tib_10 = input$Tib_12_as)
    } else if (input$bone_as == "fibula") {
        if(all(is.na(input$Fib_01_as), is.na(input$Fib_02_as), is.na(input$Fib_03_as), is.na(input$Fib_04_as), is.na(input$Fib_05_as))){
            shinyalert(title = "ERROR!", text="There was an error with the measurements",type = "error", closeOnClickOutside = TRUE, showConfirmButton = TRUE, confirmButtonText="Dismiss")
            return(NULL)
        }
        case_data_as <- data.frame(Fib_01 = input$Fib_01_as, Fib_02 = input$Fib_02_as, Fib_03 = input$Fib_03_as, Fib_04 = input$Fib_04_as, Fib_05 = input$Fib_05_as)
    }
    case_data_as <- case_data_as[, colSums(is.na(case_data_as)) == 0, drop=FALSE] #drop empty measurements
    colnames(case_data_as) <- tolower(colnames(case_data_as))

    if(input$bone_side_as == "right") {
        reference_data_as <- reference_data$right[c("DB", "stature", colnames(case_data_as))]
    } else {
        reference_data_as <- reference_data$left[c("DB", "stature", colnames(case_data_as))]
    }

    #filter by selected demographics
    reference_data_as <- filter(reference_data_as, DB %in% tolower(input$reference_select_as)) 

    #omit rows with NA
    reference_data_as <- na.omit(reference_data_as)

    if(nrow(reference_data_as) == 0 || is.na(input$known_stature_as)){
        shinyalert(title = "ERROR!", text="There was an input error",type = "error", closeOnClickOutside = TRUE, showConfirmButton = TRUE, confirmButtonText="Dismiss")
        return(NULL)
    }

    #convert reference stature to inches. Note: this requires all reference data to be stores as CM, which is standard for most datasets
    if(input$metric_as == "Inches"){
        reference_data_as$stature <- reference_data_as$stature / 2.54
    }

    #prepares parameters
    if(input$prediction_interval_as == "90%") {
        prediction_interval_as = 0.9
    } else if (input$prediction_interval_as == "95%") {
        prediction_interval_as = 0.95
    } else if (input$prediction_interval_as == "99%") {
        prediction_interval_as = 0.99
    }

    results_as <- stature_associate(reference_used = paste(unique(reference_data_as$DB), collapse = ', '), side = input$bone_side_as, bone = input$bone_as, known_stature = input$known_stature_as, reference = reference_data_as, case = case_data_as, prediction_interval = prediction_interval_as)

    #data table output
    output$table_as <- DT::renderDataTable({
        DT::datatable(results_as[[2]], selection = 'none', options = list(dom = 't', pageLength = 1), rownames = FALSE)
    })

    #generate table of results for pdf
    pdf_as$table <- ggtexttable(t(results_as[[2]]), cols = NULL, theme = ttheme("mBlue"))

    output$ggplot_as <- renderPlot({
        pdf_as$plot <- ggplot(results_as[[3]], aes(y=Measurements, x=Stature)) + geom_point(col = I("grey52"), size = 2) + labs(y = "Measurements", x = "Stature") + theme_bw()+ geom_line(aes(y = results_as[[1]][,2]), linetype = "dashed", color = "#ea6011") + geom_line(aes(y = results_as[[1]][,3]), linetype = "dashed", color = "#ea6011") + geom_smooth(method = "lm", color = "black", linetype = "dashed", formula = y ~ x) + geom_point(y = results_as[[2]]$value, x = input$known_stature_as, col = "#126a8f", size = 4)+ theme(axis.title.x = element_text(face = "bold", size=15), axis.title.y = element_text(face = "bold", size=15), axis.text.x = element_text(size = 13), axis.text.y = element_text(size = 13))
        pdf_as$plot
    })

    #generate table of parameters for pdf
    df_params_as <- cbind(data.frame(Version = SID_Version, Date = Sys.time(), Case_ID = input$case_id_as, Analyst = input$analyst_as, Prediction_Interval = input$prediction_interval_as, Stature_Metric = input$metric_as), case_data_as)
    pdf_as$params <- ggtexttable(t(df_params_as), theme = ttheme("mBlue"))

    output$save_results_as <- downloadHandler(
        filename = "report.pdf",
        content = function(file) {
            pdf(file, onefile = TRUE, width = 8.5, height = 11)
            grid.arrange(
                pdf_as$params,
                pdf_as$table,
                pdf_as$plot,
                top = "Stature Identification (SID)",
                layout_matrix = rbind(c(1,2),c(3))
            )
            dev.off()
        }
    )
})