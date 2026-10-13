# Session handoff, 2026-10-09

Written before a reboot, so that a new session can carry on without the conversation. It covers three days of work (Oct 7 to 9) on OsteoSort and SID, and one unfinished review of archaeo3d.

If you are a new session: read this first, then `~/Development/SID-trim/TRIM.md`, which is the plan and working notes for the task in progress.

## What is in progress

**A trimmed build of SID**, on branch `trim`, checked out in its own folder `~/Development/SID-trim` (a git worktree of `~/Development/SID`, which stays on `main`).

- Stage 1 of 6 is done and committed by the user (`c1927a1`): a thin PostgreSQL client (`server/src/pg.jl`) replaces LibPQ.
- **Next is stage 2:** replace HTTP.jl's `Router` with a plain dispatch over SID's five routes, in `server/src/http.jl`. Then stage 3, exact types in the handlers, metadata and the worker-thread helper.
- The rule for every stage: the change must also work on the ordinary build, and the server suite, R parity check and browser suite must pass after it. Then rerun the checker and record the count in `TRIM.md`.
- The checker's count: 147 errors on SID as it was, 33 after stage 1. It will rise once the router is replaced, because the analysis handlers behind it have not been checked yet.

The user asked to start stage 2 only when they say so.

## State of each repository

| Repository | Branch | State |
|---|---|---|
| `~/Development/OsteoSort` | `main` | clean, pushed, tests green on `00dcd56` |
| `~/Development/SID` | `main` | clean, pushed, tests green on `caa5102` |
| `~/Development/SID-trim` | `trim` | clean at `c1927a1`; local only, never pushed |
| `~/Development/archaeo3d` | `main` | clean, untouched by this session |

### OsteoSort

- Issues #7 (downloads) and #8 (uploads) are done, committed and closed.
- Still on HTTP.jl 1.11 with its hand-built hardening. The user has opened **#9 "Migrate HTTP 1 to 2"** and **#10 "Strip metadata on compile"**; neither is started. SID has both already and is the model. OsteoSort's port is larger: its streamed downloads, upload turns, the stalled-reader watchdog and the forced close all sit on HTTP.jl 1's internals.
- `VERSION` and the `Dockerfile` say 2.0.0-alpha.8; the latest release is alpha.7.
- The README does not mention the limits added for #7 and #8.

### SID

- `main` has the HTTP.jl 2 port and the stripped build. `VERSION` says 1.0.0-alpha.3; the latest release is alpha.2, so alpha.3 is not yet tagged.
- HTTP.jl 2 gave up two things, both agreed: no cap on the number of connections, and a request refused for its size gets a 413 with no message.

### archaeo3d

Asked: "is that app ready for Atlas?" The review was interrupted before the image was built (the user stopped the build), and has not been resumed. Found so far, by reading only:

- A static site served by unprivileged nginx on port 8080, with `/healthz`; no backend, no outside requests, all libraries bundled. That fits what Atlas asks of an app.
- **CSV text is put into the page as HTML without escaping** (`app.js`, in the detail panel, the filter lists and the hidden-units list). A crafted CSV could run script in the page. This is the one real problem found.
- No content-security-policy header; embedding in a frame is allowed on purpose.
- The repository is private (Atlas then needs the `DPAA_REPO_TOKEN` secret, as its README says); it has no tags, licence or tests.
- Not done: building and running the image, and checking what it serves.

## What was learned, and should not be learned again

**Memory in the Julia apps.**

- Idle memory is about 250 MiB and nearly all of it is the Julia runtime. Stock Julia's system image is 274 MB of the 421 MB `sys.so`; the app's own data is about 13 MiB.
- No effect: start-up settings (malloc arenas, GC threads, thread count, an idle clean-up); building fresh with `filter_stdlibs`. `--strip-ir` produces a program that will not start.
- `--strip-metadata` on the ordinary incremental build saves 25 to 30 MiB for 22 seconds of build time. It needs the app not to ask where its package is at run time (`CONFIG_DIR` in `server/src/config.jl`).
- HTTP.jl 2 does not save memory (slightly more), but replaces about 90 lines of hand-built hardening with its own settings.
- Measure with the client in a separate process, and in the real image at 1 CPU and 2 GiB, reading `anon` from the container's `memory.stat`. Totals, and a client in the same process, were misleading several times.

**HTTP.jl 1 and Julia sockets (still relevant to OsteoSort).**

- A Julia `TCPSocket` buffers up to 10 MB unread and keeps the room; HTTP.jl 1's idle timer then holds a closed connection, buffer included, for one to two idle periods. Fixed by `socket.throttle = 16 KB`, set through `tcpisvalid`.
- HTTP.jl 1's idle limit counts only data received, and cannot close a connection blocked on a write, because Julia's ordinary close waits for unsent data to be taken. Such a connection needs a forced close (`jl_forceclose_uv`).

**Trimming** is written up in `SID-trim/TRIM.md`: which libraries pass, how values must be typed, the worker-thread pattern that works, and what is still unknown.

**Tests.** A test that checks a table has been freed must not touch the table in its own body. HTTP.jl's client reuses connections the server has closed; give each test request its own. In a shell, `pgrep -f` and `pkill -f` match the command that runs them: use `pgrep -x`, or a pattern with a bracket in it.

## How the user wants to work

These are also in the memory notes, which a session started in `~/Development` loads.

- The user does all commits, branches and pushes. Do not commit or push. A branch or worktree only when asked.
- Explain a multi-step change and get agreement before writing files.
- **A question is not an instruction.** Answer it; do not stop, start or change anything because of it.
- Do not claim a cause before there is direct evidence. Reproduce and print the actual error first.
- Builds and long runs go in parallel; the machine has 32 cores.
- Plain language, with the reason given.

## Running things

```sh
# the database the tests need; it does not start by itself after a reboot
docker start ards-db

# SID, in either checkout
dev/julia.sh -e 'using Pkg; Pkg.test()'      # server suite, about a minute
dev/julia.sh test/parity/compare.jl          # R parity; needs test/parity/data/r_results.json
dev/julia.sh -e 'using SIDServer; SIDServer.main()'   # http://127.0.0.1:3838/, for the browser suite
docker run --rm --network host --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$PWD:/app:z" -w /app \
    mcr.microsoft.com/playwright/python:v1.49.0-jammy \
    sh -c "pip install -q playwright==1.49.0 && python test/browser/test_ui.py"

# the trimming checker, about 15 seconds, changes nothing in the repository
~/Development/SID-trim/session-tools/check.sh
```

`SID-trim` has its own copies of `.env` and the recorded R cases, since git ignores both. Do not load `.env` through a shell: the password's characters break it, and an error then prints part of it. `dev/julia.sh` reads it safely.

`gh` is not installed; the public GitHub API works with `curl` for issues and for whether a test run passed.

## Kept from the temporary folder

The session's scratch folder is under `/tmp` and does not survive a reboot. What was worth keeping is in `~/Development/SID-trim/session-tools/`:

| Path | What it is |
|---|---|
| `check.sh` | the trimming checker, self-contained |
| `trim-spike/PG.jl` | the thin PostgreSQL client as first written (now `server/src/pg.jl` in SID-trim) |
| `trim-spike/json-server.jl`, `pg-server.jl` | the two trimmed test servers; `pg-server.jl` has the five worker-thread variants |
| `trim-spike/compare-with-libpq.jl` | the cell-by-cell comparison with LibPQ |
| `trim-spike/run-with-env.py` | starts a program with `DB_*` from SID's `.env`, safely |
| `measure/idle.sh`, `breakdown.py` | run an image idle and break its memory down by mapping |
| `measure/parity-over-http.jl` | the parity check sent to a running image instead of the handler |
| `measure/h2probe.py`, `h2server.jl` | the hardening scenarios run against a plain HTTP.jl 2 server |
| `measure/build-recipe-stripped.Dockerfile` | the build recipe variant that was measured |

Several of these still name the old temporary folder inside them and need their paths changed before use. `check.sh` does not.

Docker images kept from the measurements, safe to delete: `sid:http1`, `sid:opt1a` to `sid:opt1e`. Containers that were running and will be stopped by the reboot: `ards-db`, `sid-julia`, `sid-opt1d`.
