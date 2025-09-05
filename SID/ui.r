 library(shinyBS)

source("./ui/stature_estimation_ui.r", local=TRUE) 
source("./ui/stature_association_ui.r", local=TRUE)

shinyUI(
    navbarPage(theme = "css/flatly.min.css", windowTitle = "SID",
		tags$script(HTML(paste("var header = $('.navbar > .container-fluid');header.append('<div style=\"float:left\"><img src=\"SID.png\" alt=\"alt\" style=\"float:right; width:80px;padding-top:0px;\"></div><div style=\"float:right; padding-top:15px\">", 
			"<font color=\"#FFFFFF\"><strong>Version: ", "0.0.4","</strong></font>","</div>');console.log(header)", sep=""))
		),
        stature_estimation_ui,
        stature_association_ui
    ) #navbarPage
) #shinyUI