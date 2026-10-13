# The web server spike, with its data read from PostgreSQL through the thin client:
# reference rows are loaded at start and again on request, and served as JSON.
using HTTP
using JSON
include("PG.jl")

value(v::String)::String = "'" * replace(v, "\\" => "\\\\", "'" => "\\'") * "'"
conninfo()::String = join(("host=" * value(ENV["DB_HOST"]), "port=" * value(get(ENV, "DB_PORT", "5432")), "dbname=" * value(ENV["DB_NAME"]),
    "user=" * value(ENV["DB_USER"]), "password=" * value(ENV["DB_PASS"]), "connect_timeout='10'", "options='-c statement_timeout=15000'"), " ")

struct Snapshot
    groups::Vector{String}
    femur_rows::Int
    mean_stature::Float64
end

function load()::Snapshot
    conn = PG.connect(conninfo())
    try
        groups = PG.query(conn, """
            SELECT DISTINCT i.collection || ' ' || i.ancestry || ' ' || i.sex AS group_label
            FROM osteometry.individuals i INNER JOIN osteometry.collections c ON i.collection = c.collection
            WHERE c.stature_method = TRUE AND i.stature_method = TRUE ORDER BY 1""")
        labels = String[label for label in PG.strings(groups, "group_label") if label !== missing]
        femur = PG.query(conn, """
            SELECT i.accession, b.side, i.stature FROM osteometry.femur b
            INNER JOIN osteometry.individuals i ON b.accession = i.accession WHERE i.stature_method = TRUE""")
        statures = Float64[s for s in PG.floats(femur, "stature") if s !== missing]
        return Snapshot(labels, PG.rows(femur), isempty(statures) ? NaN : sum(statures) / length(statures))
    finally
        close(conn)
    end
end

const CURRENT = Ref{Union{Nothing, Snapshot}}(nothing)

# The same load, saying how far it got: to find the step that fails on a worker thread
function load_traced()::Snapshot
    say(step::String) = println(Core.stdout, "    worker: ", step)
    say("started")
    info = conninfo(); say("connection string made")
    conn = PG.connect(info); say("connected")
    try
        groups = PG.query(conn, "SELECT DISTINCT i.collection AS group_label FROM osteometry.individuals i ORDER BY 1"); say("first query done")
        labels = String[label for label in PG.strings(groups, "group_label") if label !== missing]; say("labels read")
        femur = PG.query(conn, "SELECT i.accession, b.side, i.stature FROM osteometry.femur b INNER JOIN osteometry.individuals i ON b.accession = i.accession"); say("second query done")
        statures = Float64[s for s in PG.floats(femur, "stature") if s !== missing]; say("statures read")
        snapshot = Snapshot(labels, PG.rows(femur), isempty(statures) ? NaN : sum(statures) / length(statures)); say("snapshot made")
        return snapshot
    finally
        close(conn); say("closed")
    end
end

# ways of running work on a worker thread, to find which the trimmed program can do
t1()::Int = fetch(Threads.@spawn 1 + 1)::Int
t2()::Snapshot = fetch(Threads.@spawn load())::Snapshot
function t3()::Snapshot
    task = Threads.@spawn load()
    return fetch(task)::Snapshot
end
function t4()::Int
    n = 20
    return fetch(Threads.@spawn n + 1)::Int
end
function t5()::Snapshot
    box = Ref{Union{Nothing, Snapshot}}(nothing)
    wait(Threads.@spawn (box[] = load(); nothing))
    return box[]::Snapshot
end
attempt(name::String, f::F) where {F} = try
    f(); println(Core.stdout, "    ", name, ": works")
catch e
    println(Core.stdout, "    ", name, ": fails (", e isa TaskFailedException ? "the task itself failed" : "another error", ")")
end

json_response(status::Int, body::String)::HTTP.Response =
    HTTP.Response(status, ["Content-Type" => "application/json; charset=utf-8"], body)

function handle(request::HTTP.Request)::HTTP.Response
    try
        request.target == "/healthz" && return HTTP.Response(200; body = "ok")
        if request.target == "/api/threads"
            attempt("t1 spawn 1 + 1", t1)
            attempt("t2 spawn load(), fetched in one line", t2)
            attempt("t3 spawn load(), task kept in a variable", t3)
            attempt("t4 spawn using a local value", t4)
            attempt("t5 spawn that stores its result, then wait", t5)
            return HTTP.Response(200; body = "done")
        end
        if request.target == "/api/direct"
            snapshot = load()
            return json_response(200, JSON.json((groups = snapshot.groups, femur_rows = snapshot.femur_rows, mean_stature = snapshot.mean_stature)))
        end
        if request.target == "/api/meta"
            # read again on a worker thread, as SID does when its data is stale
            task = Threads.@spawn load_traced()
            println(Core.stdout, "    request: task made, waiting")
            got = fetch(task)
            println(Core.stdout, "    request: task finished")
            snapshot = got::Snapshot
            CURRENT[] = snapshot
            return json_response(200, JSON.json((groups = snapshot.groups, femur_rows = snapshot.femur_rows, mean_stature = snapshot.mean_stature)))
        end
        return json_response(404, JSON.json((error = "Not found",)))
    catch e
        e isa PG.Error && return json_response(503, JSON.json((error = "Reference data could not be loaded from ARDS",)))
        what(x)::String = x isa PG.Error ? "PG.Error: " * x.message : x isa TaskFailedException ? "TaskFailedException" :
            x isa MethodError ? "MethodError" : x isa ErrorException ? "ErrorException" : x isa UndefRefError ? "UndefRefError" :
            x isa TypeError ? "TypeError" : x isa KeyError ? "KeyError" : x isa ArgumentError ? "ArgumentError" :
            x isa BoundsError ? "BoundsError" : x isa InexactError ? "InexactError" : x isa Core.MissingCodeError ? "MissingCodeError" : "something else"
        println(Core.stdout, "request to ", request.target, " failed: ", what(e))
        e isa TaskFailedException && println(Core.stdout, "  inside the task: ", what(e.task.exception))
        return json_response(500, JSON.json((error = "Internal server error",)))
    end
end

function @main(args::Vector{String})::Cint
    _ = args
    # said once at start, so that a failure to read the database can be told apart
    println(Core.stdout, "libpq at ", PG.libpq, isfile(PG.libpq) ? " (found)" : " (NOT FOUND)")
    println(Core.stdout, "DB_HOST ", haskey(ENV, "DB_HOST") ? "set" : "NOT SET", ", DB_NAME ", haskey(ENV, "DB_NAME") ? "set" : "NOT SET")
    try
        first_load = load()
        println(Core.stdout, "loaded at start: ", length(first_load.groups), " groups, ", first_load.femur_rows, " femur rows")
    catch e
        if e isa PG.Error
            println(Core.stdout, "load at start failed, PostgreSQL said: ", e.message)
        elseif e isa KeyError
            println(Core.stdout, "load at start failed: a setting is missing")
        elseif e isa ErrorException
            message = e.msg
            println(Core.stdout, "load at start failed: ", message isa String ? message : "(an error with no plain message)")
        else
            println(Core.stdout, "load at start failed with another kind of error")
        end
    end
    server = HTTP.serve!(handle, "127.0.0.1", 8823; max_body_bytes = 64 * 1024,
        read_header_timeout = 10, read_timeout = 30, idle_timeout = 60, write_timeout = 30)
    println(Core.stdout, "listening")
    wait(server)
    return 0
end

Base.Experimental.entrypoint(main, (Vector{String},))
