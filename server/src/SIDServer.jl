module SIDServer

using Dates
using HTTP
using JSON3
using LibPQ
using Tables
using SIDJ

include("config.jl")
include("reference.jl")
include("meta.jl")
include("http.jl")
include("api.jl")
include("precompile.jl")

export main

end # module SIDServer
