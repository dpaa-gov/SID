stature_associate <- function(known_stature, reference, case, prediction_interval) {
    df1 <- reference[c("stature", colnames(case))] # filter by column names
    df1 <- na.omit(data.frame(Measurements = rowSums(df1[, -1, drop = FALSE]), Stature = df1$stature)) # rowsums the measurements used and preserves dataframe structure
    nref <- nrow(df1) # sample size
    lm1 <- lm(Measurements ~ Stature, data = df1) # calculate model
    pi1 <- predict(lm1, interval = "prediction", level = prediction_interval) # save predicted intervals from reference
    cf1 <- rowSums(case[, , drop = FALSE])
    af1 <- data.frame(Stature = known_stature)
    pm1 <- predict(lm1, newdata = af1, interval = "prediction", level = prediction_interval)
    t_stat <- abs(pm1[1, 1] - cf1) / (summary.lm((lm1))$sigma * sqrt(1 + (1 / nref) + ((af1[1, ] - mean(df1$Stature))^2) / (nref * sd(df1$Stature)^2)))
    p_value <- 2 * pt(-abs(t_stat), df = nref - 2)
    stats_lm1 <- summary(lm1) # summary stats
    stats_df <- data.frame(PI = round(pm1[1, 1] - pm1[1, 2], 2), measurements = paste(colnames(case), collapse = " "), value = cf1, `point estimate` = pm1[1, 1], lower = pm1[1, 2], upper = pm1[1, 3], n = nref, slope = round(coef(lm1)[2], 3), intercept = round(coef(lm1)[1], 3), `R²` = round(stats_lm1$r.squared, 3), `known stature` = af1$Stature, p = round(p_value, 3), check.names = FALSE)
    return(list(pi1, stats_df, df1))
}
