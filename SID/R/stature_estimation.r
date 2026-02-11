stature_estimate <- function(reference, case, prediction_interval, bootstrap = FALSE) {
    m_names <- colnames(case)
    pi_list <- list()
    ref_list <- list()
    stats_df <- data.frame(PI = 0, measurements = "A", value = 0, `point estimate` = 0, lower = 0, upper = 0, n = 0, slope = 0, intercept = 0, `R²` = 0, method = "A", check.names = FALSE)
    l <- 1
    for (i in seq_along(m_names)) { # for every measurement used
        c_i <- combn(m_names, i) # calculate combination of measurements at i index
        for (j in seq_len(ncol(c_i))) { # for every combination at i index
            df1 <- reference[c("stature", c_i[, j])] # filter by column names
            df1 <- na.omit(data.frame(Measurements = rowSums(df1[, -1, drop = FALSE]), Stature = df1$stature)) # rowsums the measurements used and preserves dataframe structure
            ref_list[[l]] <- df1
            lm1 <- lm(Stature ~ Measurements, data = df1) # calculate model
            pi_list[[l]] <- predict(lm1, interval = "prediction", level = prediction_interval) # save predicted intervals from reference
            cf1 <- data.frame(Measurements = rowSums(case[, c(c_i[, j]), drop = FALSE])) # structure the case data
            stats_lm1 <- summary(lm1) # summary stats

            # Decide method: bootstrap only if enabled AND n < 100
            use_bootstrap <- bootstrap && nrow(df1) < 100

            if (use_bootstrap) {
                # Bootstrap prediction interval (5000 resamples, lm.fit for speed)
                pm1_boot <- boot_predict(df1, cf1$Measurements, prediction_interval, B = 5000)
                pm1 <- round(pm1_boot, 2)
                method <- "Bootstrap"
            } else {
                pm1 <- predict(lm1, newdata = cf1, interval = "prediction", level = prediction_interval)
                pm1 <- round(pm1, 2)
                method <- "OLS"
            }

            stats_df <- rbind(stats_df, data.frame(PI = round(pm1[1] - pm1[2], 2), measurements = paste(c_i[, j], collapse = " "), value = cf1$Measurements, `point estimate` = pm1[1], lower = pm1[2], upper = pm1[3], n = nrow(df1), slope = round(stats_lm1$coefficients[2], 5), intercept = round(stats_lm1$coefficients[1], 2), `R²` = round(stats_lm1$r.squared, 3), method = method, check.names = FALSE))
            l <- l + 1
        }
    }
    return(list(pi_list, stats_df[-1, ], ref_list))
}

# Bootstrap prediction interval for a single specimen value using lm.fit() for speed.
# Adds residual noise (rnorm draw) to each bootstrap prediction so the interval
# captures both coefficient uncertainty AND irreducible observation scatter.
# Returns named vector: c(fit, lwr, upr)
boot_predict <- function(df, specimen_value, level, B = 5000) {
    X_ref <- cbind(1, df$Measurements)
    y_ref <- df$Stature
    n <- nrow(df)
    p <- ncol(X_ref)
    alpha <- 1 - level
    preds <- numeric(B)
    X_new <- c(1, specimen_value)
    for (b in seq_len(B)) {
        idx <- sample.int(n, replace = TRUE)
        Xb <- X_ref[idx, , drop = FALSE]
        yb <- y_ref[idx]
        fit <- lm.fit(Xb, yb)
        y_hat <- sum(X_new * fit$coefficients)
        # Residual SD from this bootstrap sample
        resid_b <- yb - Xb %*% fit$coefficients
        sigma_b <- sqrt(sum(resid_b^2) / (n - p))
        # Add observation noise for a true prediction interval
        preds[b] <- rnorm(1, mean = y_hat, sd = sigma_b)
    }
    point_est <- sum(X_new * lm.fit(X_ref, y_ref)$coefficients)
    c(fit = point_est, lwr = quantile(preds, alpha / 2, names = FALSE), upr = quantile(preds, 1 - alpha / 2, names = FALSE))
}
