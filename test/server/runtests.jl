using Test
using HTTP
using JSON3
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
# A fit to reference values that do not vary has no slope: its plot is sent with nulls, not refused as an error
@testset "plots without numbers" begin
    sample = EstimationSample(["fem_01"], fill(170.0, 12), reshape(Union{Missing, Float64}[450.0 for _ in 1:12], 12, 1), fill(1, 12))
    plot = SS.plot_json(model_plot(sample, ["fem_01"], 0.95))
    @test all(isnothing, plot.fit) && plot.x == fill(450.0, 12)
    @test occursin("null", JSON3.write(plot))
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
    @atomic state.meta_json = JSON3.write(SS.build_meta(snapshot, config))
    @atomic state.last_attempt = SS.now(SS.UTC)
    respond = SS.handler(state)
    function post(path, body)
        response = respond(HTTP.Request("POST", path, ["Content-Type" => "application/json"], JSON3.write(body)))
        return response.status, JSON3.read(response.body)
    end
    meta = JSON3.read(@atomic state.meta_json)

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
            @test response.status == 200 && JSON3.read(response.body).version == config.version
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
