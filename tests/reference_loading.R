# Run from the repository root: Rscript tests/reference_loading.R
source("SID/R/reference_data.r")

groups <- data.frame(
    group_label = c("A white male", "B black female", "Empty white male", NA),
    collection = c("A", "B", "Empty", "Missing"),
    ancestry = c("white", "black", "white", NA), sex = c("male", "female", "male", "male")
)
measurements <- data.frame(ards = c("Fem_01", "Fem_02", "Fib_01", "Tib_01"),
    bone = c("femur", "femur", "fibula", "tibia"), full_name = c("Length", "Width", "Length", "Length"),
    stature_method = c(TRUE, FALSE, FALSE, TRUE))
queries <- list()
query <- function(conn, statement, params = NULL) {
    queries[[length(queries)+1L]] <<- list(sql = statement, params = params)
    if (grepl("SELECT DISTINCT", statement, fixed = TRUE)) return(groups)
    if (grepl("FROM osteometry.measurements", statement, fixed = TRUE)) return(measurements)
    stopifnot(grepl("c.stature_method = TRUE", statement, fixed = TRUE),
              grepl("i.stature_method = TRUE", statement, fixed = TRUE))
    if (identical(params, list("femur"))) {
        return(data.frame(collection=c("A","A","B","Excluded"), ancestry=c("white","white","black","white"),
            sex=c("male","male","female","male"), accession=c(1L,2L,3L,4L), side=c("left","right","left","left"),
            element="femur", stature=c(170,180,160,190), fem_01=c(45,48,42,50), fem_02=c(NA,8,7,9)))
    }
    if (identical(params, list("tibia"))) {
        return(data.frame(collection="A", ancestry="white", sex="male", accession=1L, side="left",
            element="tibia", stature=170, tib_01=36))
    }
    stop("Unexpected query")
}
result <- load_reference_data(DBI::ANSI(), query)
stopifnot(length(queries) == 4L)
stopifnot(identical(result$stature_groups$group_label, c("A white male","B black female","Empty white male")))
stopifnot(identical(result$se_measurements$ards, c("Fem_01","Tib_01")))
stopifnot(identical(result$as_measurements$ards, c("Fem_01","Fem_02","Tib_01")))
stopifnot(identical(result$as_bones,c("femur","tibia")))
a <- result$reference_data[["A white male"]]
stopifnot(nrow(a)==3L, identical(a$element,c("femur","femur","tibia")))
stopifnot(identical(a$accession,c(1L,2L,1L)), identical(a$side,c("left","right","left")))
stopifnot(identical(a$fem_01,c(45,48,NA)), identical(a$tib_01,c(NA,NA,36)))
stopifnot(nrow(result$reference_data[["B black female"]])==1L)
stopifnot(identical(result$reference_data[["Empty white male"]],data.frame()))
stopifnot(identical(result$measurement_tooltips[["fem_02"]],"Width"))

# A fresh call must honor changed eligible groups, without a process-wide cache.
groups <- groups[groups$collection=="B",,drop=FALSE]
queries <- list()
changed <- load_reference_data(DBI::ANSI(),query)
stopifnot(identical(names(changed$reference_data),"B black female"),length(queries)==4L)

# No eligible groups means no bone queries or empty-data indexing errors.
groups <- groups[FALSE,,drop=FALSE]
queries <- list()
empty <- load_reference_data(DBI::ANSI(),query)
stopifnot(length(queries)==2L,length(empty$reference_data)==0L)

# An unavailable bone must not erase data from other bones.
groups <- data.frame(group_label="A white male",collection="A",ancestry="white",sex="male")
partial <- suppressMessages(load_reference_data(DBI::ANSI(),function(conn,statement,params=NULL) {
    if (identical(params,list("femur"))) stop("Bone table unavailable")
    query(conn,statement,params)
}))
stopifnot(nrow(partial$reference_data[["A white male"]])==1L,
          partial$reference_data[["A white male"]]$element=="tibia")
cat("Reference loading checks passed: query count, fresh flags, metadata, groups, sides, missing values, and partial failures.\n")
