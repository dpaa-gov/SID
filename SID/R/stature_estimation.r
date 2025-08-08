stature_estimate <- function(reference, case, prediction_interval) {
    m_names <- colnames(case)
    pi_list <- list()
    ref_list <- list()
    stats_df <- data.frame(PI = 0, measurements = "A", value = 0, point_estimate = 0, lower_pi = 0, upper_pi = 0, N = 0, slope = 0, intercept = 0, r_squared = 0)
    l <- 1
    for (i in 1:length(m_names)) { #for every measurement used
        c_i <- combn(m_names,i) #calculate combination of measurements at i index
        for (j in 1:ncol(c_i)) { #for every combination at i index
            df1 <- reference[c("stature", c_i[,j])] #filter by column names
            df1 <- na.omit(data.frame(Measurements = rowSums(df1[, -1, drop=FALSE]), Stature = df1$stature)) #rowsums the measurements used and preserves dataframe structure
            ref_list[[l]] <- df1
            lm1 <- lm(Stature ~ Measurements,data = df1) #calculate model
            pi_list[[l]] <- predict(lm1, interval = "prediction", level = prediction_interval) #save predicted intervals from reference
            cf1 <- data.frame(Measurements = rowSums(case[,c(c_i[,j]),drop=FALSE])) #structure the case data
            pm1 <- predict(lm1, newdata = cf1, interval = "prediction", level = prediction_interval)
            pm1 <- round(pm1, 2)
            stats_lm1 <- summary(lm1) #summary stats
            stats_df <- rbind(stats_df, data.frame(PI = round(pm1[1] - pm1[2], 2), measurements = paste(c_i[,j], collapse = ' '), value = cf1$Measurements, point_estimate = pm1[1], lower_pi = pm1[2], upper_pi = pm1[3], N = nrow(df1), slope = round(stats_lm1$coefficients[2],5), intercept = round(stats_lm1$coefficients[1], 2), r_squared = round(stats_lm1$r.squared,3)))
            l <- l + 1
        }
    }
    return(list(pi_list, stats_df[-1,], ref_list))
}