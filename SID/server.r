#Set options for environment
options(scipen = 999) #no scientific notation
options(stringsAsFactors = FALSE) #no strings as factors
options(warn = -1) #disables warnings

#load libraries
library(shiny)
library(ggplot2)
library(dplyr)
library(shinyalert)
library(shinyBS)
library(DT)
library(gridExtra)
library(ggpubr)
#library(odbc) for the future database

#load analytical R code
source("./R/stature_association.r", local=TRUE) 
source("./R/stature_estimation.r", local=TRUE) 

shinyServer(function(input, output, session){
    SID_Version <- "0.0.3"
    source("./server/reference_s.r", local=TRUE) 
    source("./server/stature_estimation_s.r", local=TRUE) 
    source("./server/stature_association_s.r", local=TRUE) 
})