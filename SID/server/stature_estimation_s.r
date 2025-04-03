pdf_se <- reactiveValues(plot=NULL, table=NULL, params=NULL)

observeEvent(input$stature_estimate_se, {
    #checks for measurement input errors
    if(all(is.na(input$Hum_01_se), is.na(input$Hum_01_se), is.na(input$Uln_01_se), is.na(input$Rad_01_se), is.na(input$Fem_01_se), is.na(input$Fem_02_se), is.na(input$Tib_01_se), is.na(input$Fib_01_se))){
        shinyalert(title = "ERROR!", text="There was an error with the measurements",type = "error", closeOnClickOutside = TRUE, showConfirmButton = TRUE, confirmButtonText="Dismiss")
        return(NULL)
    }

    #prepares case data
    case_data_se <- data.frame(Hum_01 = input$Hum_01_se, Uln_01 = input$Uln_01_se, Rad_01 = input$Rad_01_se, Fem_01 = input$Fem_01_se, Fem_02 = input$Fem_02_se, Tib_01 = input$Tib_01_se, Fib_01 = input$Fib_01_se)
    case_data_se <- case_data_se[, colSums(is.na(case_data_se)) == 0, drop=FALSE]

    #prepares reference data
    reference_data_se <- reference_data$df1[c("DB", "Stature", colnames(case_data_se))] #filter by column names
    reference_data_se <- filter(reference_data_se, DB %in% input$reference_select_se) #filter by selected demographics

    #prepares parameters
    if(input$prediction_interval_se == "90%") {
        prediction_interval_se = 0.9
    } else if (input$prediction_interval_se == "95%") {
        prediction_interval_se = 0.95
    } else if (input$prediction_interval_se == "99%") {
        prediction_interval_se = 0.99
    }

    #convert reference stature to inches. Note: this requires all reference data to be stores as CM, which is standard for most datasets
    if(input$metric_se == "Inches"){
        reference_data_se[,2] <- reference_data_se[,2] / 2.54
    }

    #stature estimation
    results_se <- stature_estimate(reference = reference_data_se, case = case_data_se, prediction_interval = prediction_interval_se)

    #data table output
    output$table_se <- DT::renderDataTable({
        DT::datatable(results_se[[2]], selection = list(mode="single", selected = which.min(results_se[[2]]$PI)), options = list(lengthMenu = c(1,5,10,15,20,25,30,40), pageLength = 10, order = list(0, 'asc')), rownames = FALSE)
    })

    #generate plot on selected row from datatable
    observeEvent(input$table_se_rows_selected, {
        output$ggplot_se <- renderPlot({
            if(is.numeric(input$table_se_rows_selected)) {
                pdf_se$plot <- ggplot(results_se[[3]][[input$table_se_rows_selected]], aes(x=Measurements, y=Stature)) + geom_point(col = I("grey52"), size = 2) + labs(x = "Measurements", y = "Stature") + theme_bw()+ geom_line(aes(y = results_se[[1]][[input$table_se_rows_selected]][,2]), linetype = "dashed", color = "#ea6011") + geom_line(aes(y = results_se[[1]][[input$table_se_rows_selected]][,3]), linetype = "dashed", color = "#ea6011") + geom_smooth(method = "lm", color = "black", linetype = "dashed", formula = y ~ x) + geom_point(y = results_se[[2]][input$table_se_rows_selected,4], x = results_se[[2]][input$table_se_rows_selected,3], col = "#126a8f", size = 4)+ theme(axis.title.x = element_text(face = "bold", size=15), axis.title.y = element_text(face = "bold", size=15), axis.text.x = element_text(size = 13), axis.text.y = element_text(size = 13))
                pdf_se$plot
            }
        })
        #generate table of results for pdf
        pdf_se$table <- ggtexttable(t(results_se[[2]][input$table_se_rows_selected,]), cols = NULL, theme = ttheme("mBlue"))

    })

    #generate table of parameters for pdf
    df_params_se <- data.frame(Version = SID_Version, Date = Sys.time(), Case_ID = input$case_id_se, Analyst = input$analyst_se, Reference_Data = paste(input$reference_select_se, collapse = ", "),Prediction_Interval = input$prediction_interval_se, Stature_Metric = input$metric_se, Hum_01 = input$Hum_01_se, Uln_01 = input$Uln_01_se, Rad_01 = input$Rad_01_se, Fem_01 = input$Fem_01_se, Fem_02 = input$Fem_02_se, Tib_01 = input$Tib_01_se, Fib_01 = input$Fib_01_se)
    pdf_se$params <- ggtexttable(t(df_params_se), theme = ttheme("mBlue"))

    output$save_results_se <- downloadHandler(
        filename = "report.pdf",
        content = function(file) {
            pdf(file, onefile = TRUE, width = 8.5, height = 11)
            grid.arrange(
                pdf_se$params,
                pdf_se$table,
                pdf_se$plot,
                top = "Stature Identification (SID)",
                layout_matrix = rbind(c(1,2),c(3))
            )
            dev.off()
        }
    )
})