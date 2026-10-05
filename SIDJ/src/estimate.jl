# Stature estimation. Every combination of the entered measurements is a
# model: stature regressed on the sum of those measurements, over the
# reference individuals who have all of them. The analyst picks among them.

const MIN_REFERENCE = 10      # fewest reference individuals a model may be fitted to
const BOOTSTRAP_BELOW = 100   # with bootstrap on, samples smaller than this use it
const BOOTSTRAP_DRAWS = 5000

struct Model
    measurements::Vector{String}
    value::Float64            # the specimen's summed measurements
    fit::Float64              # point estimate of stature
    lower::Float64
    upper::Float64
    n::Int
    slope::Float64
    intercept::Float64
    r2::Float64
    bootstrap::Bool           # interval by bootstrap rather than OLS
    groups::Vector{Pair{Int, Int}} # the sample's groups the rows came from => how many, by group
end

struct Estimate
    models::Vector{Model}
end

# Every non-empty subset of 1:m, smallest first, each size in lexicographic
# order (the order R's combn gives)
function subsets(m::Integer)
    out = Vector{Int}[]
    for k in 1:m
        chosen = collect(1:k)
        while true
            push!(out, copy(chosen))
            i = k
            while i >= 1 && chosen[i] == m - k + i
                i -= 1
            end
            i == 0 && break
            chosen[i] += 1
            for j in i + 1:k
                chosen[j] = chosen[j - 1] + 1
            end
        end
    end
    return out
end

# How many rows came from each group, for the groups that gave any
function group_counts(group)
    counts = Dict{Int, Int}()
    for g in group
        counts[g] = get(counts, g, 0) + 1
    end
    return sort!(collect(counts))
end

# Rows with a stature and every measurement in `used`, and their sums
function model_rows(sample::EstimationSample, used)
    rows = [i for i in eachindex(sample.stature)
            if !ismissing(sample.stature[i]) && all(j -> !ismissing(sample.values[i, j]), used)]
    x = Float64[sum(sample.values[i, j] for j in used) for i in rows]
    y = Float64[sample.stature[i] for i in rows]
    return rows, x, y
end

# `values` are the specimen's measurements, in the order of the sample's
# measurements; each is a model on its own and in combination with the others.
function estimate(sample::EstimationSample, values::AbstractVector{<:Real}, level::Real;
                  bootstrap::Bool = false, rng::AbstractRNG = Random.default_rng())
    length(values) == length(sample.measurements) ||
        throw(ArgumentError("one value is needed for each of the sample's measurements"))
    models = Model[]
    for used in subsets(length(values))
        rows, x, y = model_rows(sample, used)
        length(rows) < MIN_REFERENCE && continue
        value = sum(values[j] for j in used)
        line = fit_line(x, y)
        resampled = bootstrap && length(rows) < BOOTSTRAP_BELOW
        interval = resampled ? bootstrap_prediction(x, y, value, level; rng) : prediction(line, value, level)
        push!(models, Model(sample.measurements[used], value, interval.fit, interval.lower, interval.upper,
            length(rows), line.slope, line.intercept, line.r2, resampled, group_counts(sample.group[rows])))
    end
    return Estimate(models)
end

# What one model's plot shows: the reference individuals, the fitted line and
# its prediction interval at each of them, ordered by summed measurement.
function model_plot(sample::EstimationSample, measurements::AbstractVector{<:AbstractString}, level::Real)
    used = [findfirst(==(code), sample.measurements) for code in measurements]
    any(isnothing, used) && throw(ArgumentError("measurements must be the sample's"))
    _, x, y = model_rows(sample, Int.(used))
    return line_plot(x, y, level)
end

function line_plot(x, y, level)
    order = sortperm(x)
    x, y = x[order], y[order]
    line = fit_line(x, y)
    band = [prediction(line, xi, level) for xi in x]
    return (x = x, y = y, fit = [b.fit for b in band], lower = [b.lower for b in band], upper = [b.upper for b in band])
end
