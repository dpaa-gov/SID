#Set options for environment
SID_Version <- 0.02
options(scipen = 999) #no scientific notation
options(stringsAsFactors = FALSE) #no strings as factors
options(warn = -1) #disables warnings
options(shiny.host = "0.0.0.0")
options(shiny.port = 8180)

#load libraries
library(shiny)
library(ggplot2)
library(dplyr)
library(shinyalert)
library(shinyBS)
library(DT)
library(gridExtra)
library(ggpubr)

#load analytical R code
source("./R/stature_association.r", local=TRUE) 
source("./R/stature_estimation.r", local=TRUE) 

#launch app without browser
runApp(launch.browser = FALSE)