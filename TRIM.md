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
| 2. Plain router | done 2026-10-13 | 73 |
| 3. Exact types | done 2026-10-13 | 0: the trimmed build succeeds |
| 4. SIDJ under the checker | passes as it is, with one warning (see below) | 0 |
| 5 and 6 | not started | |

Stage 1: `server/src/pg.jl` is the client, and `server/src/reference.jl` reads each column as the type it is known to be. LibPQ and Tables are gone from the server's dependencies, which took its packages from 86 to 40. On the ordinary build the server suite, the R parity check (the same 2 one-rounding-step differences in 347,254 numbers) and the browser suite pass.

Stage 2: `route` in `server/src/http.jl` tells the five routes apart by name. Before the change, what the old router answered was recorded for 174 requests (six methods, 29 paths: closing and doubled slashes, query strings, wrong case, paths under `/api` that are not routes, files and paths outside the web folder); the new routing gives the same answer to every one. A test of the routing was added to the server suite. On the ordinary build the server suite, the parity check and the browser suite pass.

The count rose from 33 to 73, as expected: nothing in HTTP.jl is objected to any more, and the checker can now see the analysis handlers. Of the 73, 55 are in the server's own code, nearly all in `server/src/api.jl` (the handlers for estimation, the plot and association), with a few in `server/src/meta.jl`, `server/src/http.jl` and `server/src/config.jl`; 18 are in Base.

Stage 3: every value read from a request is told to be one exact kind before it is used (`server/src/api.jl`); result rows, plots and the page metadata have declared types; the worker-thread helper says what it gives back and uses the form that works when trimmed; the time reference data was loaded is written by hand (`timestamp` in `server/src/meta.jl`, checked against Julia's own in the tests); an unexpected error is put into words by `describe` in `server/src/http.jl`. One small change in `SIDJ/src/data.jl`.

How it was checked. Before any change, the handlers' answers were recorded byte for byte for 4,668 requests: every recorded R case, the plot of a third of the estimations, about 900 malformed requests (each field of each route given every kind of wrong value) and the page metadata. After the rewrite, on the ordinary build, all but 4 are identical, and those 4 are an intended change: `true` is no longer taken as the number 1. The server suite, the R parity check and the browser suite pass.

Two things changed on purpose, both agreed with the user:

- `true` and `false` are refused where a number is expected. Julia counts them as 1 and 0, and the old check ("any kind of real number") let them through. The numbers too large to be ordinary are still handled as before.
- In three places an unexpected error is now described by its kind, with what it says only where it is one of the app's own kinds, instead of Julia's full account with a stack trace: when reference data fails to load, when the first load fails in the background, and when the program cannot start.

One fault found and fixed, which is also on `main`: a POST with no body at all was answered 500. HTTP.jl 2 hands such a request over as a thing of its own (`HTTP.EmptyBody`), not as an empty body. It is now read as empty and answered 400, and there is a test of it through a real connection. The earlier tests missed it because they called the handler directly.

**The trimmed program, built by the checker on the development machine (not yet an image):**

- Starts, loads reference data from ARDS on a worker thread, and serves the page.
- Given the same 4,668 requests over HTTP, 4,630 of its answers are byte for byte those of the ordinary build. The other 38 differ only in plot coordinates, in the last binary digit (a relative difference of 2e-16); no status, message or result table differs.
- The browser suite passes against it.
- Memory that cannot be dropped: 40 MiB idle with reference data loaded, 92 MiB right after the 4,668 requests and the browser suite. The ordinary build holds about 220 to 250 MiB idle.
- It prints nothing: not "SID listening", not "Reference data loaded". Julia's log macros appear to do nothing in a trimmed program. To be replaced with plain printing in stage 5.

Stage 4: with the server's code fixed, the checker has no objection to SIDJ. It gives one warning, in `model_rows` (`SIDJ/src/estimate.jl`), about a sum over a list the compiler takes to be empty; the analyses run and match, so it has been left.

What the 33 after stage 1 were: 14 in HTTP.jl's router, about 15 reached through `server/src/http.jl` and `server/src/meta.jl`, 1 through `server/src/config.jl`, and a few in Base.

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
