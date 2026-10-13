# A plain HTTP.jl 2 server with its own limits switched on and none of our code.
using HTTP
resident_mib() = parse(Int, split(read("/proc/self/statm", String))[2]) * 4096 / 1024^2
live() = round(Int, Base.gc_live_bytes() / 2^20)
big = "x"^(parse(Int, get(ENV, "BIG_MB", "40")) * 1024^2)
handler(req) = req.target == "/big" ? HTTP.Response(200; body = big) :
               req.target == "/slow" ? (sleep(3); HTTP.Response(200; body = "slow")) :
               HTTP.Response(200; body = "ok")
server = HTTP.serve!(handler, "127.0.0.1", 8811; max_body_bytes = 64 * 1024,
    read_header_timeout = 5, read_timeout = 5, idle_timeout = 5, write_timeout = 5)
println("ready threads default=", Threads.nthreads(:default), " interactive=", Threads.nthreads(:interactive)); flush(stdout)
while true
    line = readline(stdin)
    isempty(line) && break
    if line == "gc"; GC.gc(); GC.gc(); ccall(:malloc_trim, Cint, (Cint,), 0); end
    println("STAT rss=", round(Int, resident_mib()), " live=", live(), " conns=", length(server.active_conns)); flush(stdout)
end
HTTP.forceclose(server)
