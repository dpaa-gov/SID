# SIDJ's tests live with the rest of the repo's tests, in test/sidj.
# This file is where Julia's `Pkg.test()` looks for them.
include(joinpath(@__DIR__, "..", "..", "test", "sidj", "runtests.jl"))
