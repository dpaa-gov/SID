#!/bin/sh
# check.sh [path to the SID checkout, default ~/Development/SID-trim]
# Runs the trimming build's checker over SID and sorts what it objects to.
# Changes nothing in the repository; works in a folder under /tmp. About 15 seconds.
set -eu
repo="${1:-$HOME/Development/SID-trim}"
work="${TMPDIR:-/tmp}/sid-trim-check"
mkdir -p "$work" && cd "$work"
if [ ! -f Manifest.toml ]; then
    julia +1.13 --project=. -e "using Pkg; Pkg.develop([PackageSpec(path=\"$repo/server\"), PackageSpec(path=\"$repo/SIDJ\")]); Pkg.add(\"JuliaC\")" >/dev/null 2>&1
fi
cat > entry.jl <<'JL'
import SIDServer
function @main(args::Vector{String})::Cint
    _ = args
    SIDServer.main()
    return 0
end
Base.Experimental.entrypoint(main, (Vector{String},))
JL
rm -rf out
julia +1.13 --startup-file=no --project=. -e 'using JuliaC; JuliaC.main(ARGS)' -- \
    --output-exe sid-trim --bundle out --project=. --experimental --trim=safe entry.jl > build.log 2>&1 && echo "the trimmed build succeeded: $work/out/bin/sid-trim" || echo "the trimmed build did not succeed (log: $work/build.log)"
REPO="$repo" python3 -I - <<'PY'
import re, collections, os
repo = "/" + os.path.basename(os.environ["REPO"].rstrip("/")) + "/" # paths are printed with ~ for the home folder
text = open("build.log").read()
blocks = [b for b in re.split(r'\n(?=Verifier error #\d+)', text) if b.startswith('Verifier error')]
first = collections.Counter(); own_lines = collections.Counter()
for b in blocks:
    frames = re.findall(r'@ (\S+) (\S+?):(\d+)', b)
    if not frames: first['(no location)'] += 1; continue
    first[frames[0][0]] += 1
    own = [(p, l) for m, p, l in frames if repo in p]
    own_lines[(own[0][0].split(repo, 1)[1] + ':' + own[0][1]) if own else '(not reached through SID code)'] += 1
print(len(blocks), 'errors')
print('module the unresolved call is in:', dict(first.most_common(8)))
print('first SID line on the way to it:')
for where, n in own_lines.most_common(30): print(f'  {n:4} {where}')
if not blocks: print(text[-1200:])
PY
