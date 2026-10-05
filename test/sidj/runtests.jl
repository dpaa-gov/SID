# SIDJ's tests. They need no database: the data is made up here. How SIDJ
# compares with the R SID on ARDS is checked separately, in test/parity.

using Test
using Random
using SIDJ

close(x, y; rtol = 1e-12) = isapprox(x, y; rtol, atol = 1e-12)

# ---------- the line and its intervals, against R ----------
# Twelve made-up individuals. The expected numbers are R 4.4.3's lm(),
# summary.lm() and predict(interval = "prediction") on the same data.
const X = [41.2, 43.5, 44.1, 45.8, 46.0, 47.3, 48.9, 49.5, 50.2, 51.7, 52.4, 53.9]
const Y = [160.1, 163.0, 162.2, 166.8, 165.1, 168.0, 170.9, 169.4, 172.6, 173.1, 176.0, 177.2]

@testset "a line as R fits it" begin
    line = fit_line(X, Y)
    @test close(line.intercept, 102.17313965876878) && close(line.slope, 1.3895949940727144)
    @test close(line.sigma, 0.97441587231660187) && close(line.r2, 0.9713319356213006)
    for (level, lower, upper) in ((0.9, 165.64200398089707, 169.32620477947563),
                                  (0.95, 165.21952865094335, 169.74868010942936),
                                  (0.99, 164.26300441715509, 170.70520434321762))
        p = prediction(line, 47, level)
        @test close(p.fit, 167.48410438018635) && close(p.lower, lower) && close(p.upper, upper)
    end
    # an exact line
    exact = fit_line([1.0, 2, 3, 4], [5.0, 8, 11, 14])
    @test close(exact.slope, 3) && close(exact.intercept, 2) && close(exact.r2, 1)
end

@testset "bootstrap interval" begin
    line = fit_line(X, Y)
    ols = prediction(line, 47, 0.95)
    boot = bootstrap_prediction(X, Y, 47, 0.95; rng = Xoshiro(1))
    # the point estimate is the full fit's; only the bounds are resampled
    @test boot.fit == ols.fit
    @test boot.lower < boot.fit < boot.upper
    # close to the normal-theory interval for data this well behaved
    @test abs((boot.upper - boot.lower) / (ols.upper - ols.lower) - 1) < 0.15
    # the same random numbers give the same interval
    @test bootstrap_prediction(X, Y, 47, 0.95; rng = Xoshiro(1)) == boot
    @test bootstrap_prediction(X, Y, 47, 0.95; rng = Xoshiro(2)) != boot
end

# ---------- reference groups ----------
# Two groups. Individuals have a femur and a tibia, left and right; some
# measurements are missing, and one individual has no tibia at all.
function group(label, n; offset = 0.0)
    accession = ["$label-$i" for i in 1:n]
    stature = Union{Missing, Float64}[150.0 + 30 * (i - 1) / (n - 1) + offset for i in 1:n]
    femur = Matrix{Union{Missing, Float64}}(undef, 2n, 2)
    tibia = Matrix{Union{Missing, Float64}}(undef, 2n - 2, 1)
    for i in 1:n, (s, shift) in ((0, 0.0), (n, -1.5))
        femur[s + i, 1] = 2.6 * stature[i] + 20 + 3 * sin(i) + shift
        femur[s + i, 2] = i % 5 == 0 ? missing : 2.5 * stature[i] + 30 + 2 * cos(i) + shift
    end
    for i in 1:n - 1, (s, shift) in ((0, 0.0), (n - 1, -1.0))
        tibia[s + i, 1] = 2.1 * stature[i] + 10 + 3 * cos(2i) + shift
    end
    sides = vcat(fill("left", n), fill("right", n))
    return ReferenceGroup(label, label, "a", "b", Dict(
        "femur" => BoneTable(vcat(accession, accession), sides, vcat(stature, stature), ["fem_01", "fem_02"], femur),
        "tibia" => BoneTable(vcat(accession[1:n - 1], accession[1:n - 1]), vcat(fill("left", n - 1), fill("right", n - 1)),
                             vcat(stature[1:n - 1], stature[1:n - 1]), ["tib_01"], tibia)))
end

const BIG, SMALL = group("Big", 150), group("Small", 30; offset = 5.0)

@testset "an individual's bones joined" begin
    sample = estimation_sample([BIG, SMALL], "left", ["fem_01", "tib_01"])
    @test sample.measurements == ["fem_01", "tib_01"]
    @test length(sample.stature) == 180 && sample.group == vcat(fill(1, 150), fill(2, 30))
    # femur and tibia of one individual on one row; no tibia for the last of each group
    @test sample.values[1, 1] == BIG.bones["femur"].values[1, 1] && sample.values[1, 2] == BIG.bones["tibia"].values[1, 1]
    @test ismissing(sample.values[150, 2]) && !ismissing(sample.values[150, 1])
    right = estimation_sample([SMALL], "right", ["fem_01"])
    @test right.values[1, 1] == SMALL.bones["femur"].values[31, 1]
    inches = estimation_sample([SMALL], "left", ["fem_01"]; inches = true)
    @test inches.stature[1] ≈ SMALL.bones["femur"].stature[1] / 2.54
    @test isempty(estimation_sample([SMALL], "middle", ["fem_01"]).stature)
end

@testset "estimation" begin
    sample = estimation_sample([BIG, SMALL], "left", ["fem_01", "fem_02", "tib_01"])
    result = estimate(sample, [470.0, 455.0, 360.0], 0.95)
    # every combination, smallest first, in the order R's combn makes them
    @test [m.measurements for m in result.models] == [["fem_01"], ["fem_02"], ["tib_01"], ["fem_01", "fem_02"],
        ["fem_01", "tib_01"], ["fem_02", "tib_01"], ["fem_01", "fem_02", "tib_01"]]
    m = result.models[5]
    @test m.value == 830 && m.n == 178 && !m.bootstrap
    # the same as fitting that model by hand
    x = [sample.values[i, 1] + sample.values[i, 3] for i in 1:180 if !ismissing(sample.values[i, 3])]
    y = [sample.stature[i] for i in 1:180 if !ismissing(sample.values[i, 3])]
    p = prediction(fit_line(x, y), 830, 0.95)
    @test m.fit == p.fit && m.lower == p.lower && m.upper == p.upper
    @test m.groups == [1 => 149, 2 => 29]
    # the model's plot: its reference individuals in order of x, and the line through them
    plot = model_plot(sample, ["fem_01", "tib_01"], 0.95)
    @test issorted(plot.x) && length(plot.x) == 178 && sort(plot.y) == sort(y)
    @test all(i -> plot.lower[i] < plot.fit[i] < plot.upper[i], eachindex(plot.x))
    @test_throws ArgumentError model_plot(sample, ["hum_01"], 0.95)
    @test_throws ArgumentError estimate(sample, [470.0], 0.95)
end

@testset "models need ten individuals; bootstrap only below a hundred" begin
    tiny = group("Tiny", 9)
    @test isempty(estimate(estimation_sample([tiny], "left", ["fem_01"]), [470.0], 0.95).models)
    sample = estimation_sample([BIG, SMALL], "left", ["fem_01"])
    big = estimate(estimation_sample([BIG], "left", ["fem_01"]), [470.0], 0.95; bootstrap = true, rng = Xoshiro(3))
    small = estimate(estimation_sample([SMALL], "left", ["fem_01"]), [470.0], 0.95; bootstrap = true, rng = Xoshiro(3))
    @test !only(big.models).bootstrap && only(small.models).bootstrap
    off = only(estimate(estimation_sample([SMALL], "left", ["fem_01"]), [470.0], 0.95).models)
    @test only(small.models).fit == off.fit && only(small.models).lower != off.lower
    @test length(estimate(sample, [470.0], 0.95; bootstrap = true).models) == 1
end

@testset "association" begin
    # against R: lm(x ~ y), predicted at y = 170, and SID's t-test of 49 there
    sample = AssociationSample(["x"], Y, X, fill(1, 12))
    a = associate(sample, 49, 170, 0.95)
    @test close(a.fit, 48.78370471014496) && close(a.lower, 47.177193941873433) && close(a.upper, 50.390215478416486)
    @test close(a.t, 0.29998923651546483) && close(a.p, 0.77032858113605851)
    @test close(a.slope, 0.69900362318840703) && close(a.intercept, -70.046911231884238) && a.n == 12
    @test a.groups == [1 => 12]

    femur = association_sample([BIG, SMALL], "femur", "left", ["fem_01", "fem_02"])
    # individuals missing either measurement are left out; the rest are summed
    @test length(femur.stature) == 180 - 30 - 6 && femur.sum[1] == sum(BIG.bones["femur"].values[1, :])
    @test isempty(association_sample([BIG], "humerus", "left", ["hum_01"]).stature)
    @test isempty(association_sample([BIG], "femur", "left", ["fem_09"]).stature)
    @test association_sample([SMALL], "femur", "left", ["fem_01"]; inches = true).stature[1] ≈ (150 + 5) / 2.54
    @test_throws ArgumentError associate(association_sample([group("Tiny", 9)], "femur", "left", ["fem_01"]), 400, 170, 0.95)
    plot = association_plot(femur, 0.9)
    @test issorted(plot.x) && length(plot.x) == length(femur.stature)
end
