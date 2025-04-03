reference_data <- reactiveValues(df1 = data.frame())

observeEvent(TRUE, {
    reference_data$df1 <- read.csv(file = "./extdata/data.csv", header = TRUE, sep=",") #import refernce data
    #for our future database system
    #con <- dbConnect(odbc(), Driver = "SQL Server", Server = "mysqlhost", Database = "mydbname", UID = "myuser", PWD = rstudioapi::askForPassword("Database password"), Port = 1433)
})