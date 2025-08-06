reference_data <- reactiveValues(
    humerus = data.frame(), 
    radius = data.frame(), 
    ulna = data.frame(), 
    femur = data.frame(), 
    tibia = data.frame(), 
    fibula = data.frame()
)

observeEvent(TRUE, {
    dotenv::load_dot_env() #load database information
    pg_conn <- dbConnect( #connect to database
        RPostgres::Postgres(),
        dbname = Sys.getenv("DB_NAME"),
        host = Sys.getenv("DB_HOST"),
        port = Sys.getenv("DB_PORT"),
        user = Sys.getenv("DB_USER"),
        password = Sys.getenv("DB_PASS")
    )

    #SQL queries per bone. Note it uses the stature column to pull only individuals identified to be used in stature estimation/association
    res <- dbSendQuery(
    conn = pg_conn,
    statement = "SELECT f.*, i.collection, i.ancestry, i.sex, i.stature
        FROM osteometry.femur f
        JOIN osteometry.individuals i 
        ON f.accession = i.accession
        WHERE i.stature_method = TRUE"
    )
    reference_data$femur <- dbFetch(res)

    res <- dbSendQuery(
    conn = pg_conn,
    statement = "SELECT t.*, i.collection, i.ancestry, i.sex, i.stature
        FROM osteometry.tibia t
        JOIN osteometry.individuals i 
        ON t.accession = i.accession
        WHERE i.stature_method = TRUE"
    )
    reference_data$tibia <- dbFetch(res)

    res <- dbSendQuery(
    conn = pg_conn,
    statement = "SELECT fi.*, i.collection, i.ancestry, i.sex, i.stature
        FROM osteometry.fibula fi
        JOIN osteometry.individuals i 
        ON fi.accession = i.accession
        WHERE i.stature_method = TRUE"
    )
    reference_data$fibula <- dbFetch(res)

    res <- dbSendQuery(
    conn = pg_conn,
    statement = "SELECT h.*, i.collection, i.ancestry, i.sex, i.stature
        FROM osteometry.humerus h
        JOIN osteometry.individuals i 
        ON h.accession = i.accession
        WHERE i.stature_method = TRUE"
    )
    reference_data$humerus <- dbFetch(res)

    res <- dbSendQuery(
    conn = pg_conn,
    statement = "SELECT r.*, i.collection, i.ancestry, i.sex, i.stature
        FROM osteometry.radius r
        JOIN osteometry.individuals i 
        ON r.accession = i.accession
        WHERE i.stature_method = TRUE"
    )
    reference_data$radius <- dbFetch(res)

    res <- dbSendQuery(
    conn = pg_conn,
    statement = "SELECT u.*, i.collection, i.ancestry, i.sex, i.stature
        FROM osteometry.ulna u
        JOIN osteometry.individuals i 
        ON u.accession = i.accession
        WHERE i.stature_method = TRUE"
    )
    reference_data$ulna <- dbFetch(res)

    dbClearResult(res) #clear last results
    dbDisconnect(pg_conn) #disconnect from db
})
