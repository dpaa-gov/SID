# Stature association: is a known stature consistent with a bone? The sum of
# the bone's measurements is regressed on stature in the reference sample,
# and the specimen's sum is compared with the value predicted at the known
# stature by a t-test on the prediction error.

struct Association
    measurements::Vector{String}
    value::Float64            # the specimen's summed measurements
    stature::Float64          # the known stature
    fit::Float64              # summed measurements predicted at that stature
    lower::Float64
    upper::Float64
    n::Int
    slope::Float64
    intercept::Float64
    r2::Float64
    t::Float64
    p::Float64                # two-sided
    groups::Vector{Pair{Int, Int}}
end

function associate(sample::AssociationSample, value::Real, stature::Real, level::Real)
    n = length(sample.stature)
    n < MIN_REFERENCE && throw(ArgumentError("at least $MIN_REFERENCE reference individuals are needed"))
    line = fit_line(sample.stature, sample.sum)
    interval = prediction(line, stature, level)
    t = abs(interval.fit - value) / (line.sigma * spread(line, stature))
    p = 2 * pt(-t, n - 2)
    return Association(sample.measurements, value, stature, interval.fit, interval.lower, interval.upper,
        n, line.slope, line.intercept, line.r2, t, p, group_counts(sample.group))
end

association_plot(sample::AssociationSample, level::Real) = line_plot(sample.stature, sample.sum, level)
