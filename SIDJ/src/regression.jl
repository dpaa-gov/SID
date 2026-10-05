# A straight line fitted by ordinary least squares, y = intercept + slope x,
# and the intervals R's lm() and predict(interval = "prediction") give for it.

struct LineFit
    n::Int
    xmean::Float64
    sxx::Float64        # sum of squared deviations of x from its mean
    slope::Float64
    intercept::Float64
    sigma::Float64      # residual standard error, on n - 2 degrees of freedom
    r2::Float64
end

function fit_line(x::AbstractVector{<:Real}, y::AbstractVector{<:Real})
    n = length(x)
    xmean, ymean = mean(x), mean(y)
    sxx = sxy = syy = 0.0
    for i in eachindex(x, y)
        dx, dy = x[i] - xmean, y[i] - ymean
        sxx += dx * dx
        sxy += dx * dy
        syy += dy * dy
    end
    slope = sxy / sxx
    intercept = ymean - slope * xmean
    rss = 0.0
    for i in eachindex(x, y)
        rss += (y[i] - intercept - slope * x[i])^2
    end
    return LineFit(n, xmean, sxx, slope, intercept, sqrt(rss / (n - 2)), 1 - rss / syy)
end

(line::LineFit)(x) = line.intercept + line.slope * x

# Standard error of a new observation at x, relative to sigma
spread(line::LineFit, x) = sqrt(1 + 1 / line.n + (x - line.xmean)^2 / line.sxx)

# Point estimate and prediction interval for a new observation at x
function prediction(line::LineFit, x, level)
    fit = line(x)
    half = qt((1 + level) / 2, line.n - 2) * line.sigma * spread(line, x)
    return (fit = fit, lower = fit - half, upper = fit + half)
end

# A prediction interval by resampling residuals, for small reference samples.
# Each of `draws` rounds refits the line to the fitted values plus residuals
# drawn with replacement, predicts at x, and adds noise from the full fit's
# residual spread; the interval is the percentiles of those predictions. The
# point estimate is the full fit's. Resampling residuals rather than cases
# keeps x fixed, so every refit is well defined.
function bootstrap_prediction(x::AbstractVector{<:Real}, y::AbstractVector{<:Real}, x0, level;
                              draws::Integer = BOOTSTRAP_DRAWS, rng::AbstractRNG = Random.default_rng())
    line = fit_line(x, y)
    n = length(x)
    fitted = [line(xi) for xi in x]
    residuals = y .- fitted
    dx = x .- line.xmean
    predictions = Vector{Float64}(undef, draws)
    for b in 1:draws
        # The refit by least squares, with x and so its mean and spread unchanged
        sy = sdxy = 0.0
        for i in 1:n
            yi = fitted[i] + residuals[rand(rng, 1:n)]
            sy += yi
            sdxy += dx[i] * yi
        end
        slope = sdxy / line.sxx
        predictions[b] = sy / n + slope * (x0 - line.xmean) + line.sigma * randn(rng)
    end
    alpha = 1 - level
    return (fit = line(x0), lower = quantile(predictions, alpha / 2), upper = quantile(predictions, 1 - alpha / 2))
end
