# Records what the R/Shiny SID (0.1.0) gives for a few thousand made-up cases
# against ARDS, so the Julia SID can be checked against it (compare.jl).
# Run through capture.sh, which provides the R code and the database.
#
#   Rscript capture.R <directory with SID's R/ folder> <output.json> [cases]
#
# The analytical functions are SID's own, sourced unchanged. The steps that
# lived in the Shiny server (combining groups, the side filter, joining an
# individual's bones, the groups used, inches) are copied here line for line
# from server/stature_estimation_s.r and server/stature_association_s.r, with
# `input$...` replaced by arguments and `show_error` by returning the message.

suppressPackageStartupMessages({
    library(DBI)
    library(RPostgres)
    library(dplyr)
    library(jsonlite)
})
options(scipen = 999)

args <- commandArgs(trailingOnly = TRUE)
app_dir <- args[1]
out_file <- args[2]
n_cases <- if (length(args) >= 3) as.integer(args[3]) else 1500L

source(file.path(app_dir, "R", "reference_data.r"))
source(file.path(app_dir, "R", "stature_estimation.r"))
source(file.path(app_dir, "R", "stature_association.r"))

conn <- dbConnect(RPostgres::Postgres(),
    host = Sys.getenv("DB_HOST"), port = as.integer(Sys.getenv("DB_PORT", "5432")),
    dbname = Sys.getenv("DB_NAME"), user = Sys.getenv("DB_USER"), password = Sys.getenv("DB_PASS"))
snapshot <- load_reference_data(conn)
dbDisconnect(conn)
stature_groups <- snapshot$stature_groups
se_measurements <- snapshot$se_measurements
as_measurements <- snapshot$as_measurements
as_bones <- snapshot$as_bones
reference_data <- snapshot$reference_data

interval_of <- function(label) switch(label, "90%" = 0.9, "95%" = 0.95, "99%" = 0.99, 0.95)

# ---------- Stature estimation: server/stature_estimation_s.r ----------
run_estimation <- function(reference_select_se, side_se, values, prediction_interval_label, metric_se, bootstrap_se) {
    all_meas <- se_measurements$ards
    case_values <- sapply(all_meas, function(code) {
        val <- values[[code]]
        if (is.null(val) || is.na(val)) NA else val
    })
    if (all(is.na(case_values))) return(list(error = "Please enter at least one measurement"))
    case_data_se <- as.data.frame(t(case_values))
    colnames(case_data_se) <- all_meas
    case_data_se <- case_data_se[, colSums(is.na(case_data_se)) == 0, drop = FALSE]
    colnames(case_data_se) <- tolower(colnames(case_data_se))
    if (ncol(case_data_se) == 0) return(list(error = "No valid measurements entered"))

    combined <- do.call(dplyr::bind_rows, lapply(reference_select_se, function(g) reference_data[[g]]))
    combined <- combined[combined$side == side_se, ]
    if (nrow(combined) == 0) return(list(error = "No reference data available for this selection"))

    meas_cols_available <- intersect(tolower(all_meas), colnames(combined))
    ref_wide <- combined[, c("accession", "stature", meas_cols_available), drop = FALSE]
    ref_wide <- ref_wide %>%
        dplyr::group_by(accession) %>%
        dplyr::summarise(
            stature = dplyr::first(na.omit(stature)),
            dplyr::across(dplyr::all_of(meas_cols_available), ~ dplyr::first(na.omit(.))),
            .groups = "drop"
        )
    ref_cols <- c("stature", colnames(case_data_se))
    ref_cols <- ref_cols[ref_cols %in% colnames(ref_wide)]
    reference_data_se <- as.data.frame(ref_wide[ref_cols])

    group_agg <- lapply(reference_select_se, function(g) {
        gd <- reference_data[[g]]
        gd <- gd[gd$side == side_se, ]
        if (nrow(gd) == 0) return(NULL)
        agg_cols <- intersect(c("stature", colnames(case_data_se)), colnames(gd))
        if (!"stature" %in% agg_cols) return(NULL)
        gd_wide <- gd[, c("accession", agg_cols), drop = FALSE]
        gd_wide %>%
            dplyr::group_by(accession) %>%
            dplyr::summarise(dplyr::across(dplyr::all_of(agg_cols), ~ dplyr::first(na.omit(.))), .groups = "drop")
    })
    names(group_agg) <- reference_select_se

    per_model_groups <- list()
    m_names <- colnames(case_data_se)
    model_idx <- 1
    for (i in seq_along(m_names)) {
        c_i <- combn(m_names, i)
        for (j in seq_len(ncol(c_i))) {
            meas_combo <- c_i[, j]
            check_cols <- c("stature", meas_combo)
            combo_cols_avail <- check_cols[check_cols %in% colnames(reference_data_se)]
            if (length(combo_cols_avail) < length(check_cols) || nrow(na.omit(reference_data_se[combo_cols_avail])) < 10) next
            groups_for_model <- Filter(function(g) {
                gd_agg <- group_agg[[g]]
                if (is.null(gd_agg)) return(FALSE)
                if (!all(check_cols %in% colnames(gd_agg))) return(FALSE)
                nrow(na.omit(gd_agg[check_cols])) > 0
            }, reference_select_se)
            per_model_groups[[model_idx]] <- groups_for_model
            model_idx <- model_idx + 1
        }
    }

    if (sum(!is.na(reference_data_se$stature)) == 0) return(list(error = "No reference data available for this selection"))
    if (metric_se == "Inches") reference_data_se$stature <- reference_data_se$stature / 2.54
    prediction_interval_se <- interval_of(prediction_interval_label)

    results <- stature_estimate(reference = reference_data_se, case = case_data_se,
        prediction_interval = prediction_interval_se, bootstrap = bootstrap_se)
    if (nrow(results[[2]]) == 0) return(list(error = "Insufficient reference data: all models require at least 10 individuals"))

    sel <- which.min(results[[2]]$PI)
    list(table = results[[2]], groups = per_model_groups, selected = sel,
         plot = list(reference = results[[3]][[sel]], interval = as.data.frame(results[[1]][[sel]])))
}

# ---------- Stature association: server/stature_association_s.r ----------
run_association <- function(reference_select_as, bone_as, side_as, values, known_stature_as, prediction_interval_label, metric_as) {
    bone_meas <- as_measurements[as_measurements$bone == bone_as, "ards"]
    case_values <- sapply(bone_meas, function(code) {
        val <- values[[code]]
        if (is.null(val) || is.na(val)) NA else val
    })
    if (all(is.na(case_values))) return(list(error = "Please enter at least one measurement"))
    case_data_as <- as.data.frame(t(case_values))
    colnames(case_data_as) <- bone_meas
    case_data_as <- case_data_as[, colSums(is.na(case_data_as)) == 0, drop = FALSE]
    colnames(case_data_as) <- tolower(colnames(case_data_as))
    if (ncol(case_data_as) == 0) return(list(error = "No valid measurements entered"))
    if (is.na(known_stature_as)) return(list(error = "Please enter a known stature"))

    combined <- do.call(dplyr::bind_rows, lapply(reference_select_as, function(g) reference_data[[g]]))
    ref_filtered <- combined[combined$element == bone_as & combined$side == side_as, ]
    ref_cols <- c("stature", colnames(case_data_as))
    ref_cols <- ref_cols[ref_cols %in% colnames(ref_filtered)]
    reference_data_as <- ref_filtered[ref_cols]
    reference_data_as <- na.omit(reference_data_as)

    groups_used_as_list <- Filter(function(g) {
        gd <- reference_data[[g]]
        gd_filtered <- gd[gd$element == bone_as & gd$side == side_as, ]
        if (nrow(gd_filtered) == 0) return(FALSE)
        gd_cols <- ref_cols[ref_cols %in% colnames(gd_filtered)]
        nrow(na.omit(gd_filtered[gd_cols])) > 0
    }, reference_select_as)

    if (nrow(reference_data_as) == 0) return(list(error = "No reference data available for this selection"))
    if (nrow(reference_data_as) < 10) return(list(error = "Insufficient reference data: at least 10 individuals required"))
    if (metric_as == "Inches") reference_data_as$stature <- reference_data_as$stature / 2.54
    prediction_interval_as <- interval_of(prediction_interval_label)

    results <- stature_associate(known_stature = known_stature_as, reference = reference_data_as,
        case = case_data_as, prediction_interval = prediction_interval_as)
    list(table = results[[2]], groups = groups_used_as_list,
         plot = list(reference = results[[3]], interval = as.data.frame(results[[1]])))
}

# ---------- Made-up cases ----------
# Measurements are taken from a real reference individual, mostly moved by a
# few millimetres, so the cases look like specimens; a few are made extreme.

set.seed(20261005)
labels <- stature_groups$group_label

pick_groups <- function() {
    r <- runif(1)
    if (r < 0.3 && "Trotter white male" %in% labels) return("Trotter white male")
    if (r < 0.6) return(sample(labels, 1))
    if (r < 0.85) return(sample(labels, sample(2:4, 1)))
    labels
}

# A measurement as an analyst would type it: to a tenth of a millimetre
typed <- function(x) round(x + sample(c(0, 0, runif(1, -4, 4)), 1), 1)

with_side <- function(refs, side) {
    combined <- do.call(dplyr::bind_rows, lapply(refs, function(g) reference_data[[g]]))
    if (nrow(combined) == 0) return(combined)
    combined[combined$side == side, ]
}

# The measurement fields the page shows: those with data in the selected groups
shown <- function(refs, codes, bone = NULL) {
    combined <- do.call(dplyr::bind_rows, lapply(refs, function(g) reference_data[[g]]))
    if (!is.null(bone)) combined <- combined[combined$element == bone, ]
    codes[sapply(codes, function(code) tolower(code) %in% colnames(combined) && any(!is.na(combined[[tolower(code)]])))]
}

group_size <- sapply(labels, function(g) length(unique(reference_data[[g]]$accession)))
# groups small enough for bootstrap to apply, with enough individuals to fit
bootstrap_labels <- labels[group_size >= 10 & group_size < 100]

estimation_case <- function(bootstrap) {
    refs <- if (bootstrap) sample(bootstrap_labels, sample(1:2, 1)) else pick_groups()
    side <- sample(c("left", "right"), 1)
    codes <- shown(refs, se_measurements$ards)
    if (length(codes) == 0) return(NULL)
    rows <- with_side(refs, side)
    wanted <- sample(codes, sample(seq_along(codes), 1))
    values <- list()
    if (nrow(rows) > 0) {
        # one individual's bones joined, as the estimation joins them
        who <- sample(unique(rows$accession), 1)
        mine <- rows[rows$accession == who, ]
        for (code in wanted) {
            v <- mine[[tolower(code)]]
            v <- if (is.null(v)) NA else v[!is.na(v)]
            if (length(v)) values[[code]] <- typed(v[1])
        }
    }
    # a measurement the individual lacks is filled from the others, or made up
    for (code in setdiff(wanted, names(values))) {
        all_values <- unlist(lapply(refs, function(g) reference_data[[g]][[tolower(code)]]))
        all_values <- all_values[!is.na(all_values)]
        if (length(all_values)) values[[code]] <- typed(sample(all_values, 1))
    }
    if (runif(1) < 0.05 && length(values)) values[[names(values)[1]]] <- round(values[[1]] * runif(1, 0.5, 1.6), 1)
    list(kind = "estimation", references = refs, side = side, values = values,
         interval = sample(c("90%", "95%", "99%"), 1), unit = sample(c("Inches", "Centimeters"), 1),
         bootstrap = bootstrap)
}

association_case <- function() {
    refs <- pick_groups()
    combined <- do.call(dplyr::bind_rows, lapply(refs, function(g) reference_data[[g]]))
    bones <- intersect(as_bones, unique(combined$element))
    if (!length(bones)) return(NULL)
    bone <- sample(bones, 1)
    side <- sample(c("left", "right"), 1)
    codes <- shown(refs, as_measurements[as_measurements$bone == bone, "ards"], bone)
    if (!length(codes)) return(NULL)
    rows <- combined[combined$element == bone & combined$side == side, ]
    unit <- sample(c("Inches", "Centimeters"), 1)
    wanted <- sample(codes, sample(seq_len(min(length(codes), 6)), 1))
    values <- list()
    stature <- NA
    if (nrow(rows) > 0) {
        mine <- rows[sample(nrow(rows), 1), ]
        stature <- mine$stature
        for (code in wanted) if (!is.na(mine[[tolower(code)]])) values[[code]] <- typed(mine[[tolower(code)]])
    }
    if (!length(values) || is.na(stature)) {
        for (code in wanted) {
            v <- combined[[tolower(code)]]
            v <- v[!is.na(v)]
            if (length(v)) values[[code]] <- typed(sample(v, 1))
        }
        stature <- 170
    }
    # mostly the individual's own stature, sometimes another's
    stature <- stature + sample(c(0, rnorm(1, 0, 4), rnorm(1, 0, 15)), 1)
    known <- round(if (unit == "Inches") stature / 2.54 else stature, 1)
    list(kind = "association", references = refs, element = bone, side = side, values = values,
         known_stature = known, interval = sample(c("90%", "95%", "99%"), 1), unit = unit)
}

run_case <- function(case) {
    started <- Sys.time()
    output <- tryCatch(
        if (case$kind == "estimation") {
            run_estimation(case$references, case$side, case$values, case$interval, case$unit, case$bootstrap)
        } else {
            run_association(case$references, case$element, case$side, case$values, case$known_stature, case$interval, case$unit)
        },
        error = function(e) list(error = paste("R error:", conditionMessage(e))))
    output$seconds <- as.numeric(Sys.time() - started, units = "secs")
    output
}

cases <- list()
add <- function(case) if (!is.null(case)) cases[[length(cases) + 1]] <<- case
for (i in seq_len(n_cases)) add(estimation_case(FALSE))
for (i in seq_len(n_cases)) add(association_case())
# bootstrap is slow in R: fewer cases, on the small groups it applies to
for (i in seq_len(max(20L, n_cases %/% 10L))) add(estimation_case(TRUE))

# Edge cases the page allows: no measurements, no known stature, one group with
# little data, every group at once
add(list(kind = "estimation", references = labels[1], side = "left", values = list(), interval = "95%", unit = "Inches", bootstrap = FALSE))
add(list(kind = "association", references = "Trotter white male", element = "femur", side = "left",
         values = list(Fem_01 = 450), known_stature = NA, interval = "95%", unit = "Centimeters"))
small <- stature_groups$group_label[sapply(stature_groups$group_label, function(g) nrow(reference_data[[g]]) > 0 && nrow(reference_data[[g]]) < 15)]
for (g in small) {
    add(list(kind = "estimation", references = g, side = "left", values = list(Fem_01 = 440, Tib_01 = 360, Hum_01 = 320),
             interval = "95%", unit = "Centimeters", bootstrap = FALSE))
    add(list(kind = "association", references = g, element = "femur", side = "left", values = list(Fem_01 = 440),
             known_stature = 170, interval = "95%", unit = "Centimeters"))
}
add(list(kind = "estimation", references = labels, side = "right", values = setNames(as.list(c(450, 445, 360, 330, 245, 370, 265)),
         se_measurements$ards), interval = "99%", unit = "Inches", bootstrap = FALSE))

started <- Sys.time()
for (i in seq_along(cases)) {
    output <- run_case(cases[[i]])
    # the plot data is large; it is kept for every tenth case
    if (i %% 10 != 0) output$plot <- NULL
    cases[[i]]$output <- output
    if (i %% 250 == 0) message(sprintf("%d of %d cases (%.0f s)", i, length(cases), as.numeric(Sys.time() - started, units = "secs")))
}

write_json(list(r_version = R.version.string, captured_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
                groups = labels, cases = cases),
    out_file, auto_unbox = TRUE, digits = NA, null = "null", na = "null", dataframe = "columns")
message("Wrote ", length(cases), " cases to ", out_file)
