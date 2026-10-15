module SIDServer

using Dates
using HTTP
using JSON
using SIDJ

include("config.jl")
include("pg.jl")
include("reference.jl")
include("meta.jl")
include("http.jl")
include("api.jl")
include("precompile.jl")

export main

end # module SIDServer
