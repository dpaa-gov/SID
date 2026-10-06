# Checks the Julia SID against the R/Shiny SID on the cases capture.sh
# recorded. Each case is sent through the server's own request handler, so
# validation, the analysis and the rounding of the results are all checked.
#
#   dev/julia.sh test/parity/compare.jl [test/parity/data/r_results.json]
#
# Needs the same ARDS the cases were recorded against. Prints a summary and
# writes every difference to test/parity/data/differences.txt.

using JSON
using HTTP
using SIDServer
const SS = SIDServer

const FILE = get(ARGS, 1, joinpath(@__DIR__, "data", "r_results.json"))
const OUT = joinpath(dirname(FILE), "differences.txt")

recorded = JSON.parse(read(FILE))
config = SS.Config()
state = SS.AppState(config)
snapshot = SS.load_reference(config)
@atomic state.snapshot = snapshot
@atomic state.meta_json = JSON.json(SS.build_meta(snapshot, config))
@atomic state.last_attempt = SS.now(SS.UTC)
respond = SS.handler(state)

function post(path, body)
    response = respond(HTTP.Request("POST", path, ["Content-Type" => "application/json"], JSON.json(body)))
    return response.status, JSON.parse(response.body)
end

# jsonlite writes a one-element vector as a single value
strings(value) = value isa AbstractString ? [String(value)] : String.(collect(value))

const LEVEL = Dict("90%" => 0.9, "95%" => 0.95, "99%" => 0.99)

function request(case)
    body = Dict{Symbol, Any}(:references => strings(case.references), :side => case.side,
        :interval => LEVEL[case.interval], :unit => case.unit,
        :values => Dict(lowercase(String(k)) => v for (k, v) in pairs(case.values)))
    if case.kind == "estimation"
        body[:bootstrap] = case.bootstrap
    else
        body[:element] = case.element
        body[:known_stature] = case.known_stature
    end
    return body
end

# The R messages and the Julia ones say the same things in other words
const SAME_ERROR = Dict(
    "Please enter at least one measurement" => "Enter at least one measurement",
    "Please enter a known stature" => "Enter a known stature",
    "No reference data available for this selection" => "No reference data available for this selection",
    "Insufficient reference data: all models require at least 10 individuals" => "Not enough reference data: every model needs at least 10 individuals",
    "Insufficient reference data: at least 10 individuals required" => "Not enough reference data: at least 10 individuals are needed",
)

measurement_set(text) = Set(lowercase.(split(text)))
group_set(text) = Set(replace(part, r" \d+$" => "") for part in split(text, ", ") if !isempty(part))

# ---------- tallies ----------
differences = String[]
counts = Dict{String, Int}()
tally(name, n = 1) = (counts[name] = get(counts, name, 0) + n)
note(i, text) = push!(differences, "case $i: $text")
worst = Dict{String, Float64}()
track(name, value) = (worst[name] = max(get(worst, name, 0.0), value))
bootstrap_gaps = Float64[]   # Julia's bound minus R's, as a share of the interval's width

function compare_number(i, what, julia, r; digits = nothing)
    tally("numbers compared")
    r === nothing && julia === nothing && return
    if r === nothing || julia === nothing
        note(i, "$what: Julia $julia, R $r")
        return tally("numbers different")
    end
    gap = abs(julia - r)
    track(what, gap)
    if gap != 0
        # R and Julia can round a value that lies on a rounding boundary differently
        last_place = digits === nothing ? 0.0 : 10.0^-digits
        if gap <= last_place * 1.0000001
            tally("numbers one rounding step apart")
            note(i, "$what: Julia $julia, R $r (one rounding step)")
        else
            tally("numbers different")
            note(i, "$what: Julia $julia, R $r")
        end
    end
end

function compare_plot(i, julia, r; x_name, y_name)
    tally("plots compared")
    rx, ry = Float64.(r.reference[x_name]), Float64.(r.reference[y_name])
    rfit, rlower, rupper = Float64.(r.interval.fit), Float64.(r.interval.lwr), Float64.(r.interval.upr)
    # ties in x are ordered differently; compare the points as a set
    rpoints = sort!(collect(zip(rx, ry, rfit, rlower, rupper)))
    jpoints = sort!(collect(zip(Float64.(julia.x), Float64.(julia.y), Float64.(julia.fit), Float64.(julia.lower), Float64.(julia.upper))))
    if length(rpoints) != length(jpoints)
        tally("plots different")
        return note(i, "plot: Julia $(length(jpoints)) points, R $(length(rpoints))")
    end
    relative = maximum((maximum(abs.(collect(a) .- collect(b)) ./ max.(1.0, abs.(collect(b)))) for (a, b) in zip(jpoints, rpoints)); init = 0.0)
    track("plot (relative)", relative)
    relative > 1e-9 && (tally("plots different"); note(i, "plot differs by $relative (relative)"))
end

for (i, case) in enumerate(recorded.cases)
    r = case.output
    path = case.kind == "estimation" ? "/api/estimate" : "/api/associate"
    status, julia = post(path, request(case))
    tally("cases")
    tally(case.kind * (get(case, :bootstrap, false) == true ? " (bootstrap)" : ""))

    if haskey(r, :error)
        tally("cases R refused")
        if startswith(r.error, "R error")
            # R crashed; Julia must refuse with a message
            status == 422 ? tally("R crashes Julia refuses") : (tally("cases different"); note(i, "R crashed ($(r.error)); Julia $status"))
        elseif status == 200 || get(SAME_ERROR, r.error, r.error) != julia.error
            tally("cases different")
            note(i, "R: $(r.error); Julia: $(status == 200 ? "a result" : julia.error)")
        end
        continue
    end
    if status != 200
        tally("cases different")
        note(i, "R gave a result; Julia: $(julia.error)")
        continue
    end
    columns = collect(julia.results.columns)
    col(row, name) = row[findfirst(==(name), columns)]

    if case.kind == "association"
        row = only(julia.results.rows)
        t = (; (Symbol(name) => only(column) for (name, column) in pairs(r.table))...)
        compare_number(i, "PI", col(row, "PI"), t.PI; digits = 2)
        compare_number(i, "Value", col(row, "Value"), t.value; digits = 2)
        compare_number(i, "Point estimate", col(row, "Point estimate"), round(t[Symbol("point estimate")]; digits = 2); digits = 2)
        compare_number(i, "Lower", col(row, "Lower"), round(t.lower; digits = 2); digits = 2)
        compare_number(i, "Upper", col(row, "Upper"), round(t.upper; digits = 2); digits = 2)
        compare_number(i, "n", col(row, "n"), t.n)
        compare_number(i, "Slope (association)", col(row, "Slope"), t.slope; digits = 3)
        compare_number(i, "Intercept (association)", col(row, "Intercept"), t.intercept; digits = 3)
        compare_number(i, "R²", col(row, "R²"), t[Symbol("R²")]; digits = 3)
        compare_number(i, "p", col(row, "p"), t.p; digits = 3)
        measurement_set(col(row, "Measurements")) == measurement_set(t.measurements) ||
            (tally("measurements different"); note(i, "measurements $(col(row, "Measurements")) vs $(t.measurements)"))
        group_set(col(row, "Reference")) == Set(strings(r.groups)) ||
            (tally("groups different"); note(i, "groups $(col(row, "Reference")) vs $(strings(r.groups))"))
        haskey(r, :plot) && compare_plot(i, julia.plot, r.plot; x_name = :Stature, y_name = :Measurements)
        continue
    end

    # Estimation: every model R made, matched by its measurements
    t = r.table
    r_models = Dict(measurement_set(t.measurements[k]) => k for k in eachindex(t.measurements))
    j_models = Dict(measurement_set(col(row, "Measurements")) => row for row in julia.results.rows)
    if keys(r_models) != keys(j_models)
        tally("model lists different")
        note(i, "models: Julia $(length(j_models)), R $(length(r_models))")
    end
    r_groups = r.groups isa AbstractString ? [r.groups] : collect(r.groups)
    for (set, k) in r_models
        row = get(j_models, set, nothing)
        row === nothing && continue
        tally("models compared")
        bootstrapped = t.method[k] == "Bootstrap"
        col(row, "Method") == t.method[k] || (tally("methods different"); note(i, "method $(col(row, "Method")) vs $(t.method[k])"))
        compare_number(i, "Point estimate", col(row, "Point estimate"), t[Symbol("point estimate")][k]; digits = 2)
        compare_number(i, "Value", col(row, "Value"), round(t.value[k]; digits = 2); digits = 2)
        compare_number(i, "n", col(row, "n"), t.n[k])
        compare_number(i, "Slope", col(row, "Slope"), t.slope[k]; digits = 5)
        compare_number(i, "Intercept", col(row, "Intercept"), t.intercept[k]; digits = 2)
        compare_number(i, "R²", col(row, "R²"), t[Symbol("R²")][k]; digits = 3)
        if bootstrapped
            # random draws: the bounds can only be close, not equal
            width = t.upper[k] - t.lower[k]
            push!(bootstrap_gaps, (col(row, "Lower") - t.lower[k]) / width, (col(row, "Upper") - t.upper[k]) / width)
            tally("bootstrap models compared")
        else
            compare_number(i, "PI", col(row, "PI"), t.PI[k]; digits = 2)
            compare_number(i, "Lower", col(row, "Lower"), t.lower[k]; digits = 2)
            compare_number(i, "Upper", col(row, "Upper"), t.upper[k]; digits = 2)
        end
        groups = r_groups[k]
        group_set(col(row, "Reference")) == Set(strings(groups)) ||
            (tally("groups different"); note(i, "groups $(col(row, "Reference")) vs $(strings(groups))"))
    end
    if haskey(r, :plot)
        model = split(t.measurements[r.selected])
        _, plot = post("/api/estimate/plot", merge(request(case), Dict(:measurements => model)))
        compare_plot(i, plot.plot, r.plot; x_name = :Measurements, y_name = :Stature)
    end
end

open(OUT, "w") do io
    foreach(line -> println(io, line), differences)
end
println("Compared with ", recorded.r_version, ", recorded ", recorded.captured_at)
for name in sort!(collect(keys(counts)))
    println(rpad(name, 36), counts[name])
end
println("\nLargest difference per value:")
for name in sort!(collect(keys(worst)))
    println(rpad("  " * name, 36), worst[name])
end
if !isempty(bootstrap_gaps)
    gaps = sort(abs.(bootstrap_gaps))
    println("\nBootstrap bounds, Julia minus R as a share of the interval width:")
    println("  median ", round(gaps[(end + 1) ÷ 2]; digits = 4), ", 95th percentile ", round(gaps[ceil(Int, 0.95 * end)]; digits = 4),
            ", largest ", round(gaps[end]; digits = 4), ", mean signed ", round(sum(bootstrap_gaps) / length(bootstrap_gaps); digits = 4))
end
println("\n", length(differences), " differences written to ", OUT)
