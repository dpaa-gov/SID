#!/bin/sh
# Runs capture.R: the R/Shiny SID's analyses on made-up cases against ARDS,
# saved for compare.jl. The R code is taken from the last R release, so this
# works with the R app gone from the working tree.
#
#   test/parity/capture.sh            # 1,500 cases of each analysis
#   CASES=200 test/parity/capture.sh
#
# Needs the ARDS container on the sid-dev network and DB_* in .env. R_IMAGE
# must have DBI, RPostgres, dplyr and jsonlite; by default those are installed
# into rocker/shiny:4.4.3, the image the R SID ran in, and cached.
set -eu
cd "$(dirname "$0")/../.."
R_REF="${R_REF:-0145a9f38ac2aa89116fe576ad51b35e4a8b46b6}"
R_IMAGE="${R_IMAGE:-rocker/shiny:4.4.3}"
out=test/parity/data
mkdir -p "$out/app" "${XDG_CACHE_HOME:-$HOME/.cache}/sid/r-library"
git archive "$R_REF" SID/R | tar -x -C "$out/app" --strip-components=1

docker run --rm --network sid-dev --env-file .env --user "$(id -u):$(id -g)" -e HOME=/tmp \
    -e R_LIBS_USER=/rlib -v "${XDG_CACHE_HOME:-$HOME/.cache}/sid/r-library:/rlib:z" \
    -v "$PWD/test/parity:/parity:z" -w /parity --entrypoint sh "$R_IMAGE" -c '
    Rscript -e "need <- c(\"DBI\", \"RPostgres\", \"dplyr\", \"jsonlite\");
        missing <- need[!sapply(need, requireNamespace, quietly = TRUE)];
        if (length(missing)) install.packages(missing, lib = \"/rlib\", repos = \"https://cloud.r-project.org\")" &&
    Rscript capture.R data/app data/r_results.json '"${CASES:-1500}"
