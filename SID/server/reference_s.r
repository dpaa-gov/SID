reference_data <- reactiveValues(
    left = data.frame(), 
    right = data.frame()
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
    femur <- dbFetch(res)

    res <- dbSendQuery(
    conn = pg_conn,
    statement = "SELECT t.*, i.collection, i.ancestry, i.sex, i.stature
        FROM osteometry.tibia t
        JOIN osteometry.individuals i 
        ON t.accession = i.accession
        WHERE i.stature_method = TRUE"
    )
    tibia <- dbFetch(res)

    res <- dbSendQuery(
    conn = pg_conn,
    statement = "SELECT fi.*, i.collection, i.ancestry, i.sex, i.stature
        FROM osteometry.fibula fi
        JOIN osteometry.individuals i 
        ON fi.accession = i.accession
        WHERE i.stature_method = TRUE"
    )
    fibula <- dbFetch(res)

    res <- dbSendQuery(
    conn = pg_conn,
    statement = "SELECT h.*, i.collection, i.ancestry, i.sex, i.stature
        FROM osteometry.humerus h
        JOIN osteometry.individuals i 
        ON h.accession = i.accession
        WHERE i.stature_method = TRUE"
    )
    humerus <- dbFetch(res)

    res <- dbSendQuery(
    conn = pg_conn,
    statement = "SELECT r.*, i.collection, i.ancestry, i.sex, i.stature
        FROM osteometry.radius r
        JOIN osteometry.individuals i 
        ON r.accession = i.accession
        WHERE i.stature_method = TRUE"
    )
    radius <- dbFetch(res)

    res <- dbSendQuery(
    conn = pg_conn,
    statement = "SELECT u.*, i.collection, i.ancestry, i.sex, i.stature
        FROM osteometry.ulna u
        JOIN osteometry.individuals i 
        ON u.accession = i.accession
        WHERE i.stature_method = TRUE"
    )
    ulna <- dbFetch(res)

    dbClearResult(res) #clear last results
    dbDisconnect(pg_conn) #disconnect from db

    #vector of bone names
    bones <- c("humerus", "ulna", "radius", "femur", "tibia", "fibula")

    #columns to drop (from all but the anchor bone)
    cols_to_remove <- c("collection", "ancestry", "sex", "stature", "bone", "side")

    #initialize empty lists to hold filtered data
    left_bones <- list()
    right_bones <- list()

    #filter and clean all bones
    for (bone in bones) {
        #filter to left and right
        bone_data <- get(bone)
        left  <- bone_data[bone_data$side == "left", ]
        right <- bone_data[bone_data$side == "right", ]

        #drop extra columns if not the anchor bone (e.g., humerus)
        if (bone != "humerus") {
            left  <- subset(left,  select = -c(collection, ancestry, sex, stature, bone, side))
            right <- subset(right, select = -c(collection, ancestry, sex, stature, bone, side))
        }

        #store in the lists
        left_bones[[bone]]  <- left
        right_bones[[bone]] <- right
    }

    #merge bones by "accession"
    left_reference  <- Reduce(function(x, y) merge(x, y, by = "accession"), left_bones)
    right_reference <- Reduce(function(x, y) merge(x, y, by = "accession"), right_bones)

    #add DB column (based on anchor bone's info: collection, ancestry, sex)
    left_reference$DB  <- tolower(paste(left_reference$collection, left_reference$ancestry, left_reference$sex))
    right_reference$DB <- tolower(paste(right_reference$collection, right_reference$ancestry, right_reference$sex))

    #move into reactiveValues
    reference_data$left <- left_reference
    reference_data$right <- right_reference
})
