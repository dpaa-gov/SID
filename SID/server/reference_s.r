# Load current ARDS reference data for this session.
if (file.exists(".env")) {
    dotenv::load_dot_env(".env")
} else {
    message("No .env file found; using system environment variables.")
}

reference_snapshot <- (function() {
    db_host <- Sys.getenv("DB_HOST", unset = "host.docker.internal")
    db_port <- Sys.getenv("DB_PORT", unset = "5432")
    db_name <- Sys.getenv("DB_NAME", unset = "")
    db_user <- Sys.getenv("DB_USER", unset = "")
    db_pass <- Sys.getenv("DB_PASS", unset = "")

    if (db_port == "" || is.na(suppressWarnings(as.integer(db_port)))) {
        db_port <- "5432"
    }

    if (db_name == "" || db_user == "" || db_pass == "") {
        stop("Missing required database environment variables: DB_NAME, DB_USER, and/or DB_PASS")
    }

    pg_conn <- tryCatch(
        dbConnect(
            RPostgres::Postgres(),
            host = db_host,
            port = as.integer(db_port),
            dbname = db_name,
            user = db_user,
            password = db_pass
        ),
        error = function(e) {
            stop("Failed to connect to ARDS database: ", e$message)
        }
    )

    on.exit(DBI::dbDisconnect(pg_conn), add = TRUE)
    load_reference_data(pg_conn)
})()

stature_groups <- reference_snapshot$stature_groups
se_measurements <- reference_snapshot$se_measurements
se_bones <- reference_snapshot$se_bones
as_measurements <- reference_snapshot$as_measurements
as_bones <- reference_snapshot$as_bones
measurement_tooltips <- reference_snapshot$measurement_tooltips
reference_data <- do.call(shiny::reactiveValues, reference_snapshot$reference_data)
rm(reference_snapshot)
