# Set options for environment
options(scipen = 999) # no scientific notation

# load libraries
library(shiny)
library(dplyr)
library(shinyalert)
library(DT)
library(plotly)
library(DBI)
library(RPostgres)
library(dotenv)

# load analytical R code
source("./R/stature_association.r", local = TRUE)
source("./R/stature_estimation.r", local = TRUE)

# Reusable error dialog
show_error <- function(text) {
    shinyalert(
        title = "ERROR!", text = text, type = "error",
        closeOnClickOutside = TRUE, showConfirmButton = TRUE, confirmButtonText = "Dismiss"
    )
}

shinyServer(function(input, output, session) {
    source("./server/reference_s.r", local = TRUE)
    source("./server/stature_estimation_s.r", local = TRUE)
    source("./server/stature_association_s.r", local = TRUE)
})
