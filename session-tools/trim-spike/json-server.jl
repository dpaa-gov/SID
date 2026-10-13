# The server, plus what SID's request handling does: read a JSON request whose
# values are not known until it arrives, check them, do some work on a worker
# thread, and answer in JSON.
using HTTP
using JSON

struct RequestError <: Exception
    status::Int
    message::String
end

json_response(status::Int, body::String)::HTTP.Response =
    HTTP.Response(status, ["Content-Type" => "application/json; charset=utf-8", "Cache-Control" => "no-store"], body)

# A number as JSON gives it, as a Float64; nothing for anything else
number(value)::Union{Float64, Nothing} = value isa Float64 ? value : value isa Int64 ? Float64(value) : nothing

function estimate(request::HTTP.Request)::HTTP.Response
    parsed = try
        JSON.parse(copy(request.body))
    catch
        throw(RequestError(400, "The request body is not valid JSON"))
    end
    # each value is narrowed to one exact type before it is used
    parsed isa JSON.Object{String, Any} || throw(RequestError(400, "The request body must be a JSON object"))
    haskey(parsed, "measurements") || throw(RequestError(400, "Missing field: measurements"))
    measurements = parsed["measurements"]
    measurements isa Vector{Any} || throw(RequestError(400, "measurements must be a list"))
    values = Float64[]
    for value in measurements
        x = number(value)
        x === nothing && throw(RequestError(400, "measurements must be numbers"))
        push!(values, x)
    end
    isempty(values) && throw(RequestError(422, "Enter at least one measurement"))
    side = get(parsed, "side", "Left")
    side isa String || throw(RequestError(400, "side must be text"))
    # the work, off the thread that answers requests
    total = fetch(Threads.@spawn sum(values))::Float64
    return json_response(200, JSON.json((side = side, n = length(values), mean = total / length(values), values = values)))
end

function handle(request::HTTP.Request)::HTTP.Response
    try
        request.target == "/healthz" && return HTTP.Response(200; body = "ok")
        request.target == "/api/estimate" && request.method == "POST" && return estimate(request)
        return json_response(404, JSON.json((error = "Not found",)))
    catch e
        e isa RequestError && return json_response(e.status, JSON.json((error = e.message,)))
        return json_response(500, JSON.json((error = "Internal server error",)))
    end
end

function @main(args::Vector{String})::Cint
    _ = args
    server = HTTP.serve!(handle, "127.0.0.1", 8822; max_body_bytes = 64 * 1024,
        read_header_timeout = 10, read_timeout = 30, idle_timeout = 60, write_timeout = 30)
    println(Core.stdout, "listening")
    wait(server)
    return 0
end

Base.Experimental.entrypoint(main, (Vector{String},))
