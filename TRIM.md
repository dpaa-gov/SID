# Trimmed build: plan and working notes

This branch (`trim`) works toward building SID with Julia's trimming compiler (`juliac --trim`), which is still experimental. The branch stays separate until trimming is fit for production; the aim is to be ready to switch the day it is.

Started 2026-10-09. Update the Status section as stages are finished.

## Why

Nearly all of SID's idle memory is the Julia runtime, not SID. A trimmed program holds only the code it can be shown to reach, and leaves the compiler and the rest of Julia's system image out.

| | SID on the ordinary build | Trimmed test server |
|---|---|---|
| Idle memory that cannot be dropped | about 220 to 250 MiB | 24 MiB |
| After a load | 240 to 270 MiB | 45 MiB |
| Compile time | about 6 minutes | about 20 seconds |

The test server is not SID: it has HTTP.jl 2, JSON and a thin PostgreSQL client reading SID's reference tables, but none of SID's analysis. SID's own figure will be higher.

## The rule

**Every change to the code must also work on the ordinary build.**

What trimming asks for is ordinary Julia written more strictly: exact types, a thin database client, a plain router. None of it is specific to trimming. So:

- After every stage the existing checks pass on the ordinary build: the server suite, the R parity check and the browser suite.
- Only the build recipe and the program's entry point are specific to trimming, and they are kept in files of their own.
- The code changes can be merged into `main` at any time, before trimming itself. Moving to production is then a change of build, not a rewrite landing all at once.

## Stages

1. **A thin PostgreSQL client in place of LibPQ.** Check with the server suite and the parity run.
2. **A plain router** in place of HTTP.jl's.
3. **Exact types** in the request handlers, the page metadata and the worker-thread helper, working through what the checker reports.
4. **SIDJ**, the maths and its statistics library, under the checker.
5. **A trimmed build recipe** beside the current one, including where the PostgreSQL library is found inside the bundle.
6. **The trimmed image proved:** parity over HTTP, the browser suite, memory, and the connection tests.

After each of stages 1 to 4, run the ordinary checks and the checker below, and record the count.

## Status

| Stage | State | Checker errors after it |
|---|---|---|
| SID as it was | | 147 |
| 1. Thin PostgreSQL client | done 2026-10-09 | 33 |
| 2 to 6 | not started | |

Stage 1: `server/src/pg.jl` is the client, and `server/src/reference.jl` reads each column as the type it is known to be. LibPQ and Tables are gone from the server's dependencies, which took its packages from 86 to 40. On the ordinary build the server suite, the R parity check (the same 2 one-rounding-step differences in 347,254 numbers) and the browser suite pass.

What the 33 are: 14 in HTTP.jl's router, about 15 reached through `server/src/http.jl` and `server/src/meta.jl`, 1 through `server/src/config.jl`, and a few in Base.

Of the first 147: about 110 came through loading reference data (`server/src/reference.jl`), mostly LibPQ and the logging framework it brings; 14 are in HTTP.jl's router; about 15 are in `server/src/http.jl` and `server/src/meta.jl`. The checker cannot see past a call it cannot resolve, and the router is one, so the analysis handlers behind it have not been checked yet. Expect the count to rise again once stage 2 is done.

## Running the checker

It takes about 15 seconds and changes nothing in the repository. In an empty folder outside it:

```sh
julia +1.13 --project=. -e 'using Pkg;
    Pkg.develop([PackageSpec(path="/path/to/SID/server"), PackageSpec(path="/path/to/SID/SIDJ")]);
    Pkg.add("JuliaC")'

cat > entry.jl <<'EOF'
import SIDServer
function @main(args::Vector{String})::Cint
    _ = args
    SIDServer.main()
    return 0
end
Base.Experimental.entrypoint(main, (Vector{String},))
EOF

julia +1.13 --startup-file=no --project=. -e 'using JuliaC; JuliaC.main(ARGS)' -- \
    --output-exe sid-trim --bundle out --project=. --experimental --trim=safe entry.jl
```

Each `Verifier error` names a call the compiler could not resolve and the path that led to it. `import SIDServer`, not `using`: SIDServer exports `main`, which `@main` must define itself. Delete `out` before building again; the bundling step fails if it exists.

## What trimming needs, found so far

Each of these was met in the test servers (2026-10-09, Julia 1.13.1, JuliaC 0.3.10, HTTP.jl 2.9, JSON 1.10).

**The libraries.**

- HTTP.jl 2 and JSON pass as they are; HTTP.jl's own tests include trimmed servers. HTTP.jl's `Router` does not pass.
- LibPQ does not pass. A client of about 110 lines calling the PostgreSQL C library through `LibPQ_jll` does. It matched LibPQ on SID's reference queries (247,846 cells, no differences), stops a stalled query at the 15 seconds set and gives up on an unreachable database at the 10 seconds set.

**Our own code.**

- Narrow every value read from a request to one exact type before it is used. `x isa JSON.Object{String, Any}`, `x isa Vector{Any}`, `x isa Float64` or `x isa Int64`, `x isa String` are accepted; `x isa AbstractVector`, `x isa Real` and `x isa AbstractString` are not.
- A number from JSON is a `Float64`, an `Int64` or, when very large, a `BigInt`. Handle the first two and refuse the rest.
- The same applies to anything printed: an `AbstractString`, such as the message in an `ErrorException`, cannot be passed to `println` until it has been narrowed to `String`.
- Print with `println(Core.stdout, ...)`. Julia's log macros have not been tried.

**Worker threads.** A task that returns its result failed when the trimmed program ran (a `MethodError` inside the task), though the build had accepted it. A task that stores its result in a typed `Ref`, returns nothing and is then waited for worked:

```julia
box = Ref{Union{Nothing, Snapshot}}(nothing)
wait(Threads.@spawn (box[] = load(); nothing))
snapshot = box[]::Snapshot
```

Why the other form fails is not known, and one earlier test with a returning task did work. Treat anything on a worker thread as unproven until it has been run trimmed.

**The PostgreSQL library's location.** The trimmed test program looked for `libpq` in the build machine's own Julia folder (`~/.julia/artifacts/...`), which will not exist in a container. The library is in the bundle; the program has to be pointed at it there. Not yet solved.

## Not yet known

- Whether SIDJ and its statistics library (Rmath) pass.
- Whether Julia's log macros pass, or every message must be printed by hand.
- How the trimmed program behaves under the connection tests in `test/server/runtests.jl`.
- How long trimming stays experimental, and what changes between Julia versions meanwhile.
