# Analysis endpoints: request validation, stature estimation and association.

const MAX_BODY_BYTES = 64 * 1024
const REQUEST_TOO_LARGE = "The request is too large"
const REFERENCE_CHANGED = "The reference data has changed. Reload the page and try again."
const NO_MEASUREMENTS = "Enter at least one measurement"
const NO_REFERENCE = "No reference data available for this selection"
const ANALYSIS_FAILED = "The analysis failed for this input and reference data"

bad_request(message) = throw(RequestError(400, message))
cannot_analyse(message) = throw(RequestError(422, message))

function read_json(req::HTTP.Request)
    length(req.body) <= MAX_BODY_BYTES || throw(RequestError(413, REQUEST_TOO_LARGE))
    body = try
        JSON.parse(copy(req.body)) # the request's bytes, in whichever form HTTP.jl holds them
    catch
        bad_request("The request body is not valid JSON")
    end
    body isa JSON.Object || bad_request("The request body must be a JSON object")
    return body
end

field(body, name) = haskey(body, name) ? body[name] : bad_request("Missing field: $name")

function text_field(body, name)
    value = field(body, name)
    value isa AbstractString || bad_request("$name must be text")
    return String(value)
end

function list_field(body, name)
    value = field(body, name)
    value isa AbstractVector && all(v -> v isa AbstractString, value) || bad_request("$name must be a list of text values")
    return String.(value)
end

function side_field(body)
    side = lowercase(text_field(body, :side))
    side in ("left", "right") || bad_request("side must be left or right")
    return side
end

# The prediction interval's level: 90%, 95% or 99%
const LEVELS = (0.9, 0.95, 0.99)
function interval_field(body)
    value = field(body, :interval)
    value isa Real && any(level -> value == level, LEVELS) || bad_request("interval must be 0.9, 0.95 or 0.99")
    return Float64(value)
end

# Whether stature is in inches. ARDS holds it in centimetres.
function inches_field(body)
    unit = text_field(body, :unit)
    unit in ("Inches", "Centimeters") || bad_request("unit must be Inches or Centimeters")
    return unit == "Inches"
end

function flag_field(body, name)
    value = get(body, name, false)
    value isa Bool || bad_request("$name must be true or false")
    return value
end

# A number from a request as an ordinary one, or NaN for anything else. A
# number too large for one arrives as a big number that is finite itself but
# infinite once converted, so it is converted before it is checked.
plain_number(value) = value isa Real ? Float64(value) : NaN

# Typed-in measurements by code, blank ones left out
function values_field(body, name)
    value = field(body, name)
    value isa JSON.Object || bad_request("$name must be an object of measurement values")
    entries = Dict{String, Float64}()
    for (code, number) in pairs(value)
        number === nothing && continue
        amount = plain_number(number)
        isfinite(amount) && amount > 0 || bad_request("$(uppercasefirst(String(code))) must be a number above 0")
        entries[lowercase(String(code))] = amount
    end
    return entries
end

function current_snapshot(state::AppState)
    (@atomic state.snapshot) === nothing && ensure_fresh!(state)
    snapshot = @atomic state.snapshot
    snapshot === nothing && throw(RequestError(503, "Reference data could not be loaded from ARDS"))
    return snapshot
end

function selected_groups(snapshot::ReferenceSnapshot, labels)
    isempty(labels) && bad_request("Select at least one reference group")
    by_label = Dict(group.label => group for group in snapshot.groups)
    all(label -> haskey(by_label, label), labels) || throw(RequestError(409, REFERENCE_CHANGED))
    # a group named twice is one group: its individuals are not counted twice
    return [by_label[label] for label in unique(labels)]
end

# Whether any selected group has a value for a measurement, on either side.
# The page offers only those, as the fields to type in.
has_data(groups, bone, code) = any(groups) do group
    table = get(group.bones, bone, nothing)
    j = table === nothing ? nothing : findfirst(==(code), table.measurements)
    j !== nothing && any(!ismissing, view(table.values, :, j))
end

# The entered codes among `offered`, in that order. A code that is not one of
# the analysis's is refused, as is one the selected groups have no data for.
function entered_codes(entered, offered::Vector{Measurement}, groups)
    known = Dict(m.code => m for m in offered)
    for code in keys(entered)
        haskey(known, code) || bad_request("Unknown measurement: $(uppercasefirst(code))")
        has_data(groups, known[code].bone, code) ||
            cannot_analyse("$(uppercasefirst(code)) has no reference data in the selected groups")
    end
    isempty(entered) && cannot_analyse(NO_MEASUREMENTS)
    return [m.code for m in offered if haskey(entered, m.code)]
end

# --- Results as the page shows them ---

json_cell(value::AbstractFloat) = isfinite(value) ? value : nothing
json_cell(value) = value

# A plot's columns, with anything that is not a number (a fit to reference
# values that do not vary) sent as null
plot_json(plot::NamedTuple) = map(column -> json_cell.(column), plot)

table_json(columns, rows) = (columns = columns, rows = [[json_cell(cell) for cell in row] for row in rows])

measurement_text(codes) = join(uppercasefirst.(codes), " ")

# Which reference groups a result's sample came from, and how many from each
reference_text(groups, counts) = join(sort!(["$(groups[g].label) $n" for (g, n) in counts]), ", ")

# Numbers are rounded as the R SID rounded them. PI is the half-width of the
# prediction interval, point estimate minus lower bound.
const ESTIMATE_COLUMNS = ["PI", "Measurements", "Value", "Point estimate", "Lower", "Upper", "n",
                          "Slope", "Intercept", "R²", "Method", "Reference"]

function estimate_row(model::Model, groups)
    fit, lower, upper = round(model.fit; digits = 2), round(model.lower; digits = 2), round(model.upper; digits = 2)
    return Any[round(fit - lower; digits = 2), measurement_text(model.measurements), round(model.value; digits = 2),
        fit, lower, upper, model.n, round(model.slope; digits = 5), round(model.intercept; digits = 2),
        round(model.r2; digits = 3), model.bootstrap ? "Bootstrap" : "OLS", reference_text(groups, model.groups)]
end

const ASSOCIATION_COLUMNS = ["PI", "Measurements", "Value", "Point estimate", "Lower", "Upper", "n",
                             "Slope", "Intercept", "R²", "Known stature", "p", "Reference"]

function association_row(result::Association, groups)
    return Any[round(result.fit - result.lower; digits = 2), measurement_text(result.measurements),
        round(result.value; digits = 2), round(result.fit; digits = 2), round(result.lower; digits = 2),
        round(result.upper; digits = 2), result.n, round(result.slope; digits = 3), round(result.intercept; digits = 3),
        round(result.r2; digits = 3), result.stature, round(result.p; digits = 3), reference_text(groups, result.groups)]
end

function analysis(work)
    try
        return off_thread(work)
    catch e
        e isa RequestError && rethrow()
        @error "Analysis failed" exception = (e, catch_backtrace())
        throw(RequestError(422, ANALYSIS_FAILED))
    end
end

# --- Stature estimation ---

# What an estimation is run on, read from the request
function estimation_input(state::AppState, body)
    snapshot = current_snapshot(state)
    groups = selected_groups(snapshot, list_field(body, :references))
    side = side_field(body)
    level = interval_field(body)
    inches = inches_field(body)
    entered = values_field(body, :values)
    offered = filter(m -> m.stature, snapshot.measurements)
    codes = entered_codes(entered, offered, groups)
    sample = estimation_sample(groups, side, codes; inches)
    (isempty(sample.stature) || all(ismissing, sample.stature)) && cannot_analyse(NO_REFERENCE)
    return (; groups, level, sample, values = [entered[code] for code in codes])
end

# Every model, in the order they are made: one measurement, then two, and so
# on. `selected` is the one with the narrowest interval, which the page shows
# first; its plot comes with it.
function estimate_handler(state::AppState, req::HTTP.Request)
    body = read_json(req)
    input = estimation_input(state, body)
    bootstrap = flag_field(body, :bootstrap)
    result = analysis(() -> estimate(input.sample, input.values, input.level; bootstrap))
    isempty(result.models) && cannot_analyse("Not enough reference data: every model needs at least $MIN_REFERENCE individuals")
    rows = [estimate_row(model, input.groups) for model in result.models]
    selected = argmin(i -> (rows[i][1], i), eachindex(rows))
    plot = model_plot(input.sample, result.models[selected].measurements, input.level)
    return json_response(200, (results = table_json(ESTIMATE_COLUMNS, rows), selected = selected - 1, plot = plot_json(plot)))
end

# The plot of another model, chosen in the results table
function estimate_plot_handler(state::AppState, req::HTTP.Request)
    body = read_json(req)
    input = estimation_input(state, body)
    model = unique(lowercase.(list_field(body, :measurements)))
    issubset(model, input.sample.measurements) && !isempty(model) || bad_request("measurements must be some of those entered")
    plot = model_plot(input.sample, model, input.level)
    # a model the estimate would not make, or one the reference data no longer supports
    length(plot.x) < MIN_REFERENCE && cannot_analyse("Not enough reference data: a model needs at least $MIN_REFERENCE individuals")
    return json_response(200, (plot = plot_json(plot),))
end

# --- Stature association ---

function associate_handler(state::AppState, req::HTTP.Request)
    body = read_json(req)
    snapshot = current_snapshot(state)
    groups = selected_groups(snapshot, list_field(body, :references))
    element = text_field(body, :element)
    element in snapshot.bones || bad_request("Unknown element: $element")
    side = side_field(body)
    level = interval_field(body)
    inches = inches_field(body)
    entered = values_field(body, :values)
    codes = entered_codes(entered, filter(m -> m.bone == element, snapshot.measurements), groups)
    known = get(body, :known_stature, nothing)
    known === nothing && cannot_analyse("Enter a known stature")
    stature = plain_number(known)
    isfinite(stature) && stature > 0 || bad_request("The known stature must be a number above 0")
    sample = association_sample(groups, element, side, codes; inches)
    isempty(sample.stature) && cannot_analyse(NO_REFERENCE)
    length(sample.stature) < MIN_REFERENCE &&
        cannot_analyse("Not enough reference data: at least $MIN_REFERENCE individuals are needed")
    value = sum(entered[code] for code in codes)
    result = analysis(() -> associate(sample, value, stature, level))
    return json_response(200, (results = table_json(ASSOCIATION_COLUMNS, [association_row(result, groups)]),
                               plot = plot_json(association_plot(sample, level))))
end
