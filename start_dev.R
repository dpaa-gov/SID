#!/usr/bin/env Rscript
# SID Local Development Server
# Runs the Shiny app without Docker
#
# Prerequisites:
#   - R with required packages (see README.md)
#   - .env file in SID/ with DB credentials
#
# Usage:
#   Rscript start_dev.R
#   # or from RStudio: source("start_dev.R")

cat("Starting SID in development mode...\n")

# Install missing R packages
required_packages <- c(
    "shiny", "dplyr", "shinyalert",
    "DT", "plotly", "DBI", "RPostgres", "dotenv"
)
missing <- required_packages[!sapply(required_packages, requireNamespace, quietly = TRUE)]
if (length(missing) > 0) {
    cat("Installing missing packages:", paste(missing, collapse = ", "), "\n")
    install.packages(missing)
}

cat("App will be available at http://127.0.0.1:4002\n\n")

shiny::runApp(
    appDir = "SID",
    port = 4002,
    host = "127.0.0.1",
    launch.browser = TRUE
)
