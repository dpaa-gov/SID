reference_data <- reactiveValues(df1 = data.frame())

observeEvent(TRUE, {
    reference_data$df1 <- read.csv(file = "./extdata/data.csv", header = TRUE, sep=",") #import refernce data
})