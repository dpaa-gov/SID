source("./ui/stature_estimation_ui.r", local = TRUE)
source("./ui/stature_association_ui.r", local = TRUE)

shinyUI(
    navbarPage(
        theme = "css/flatly.min.css", windowTitle = "SID",
        header = tags$head(
            tags$link(rel = "stylesheet", type = "text/css", href = "css/sid.css")
        ),
        tags$script(HTML(paste("var header = $('.navbar > .container-fluid');header.append('<div style=\"float:left\"><img src=\"SID.png\" alt=\"alt\" style=\"float:right; width:80px;padding-top:0px;\"></div><div style=\"float:right; padding-top:15px\">",
            "<font color=\"#d4a843\"><strong>Version: ", "0.1.0", "</strong></font>", "</div>');console.log(header)",
            sep = ""
        ))),
        stature_estimation_ui,
        stature_association_ui
    ) # navbarPage
) # shinyUI
