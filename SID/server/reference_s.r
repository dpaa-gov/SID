# Connect to ARDS PostgreSQL and load reference metadata

if (file.exists(".env")) {
    dotenv::load_dot_env(".env")
} else {
    message("No .env file found; using system environment variables.")
}

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

# Reference groups (collection + ancestry + sex) for stature individuals
stature_groups <- unique(na.omit(dbGetQuery(
    conn = pg_conn,
    statement = "SELECT DISTINCT i.collection || ' ' || i.ancestry || ' ' || i.sex AS group_label,
        i.collection, i.ancestry, i.sex
        FROM osteometry.individuals i
        INNER JOIN osteometry.collections c ON i.collection = c.collection
        WHERE c.stature_method = TRUE
        AND i.stature_method = TRUE
        ORDER BY i.collection, i.ancestry, i.sex"
)))

# Stature Estimation measurements (stature_method = TRUE on measurements table)
se_measurements <- dbGetQuery(
    conn = pg_conn,
    statement = "SELECT ards, bone, full_name FROM osteometry.measurements
        WHERE stature_method = TRUE
        ORDER BY bone, ards"
)
se_bones <- unique(se_measurements$bone)

# Stature Association measurements — bones derived from stature_method flag
# Uses se_bones (stature_method = TRUE) for the bone list, but loads ALL measurements for those bones
as_measurements <- dbGetQuery(
    conn = pg_conn,
    statement = "SELECT ards, bone, full_name FROM osteometry.measurements
        ORDER BY bone, ards"
)
as_measurements <- as_measurements[as_measurements$bone %in% se_bones, ]
as_bones <- unique(as_measurements$bone)

# Tooltip lookup: ards code -> full_name (lowercase keys for matching)
measurement_tooltips <- setNames(
    c(se_measurements$full_name, as_measurements$full_name),
    tolower(c(se_measurements$ards, as_measurements$ards))
)
measurement_tooltips <- measurement_tooltips[!duplicated(names(measurement_tooltips))]

# Reactive storage for reference data (loaded per group)
reference_data <- reactiveValues()

# Load reference data for all groups at startup
for (i in seq_len(nrow(stature_groups))) {
    group <- stature_groups[i, ]
    label <- group$group_label

    all_bone_data <- data.frame()
    for (bone in as_bones) {
        # Get ALL measurement columns for this bone (association needs all)
        bone_meas <- as_measurements[as_measurements$bone == bone, "ards"]
        if (length(bone_meas) == 0) next

        table_name <- paste0("osteometry.", gsub(" ", "_", tolower(bone)))
        meas_cols <- paste(paste0("b.", bone_meas), collapse = ", ")

        query <- paste0(
            "SELECT i.accession, b.side, '", bone, "' AS element, i.stature, ", meas_cols,
            " FROM ", table_name, " b",
            " INNER JOIN osteometry.individuals i ON b.accession = i.accession",
            " WHERE i.stature_method = TRUE",
            " AND i.collection = $1 AND i.ancestry = $2 AND i.sex = $3"
        )

        tryCatch(
            {
                bone_data <- dbGetQuery(pg_conn, query, params = list(group$collection, group$ancestry, group$sex))
                if (nrow(bone_data) > 0) {
                    all_bone_data <- dplyr::bind_rows(all_bone_data, bone_data)
                }
            },
            error = function(e) {
                message(paste("Warning: Could not load", bone, "for group", label, "-", e$message))
            }
        )
    }

    reference_data[[label]] <- all_bone_data
}

dbDisconnect(pg_conn)
