import SIDServer
function @main(args::Vector{String})::Cint
    _ = args
    SIDServer.main()
    return 0
end
Base.Experimental.entrypoint(main, (Vector{String},))
