# Runs both analyses once while the package is precompiled, on a small
# made-up reference group, so the first real request does not wait for Julia
# to compile. Nothing here touches the database.

using PrecompileTools: @setup_workload, @compile_workload

@setup_workload begin
    # Left and right rows of `n` individuals with a few gaps; sizes follow stature
    function sample_table(codes, n, size)
        values = Matrix{Union{Missing, Float64}}(undef, 2n, length(codes))
        stature = Union{Missing, Float64}[150.0 + 0.5 * ((i * 7) % 81) for i in 1:n]
        for i in 1:n, j in eachindex(codes)
            length = size + 4j + 2.4 * stature[i] - 360 + 0.8 * ((i * j) % 9)
            values[i, j] = (i + j) % 7 == 0 ? missing : length
            values[n + i, j] = (i + 2j) % 11 == 0 ? missing : length - 1
        end
        return BoneTable(repeat(["R$i" for i in 1:n], 2), vcat(fill("left", n), fill("right", n)), vcat(stature, stature), codes, values)
    end
    femur, tibia = ["fem_01", "fem_02"], ["tib_01", "tib_02"]
    # 120 individuals, enough that bootstrap is not used, and 40, few enough that it is
    groups = [ReferenceGroup("Sample $n", "Sample", "group", "$n",
                  Dict("femur" => sample_table(femur, n, 450), "tibia" => sample_table(tibia, n, 370))) for n in (120, 40)]
    measurements = Measurement[(code = "fem_01", bone = "femur", name = "Maximum length", stature = true),
        (code = "fem_02", bone = "femur", name = nothing, stature = false),
        (code = "tib_01", bone = "tibia", name = "Maximum length", stature = true),
        (code = "tib_02", bone = "tibia", name = nothing, stature = false)]
    snapshot = ReferenceSnapshot(groups, measurements, ["femur", "tibia"], now(UTC))
    config = Config("", 5432, "", "", "", 3838, 30, joinpath(REPO_ROOT, "web"),
        joinpath(pkgdir(@__MODULE__), "config"), "precompile")
    json(body) = Vector{UInt8}(JSON.json(body))

    @compile_workload begin
        state = AppState(config)
        @atomic state.snapshot = snapshot
        @atomic state.meta_json = JSON.json(build_meta(snapshot, config))
        @atomic state.last_attempt = now(UTC) # so nothing tries to reach ARDS
        respond = handler(state)
        post(path, body) = respond(HTTP.Request("POST", path, ["Content-Type" => "application/json"], json(body)))
        get(path) = respond(HTTP.Request("GET", path))

        get("/healthz")
        get("/api/meta")
        page = get("/")
        respond(HTTP.Request("GET", "/", ["If-None-Match" => HTTP.header(page, "ETag")]))
        for references in (["Sample 120"], ["Sample 40"]), bootstrap in (false, true)
            estimation = (references = references, side = "left", interval = 0.95, unit = "Inches",
                          values = (fem_01 = 452.5, tib_01 = 371.0))
            post("/api/estimate", merge(estimation, (bootstrap = bootstrap,)))
            post("/api/estimate/plot", merge(estimation, (measurements = ["fem_01"],)))
        end
        post("/api/associate", (references = ["Sample 120", "Sample 40"], element = "femur", side = "right",
            interval = 0.9, unit = "Centimeters", known_stature = 170.5, values = (fem_01 = 452.5, fem_02 = 460.0)))
        post("/api/associate", (references = ["Sample 40"], element = "femur", side = "left",
            interval = 0.99, unit = "Inches", known_stature = nothing, values = (fem_01 = 452.5,)))
        post("/api/estimate", (references = ["Nope"],))
    end
end
