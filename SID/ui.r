source("./ui/stature_estimation_ui.r", local = TRUE)
source("./ui/stature_association_ui.r", local = TRUE)

# Read version from file
app_version <- trimws(readLines("VERSION", n = 1))

shinyUI(
    navbarPage(
        theme = "css/flatly.min.css", windowTitle = "SID",
        header = tags$head(
            tags$link(rel = "stylesheet", type = "text/css", href = "css/sid.css")
        ),
        title = tags$img(src = "SID.png", class = "navbar-logo"),
        tags$script(HTML(paste0(
            "var header = $('.navbar > .container-fluid');",
            "header.append('<span class=\"version-badge\">v ", app_version, "</span>');"
        ))),
        stature_estimation_ui,
        stature_association_ui
    ) # navbarPage
) # shinyUI
