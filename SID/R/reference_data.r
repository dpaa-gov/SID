# Read a fresh reference snapshot for each session, with one query per bone.
load_reference_data <- function(conn, read_query = DBI::dbGetQuery) {
    stature_groups <- unique(na.omit(read_query(conn, paste(
        "SELECT DISTINCT i.collection || ' ' || i.ancestry || ' ' || i.sex AS group_label,",
        "i.collection, i.ancestry, i.sex FROM osteometry.individuals i",
        "INNER JOIN osteometry.collections c ON i.collection = c.collection",
        "WHERE c.stature_method = TRUE AND i.stature_method = TRUE",
        "ORDER BY i.collection, i.ancestry, i.sex"
    ))))
    measurements <- read_query(conn, paste(
        "SELECT ards, bone, full_name, stature_method FROM osteometry.measurements",
        "ORDER BY bone, ards"
    ))
    columns <- c("ards", "bone", "full_name")
    se_measurements <- measurements[measurements$stature_method %in% TRUE, columns, drop = FALSE]
    rownames(se_measurements) <- NULL
    se_bones <- unique(se_measurements$bone)
    as_measurements <- measurements[measurements$bone %in% se_bones, columns, drop = FALSE]
    rownames(as_measurements) <- NULL
    as_bones <- unique(as_measurements$bone)
    measurement_tooltips <- setNames(
        c(se_measurements$full_name, as_measurements$full_name),
        tolower(c(se_measurements$ards, as_measurements$ards))
    )
    measurement_tooltips <- measurement_tooltips[!duplicated(names(measurement_tooltips))]

    group_rows <- lapply(seq_len(nrow(stature_groups)), function(i) list())
    for (bone in as_bones) {
        if (nrow(stature_groups) == 0) break
        bone_meas <- as_measurements[as_measurements$bone == bone, "ards"]
        if (length(bone_meas) == 0) next
        # PostgreSQL folded the original unquoted measurement identifiers to lower case.
        table_name <- DBI::dbQuoteIdentifier(conn, DBI::Id(schema = "osteometry", table = gsub(" ", "_", tolower(bone))))
        meas_cols <- paste(paste0("b.", DBI::dbQuoteIdentifier(conn, tolower(bone_meas))), collapse = ", ")
        query <- paste0(
            "SELECT i.collection, i.ancestry, i.sex, i.accession, b.side, $1::text AS element, i.stature, ", meas_cols,
            " FROM ", table_name, " b",
            " INNER JOIN osteometry.individuals i ON b.accession = i.accession",
            " INNER JOIN osteometry.collections c ON c.collection = i.collection",
            " WHERE i.stature_method = TRUE AND c.stature_method = TRUE"
        )
        bone_data <- tryCatch(
            read_query(conn, query, params = list(bone)),
            error = function(e) {
                message(paste("Warning: Could not load", bone, "reference data -", e$message))
                NULL
            }
        )
        if (is.null(bone_data) || nrow(bone_data) == 0) next
        data_columns <- c("accession", "side", "element", "stature", tolower(bone_meas))
        for (i in seq_len(nrow(stature_groups))) {
            group <- stature_groups[i, ]
            rows <- which(bone_data$collection == group$collection &
                          bone_data$ancestry == group$ancestry & bone_data$sex == group$sex)
            if (length(rows) == 0) next
            data <- bone_data[rows, data_columns, drop = FALSE]
            rownames(data) <- NULL
            group_rows[[i]][[bone]] <- data
        }
    }
    reference_data <- list()
    for (i in seq_len(nrow(stature_groups))) {
        # Keep the old per-group column layout, including empty groups.
        reference_data[[stature_groups$group_label[i]]] <- if (length(group_rows[[i]])) {
            dplyr::bind_rows(group_rows[[i]])
        } else data.frame()
    }
    list(stature_groups = stature_groups, se_measurements = se_measurements,
         se_bones = se_bones, as_measurements = as_measurements, as_bones = as_bones,
         measurement_tooltips = measurement_tooltips, reference_data = reference_data)
}
