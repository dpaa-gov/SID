using Test
using HTTP
using JSON
using SIDServer
using SIDJ
const SS = SIDServer

const HAVE_DB = !isempty(get(ENV, "DB_NAME", ""))

@testset "config" begin
    @test SS.conninfo_value("a'b\\c") == "'a\\'b\\\\c'"
    @test_throws ErrorException SS.Config(Dict("DB_NAME" => "ards"))
    config = SS.Config(Dict("DB_NAME" => "ards", "DB_USER" => "u", "DB_PASS" => "p", "DB_PORT" => "x"))
    @test config.db_port == 5432
    @test config.port == 3838
end

# Bones are listed head to toe where the data collection manual numbers their
# measurements, by a bone's lowest number; the rest follow by name.
@testset "bone order" begin
    @test SS.manual_number("45") == 45 && SS.manual_number(" 45a") == 45
    @test SS.manual_number(missing) === nothing && SS.manual_number("MCAL") === nothing
    bone_of = ["femur", "femur", "humerus", "fibula", "tibia", "talus"]
    numbers = ["75", "76", "45", "92", "86", missing]
    @test SS.bone_order(["fibula", "femur", "tibia", "humerus", "talus"], bone_of, numbers) == ["humerus", "femur", "tibia", "fibula", "talus"]
end

# Rounding as the R SID rounded: the PI from the rounded bounds
# No more of a request is read than the 64 KB any request to SID may be: one of
# a gigabyte or two would otherwise be held in memory before anything could refuse it.
@testset "a request is read only as far as its limit" begin
    config = SS.Config("", 5432, "", "", "", 3838, 30, joinpath(SS.REPO_ROOT, "web"), joinpath(pkgdir(SS), "config"), "test")
    state = SS.AppState(config)
    @atomic state.last_attempt = SS.now(SS.UTC) # so nothing tries to reach ARDS
    inner = SS.handler(state)
    largest = Ref(0) # the largest body the app itself was handed
    server = HTTP.serve!(SS.limited(req -> (largest[] = max(largest[], length(req.body)); inner(req))), "127.0.0.1", 8772; stream = true)
    url = "http://127.0.0.1:8772"
    post(path, body) = HTTP.post(url * path, ["Content-Type" => "application/json"], body; status_exception = false, retry = false)
    message(response) = JSON.parse(response.body).error
    # a request written by hand, for what the client above will not send; the answer, or nothing if none came in time
    function raw(text; seconds = 10)
        socket = HTTP.Sockets.connect("127.0.0.1", 8772)
        write(socket, text)
        answer = @async String(read(socket))
        done = timedwait(() -> istaskdone(answer), seconds) == :ok
        close(socket)
        return done ? fetch(answer) : nothing
    end
    try
        @test SS.body_limit("/api/estimate") == SS.MAX_BODY_BYTES == 64 * 1024
        # small requests reach the app as before
        small = "{\"references\": []}"
        ordinary = post("/api/estimate", small)
        @test ordinary.status in (400, 503) && largest[] == sizeof(small)
        @test HTTP.get(url * "/healthz").status == 200
        # a request up to the limit is still handed over
        fits = post("/api/estimate", "{\"pad\": \"" * "x"^60_000 * "\"}")
        @test fits.status != 413 && largest[] > 60_000
        # over it: refused, and never handed to the app, on every route
        largest[] = 0
        for path in ("/api/estimate", "/api/estimate/plot", "/api/associate")
            over = post(path, "{\"pad\": \"" * "x"^100_000 * "\"}")
            @test over.status == 413 && message(over) == SS.REQUEST_TOO_LARGE
        end
        @test largest[] == 0
        # a request that says it is 2 GB is refused on its word: nothing of it is waited for or read
        seconds = @elapsed answer = raw("POST /api/estimate HTTP/1.1\r\nHost: x\r\nContent-Length: 2000000000\r\n\r\n{\"pad\": \"")
        @test answer !== nothing && startswith(answer, "HTTP/1.1 413") && seconds < 5 && largest[] == 0
        # one that does not say how large it is is cut off once it has gone over
        chunk = string(16384; base = 16) * "\r\n" * "x"^16384 * "\r\n"
        answer = raw("POST /api/associate HTTP/1.1\r\nHost: x\r\nConnection: close\r\nTransfer-Encoding: chunked\r\n\r\n" * chunk^8 * "0\r\n\r\n")
        @test answer !== nothing && startswith(answer, "HTTP/1.1 413") && largest[] == 0
        # and the server is still answering afterwards
        @test HTTP.get(url * "/healthz").status == 200
    finally
        close(server)
    end
end

# Connections that are opened and left silent must not keep others out: only
# so many are held at once, and one that sends nothing is closed.
@testset "connections are limited, and silent ones closed" begin
    config = SS.Config("", 5432, "", "", "", 3838, 30, joinpath(SS.REPO_ROOT, "web"), joinpath(pkgdir(SS), "config"), "test")
    state = SS.AppState(config)
    @atomic state.last_attempt = SS.now(SS.UTC) # so nothing tries to reach ARDS
    @test SS.MAX_CONNECTIONS == 10_000 && SS.IDLE_SECONDS == 60 # above the 30 seconds Atlas allows an answer
    # a server that holds two connections and closes one silent for a second
    server = SS.listen(SS.handler(state), "127.0.0.1", 8774; max_connections = 2, idle_seconds = 1)
    health = "GET /healthz HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n"
    function answer_to(socket; seconds = 15)
        answer = @async String(read(socket))
        return timedwait(() -> istaskdone(answer), seconds) == :ok ? fetch(answer) : nothing
    end
    ask() = (socket = HTTP.Sockets.connect("127.0.0.1", 8774); write(socket, health); answer_to(socket))
    try
        @test startswith(ask(), "HTTP/1.1 200")
        # two connections that send nothing take both places
        silent = [HTTP.Sockets.connect("127.0.0.1", 8774) for _ in 1:2]
        sleep(0.3)
        # a request arriving now has to wait, and is answered once a silent one has been closed
        waited = @elapsed answer = ask()
        @test answer !== nothing && startswith(answer, "HTTP/1.1 200")
        @test 0.5 < waited < 10
        # the silent ones were told so and closed
        closed = [answer_to(socket; seconds = 10) for socket in silent]
        @test all(text -> text !== nothing && startswith(text, "HTTP/1.1 408"), closed)
        # and the server carries on
        @test startswith(ask(), "HTTP/1.1 200")
    finally
        close(server)
    end
end

# A request refused for its size leaves nothing behind it. It still arrives,
# and each connection used to keep room for what it had been sent faster
# than it was read, until a minute or two after it had closed.
@testset "a refused request leaves nothing behind" begin
    config = SS.Config("", 5432, "", "", "", 3838, 30, joinpath(SS.REPO_ROOT, "web"), joinpath(pkgdir(SS), "config"), "test")
    state = SS.AppState(config)
    @atomic state.last_attempt = SS.now(SS.UTC) # so nothing tries to reach ARDS
    server = SS.listen(SS.handler(state), "127.0.0.1", 8776)
    large = "{\"pad\": \"" * "x"^(11 * 1024^2) * "\"}"
    function send()
        socket = HTTP.Sockets.connect("127.0.0.1", 8776)
        write(socket, "POST /api/estimate HTTP/1.1\r\nHost: x\r\nContent-Length: $(sizeof(large))\r\n\r\n")
        write(socket, large)
        answer = String(readavailable(socket))
        close(socket)
        return answer
    end
    # what Julia counts as in use once everything unused has been cleared out
    in_use() = (sleep(1); GC.gc(); GC.gc(); Base.gc_live_bytes() / 1024^2)
    try
        @test SS.UNREAD_BYTES == 16 * 1024
        @test startswith(send(), "HTTP/1.1 413") # once first, so that what compiling takes is not counted
        before = in_use()
        answers = fetch.([@async send() for _ in 1:20])
        @test all(startswith("HTTP/1.1 413"), answers)
        after = in_use()
        @info "In use around twenty refused requests of 11 MB at once" before after
        @test after - before < 50
    finally
        close(server)
    end
end

# A fit to reference values that do not vary has no slope: its plot is sent with nulls, not refused as an error
@testset "plots without numbers" begin
    sample = EstimationSample(["fem_01"], fill(170.0, 12), reshape(Union{Missing, Float64}[450.0 for _ in 1:12], 12, 1), fill(1, 12))
    plot = SS.plot_json(model_plot(sample, ["fem_01"], 0.95))
    @test all(isnothing, plot.fit) && plot.x == fill(450.0, 12)
    @test occursin("null", JSON.json(plot))
end

@testset "result rows" begin
    groups = [ReferenceGroup("B group", "B", "x", "y", Dict()), ReferenceGroup("A group", "A", "x", "y", Dict())]
    model = Model(["fem_01", "tib_01"], 820.0000000001, 66.516, 63.996, 69.03, 1113, 0.0482149, 26.98765, 0.73123, false, [1 => 13, 2 => 1100])
    row = SS.estimate_row(model, groups)
    @test row == Any[2.52, "Fem_01 Tib_01", 820.0, 66.52, 64.0, 69.03, 1113, 0.04821, 26.99, 0.731, "OLS", "A group 1100, B group 13"]
    @test SS.ESTIMATE_COLUMNS[end] == "Reference" && length(SS.ESTIMATE_COLUMNS) == length(row)
end

if HAVE_DB
    config = SS.Config()
    snapshot = SS.load_reference(config)
    state = SS.AppState(config)
    @atomic state.snapshot = snapshot
    @atomic state.meta_json = JSON.json(SS.build_meta(snapshot, config))
    @atomic state.last_attempt = SS.now(SS.UTC)
    respond = SS.handler(state)
    function post(path, body)
        response = respond(HTTP.Request("POST", path, ["Content-Type" => "application/json"], JSON.json(body)))
        return response.status, JSON.parse(response.body)
    end
    meta = JSON.parse(@atomic state.meta_json)

    # What the page builds its forms from must describe the reference data as loaded
    @testset "page metadata" begin
        @test [g.label for g in meta.groups] == [g.label for g in snapshot.groups] && allunique(g.label for g in meta.groups)
        @test collect(meta.default_references) == ["Trotter white male"]
        @test collect(meta.bones) == ["humerus", "radius", "ulna", "femur", "tibia", "fibula"]
        @test [m.code for m in meta.measurements if m.stature] == ["hum_01", "rad_01", "uln_01", "fem_01", "fem_02", "tib_01", "fib_01"]
        # association offers every measurement of those bones
        @test all(m -> m.bone in meta.bones, meta.measurements) && count(m -> m.bone == "femur", meta.measurements) > 2
        for (group, loaded) in zip(meta.groups, snapshot.groups), element in group.elements
            @test collect(element.measurements) == available_measurements(loaded.bones[element.element])
        end
    end

    trotter = ["Trotter white male"]
    estimation = (references = trotter, side = "left", interval = 0.95, unit = "Inches", bootstrap = false,
                  values = (fem_01 = 450, tib_01 = 370, hum_01 = 330))

    @testset "estimation" begin
        status, body = post("/api/estimate", estimation)
        @test status == 200
        rows = body.results.rows
        @test length(rows) == 7 && collect(body.results.columns) == SS.ESTIMATE_COLUMNS
        # one measurement, then two, then all three, head to toe
        @test [r[2] for r in rows] == ["Hum_01", "Fem_01", "Tib_01", "Hum_01 Fem_01", "Hum_01 Tib_01", "Fem_01 Tib_01", "Hum_01 Fem_01 Tib_01"]
        @test body.selected + 1 == argmin(i -> (rows[i][1], i), eachindex(rows))
        selected = rows[body.selected + 1]
        @test length(body.plot.x) == selected[7] && issorted(body.plot.x)
        @test all(r -> r[11] == "OLS" && startswith(r[12], "Trotter white male "), rows)
        # inches are centimetres over 2.54
        _, cm = post("/api/estimate", merge(estimation, (unit = "Centimeters",)))
        @test all(i -> isapprox(cm.results.rows[i][4] / 2.54, rows[i][4]; atol = 0.006), eachindex(rows))
        # another model's plot
        status, other = post("/api/estimate/plot", merge(estimation, (measurements = ["hum_01"],)))
        @test status == 200 && length(other.plot.x) == rows[1][7]
        @test post("/api/estimate/plot", merge(estimation, (measurements = ["rad_01"],)))[1] == 400
        # a measurement named twice is one measurement, and a group named twice one group
        @test post("/api/estimate/plot", merge(estimation, (measurements = ["hum_01", "hum_01"],)))[2].plot.x == other.plot.x
        @test post("/api/estimate", merge(estimation, (references = vcat(trotter, trotter),)))[2].results.rows == rows
        # small groups are bootstrapped when asked for
        small = merge(estimation, (references = ["SI-TERRY black male"], bootstrap = true))
        status, boot = post("/api/estimate", small)
        @test status == 200 && all(r -> r[11] == "Bootstrap", boot.results.rows)
        # the same request again gives the same intervals, with the groups in either order
        two = ["SI-TERRY black male", "CMNH black male"]
        first = post("/api/estimate", merge(small, (references = two,)))[2].results.rows
        @test post("/api/estimate", merge(small, (references = reverse(two),)))[2].results.rows == first
        @test any(r -> r[11] == "Bootstrap", first)
    end

    @testset "association" begin
        status, body = post("/api/associate", (references = trotter, element = "femur", side = "left", interval = 0.9,
            unit = "Centimeters", known_stature = 170, values = (fem_01 = 450, fem_02 = 446)))
        @test status == 200
        row = only(body.results.rows)
        @test collect(body.results.columns) == SS.ASSOCIATION_COLUMNS
        @test row[2] == "Fem_01 Fem_02" && row[3] == 896 && row[11] == 170 && 0 <= row[12] <= 1
        @test length(body.plot.x) == row[7]
    end

    # What the R SID refused, and what the page cannot send
    @testset "refusals" begin
        message(path, body) = ((s, b) = post(path, body); (s, get(b, :error, "")))
        @test message("/api/estimate", merge(estimation, (values = (fem_01 = nothing,),))) == (422, "Enter at least one measurement")
        @test message("/api/estimate", merge(estimation, (references = ["Nope"],)))[1] == 409
        @test message("/api/estimate", merge(estimation, (references = String[],)))[1] == 400
        @test message("/api/estimate", merge(estimation, (side = "middle",)))[1] == 400
        @test message("/api/estimate", merge(estimation, (interval = 0.8,)))[1] == 400
        @test message("/api/estimate", merge(estimation, (unit = "Feet",)))[1] == 400
        @test message("/api/estimate", merge(estimation, (values = (fem_01 = -4,),))) == (400, "Fem_01 must be a number above 0")
        @test message("/api/estimate", merge(estimation, (values = (hum_02 = 300,),))) == (400, "Unknown measurement: Hum_02")
        # a measurement the selected groups have no data for is refused, not dropped
        missing_bone = findfirst(g -> !haskey(g.bones, "humerus"), snapshot.groups)
        if missing_bone !== nothing
            @test message("/api/estimate", merge(estimation, (references = [snapshot.groups[missing_bone].label],))) ==
                (422, "Hum_01 has no reference data in the selected groups")
        end
        tiny = [g.label for g in snapshot.groups if 0 < length(get(g.bones, "femur", (accession = [],)).accession) < 10]
        if !isempty(tiny)
            @test message("/api/estimate", merge(estimation, (references = tiny[1:1], values = (fem_01 = 450,)))) ==
                (422, "Not enough reference data: every model needs at least 10 individuals")
            # the plot of a model too small to fit is refused the same way, not drawn from a fit that cannot be made
            @test message("/api/estimate/plot", merge(estimation, (references = tiny[1:1], values = (fem_01 = 450,), measurements = ["fem_01"]))) ==
                (422, "Not enough reference data: a model needs at least 10 individuals")
        end
        association = (references = trotter, element = "femur", side = "left", interval = 0.95, unit = "Inches",
                       known_stature = 67, values = (fem_01 = 450,))
        @test message("/api/associate", merge(association, (known_stature = nothing,))) == (422, "Enter a known stature")
        @test message("/api/associate", merge(association, (known_stature = 0,)))[1] == 400
        @test message("/api/associate", merge(association, (values = (fem_01 = nothing,),))) == (422, "Enter at least one measurement")
        @test message("/api/associate", merge(association, (values = (tib_01 = 370,),))) == (400, "Unknown measurement: Tib_01")
        @test message("/api/associate", merge(association, (element = "skull",)))[1] == 400
        @test respond(HTTP.Request("POST", "/api/estimate", [], "not json")).status == 400
    end

    @testset "http" begin
        server, live = SS.serve(config; host = "127.0.0.1", port = 8766)
        try
            @test HTTP.get("http://127.0.0.1:8766/healthz").status == 200
            page = HTTP.get("http://127.0.0.1:8766/")
            @test page.status == 200 && occursin("<title>SID</title>", String(page.body))
            response = HTTP.get("http://127.0.0.1:8766/api/meta")
            @test response.status == 200 && JSON.parse(response.body).version == config.version
            # a second page load inside the max age reuses the snapshot
            loaded_at = (@atomic live.snapshot).loaded_at
            HTTP.get("http://127.0.0.1:8766/api/meta")
            @test (@atomic live.snapshot).loaded_at == loaded_at
            script = HTTP.get("http://127.0.0.1:8766/js/app.js")
            etag = HTTP.header(script, "ETag")
            @test HTTP.get("http://127.0.0.1:8766/js/app.js", ["If-None-Match" => etag]; status_exception = false).status == 304
            @test HTTP.get("http://127.0.0.1:8766/api/nope"; status_exception = false).status == 404
            @test HTTP.get("http://127.0.0.1:8766/../server/Project.toml"; status_exception = false).status == 404
        finally
            close(server)
        end
    end
else
    @warn "DB_NAME is not set; skipping tests that need ARDS"
end
