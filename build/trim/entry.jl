# Where the trimmed program starts (build/Dockerfile.trim). A trimmed build
# keeps only what can be reached from here.
import SIDServer

function @main(args::Vector{String})::Cint
    _ = args
    return SIDServer.julia_main()
end

Base.Experimental.entrypoint(main, (Vector{String},))
