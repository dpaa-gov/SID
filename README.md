# SID

Stature identification. SID estimates living stature from skeletal measurements, and tests whether a known stature is consistent with a bone, by regression on reference populations.

- **Estimation:** stature predicted from the measurements of one side, with a prediction interval.
- **Association:** whether a known stature fits the measurements of one bone.

![SID](screenshot.png)

## How it is built

| Part | What it is | Where |
|---|---|---|
| SIDJ | The method: a Julia package with no web or database code | `SIDJ/` |
| Server | A Julia HTTP server: loads reference data, runs SIDJ, serves the page | `server/` |
| Page | Static HTML, CSS and JavaScript on Bootstrap 5 | `web/` |
| Reference data | ARDS, a PostgreSQL database, read-only | external |

Reference data is re-read from ARDS when the page is opened, so anything switched off for stature there (`stature_method`) is gone from the app on the next page load.

## Using the app

1. Choose one or more **reference groups**. Selecting several pools their individuals.
2. **Estimation:** choose the side and type the measurements. **Association:** choose the element and side, and type the known stature and the measurements.
3. Choose the prediction interval and the stature unit.
4. Press **Estimate** or **Associate**.

**Method.** A model sums the measurements it uses and fits ordinary least squares over the reference individuals who have all of them: estimation regresses stature on the sum, association the sum on stature. Intervals are normal-theory prediction intervals. Association's p-value is a two-sided t-test of the specimen's sum against the value predicted at the known stature. A model needs at least 10 reference individuals.

**Estimation results.** Every combination of the entered measurements is a model, one per row, sorted by **PI** (point estimate minus lower bound). The narrowest is selected first; click a row to see its plot. **Copy** copies the selected row.

**Bootstrap.** With it on, models with fewer than 100 individuals get a bootstrap interval; the point estimate stays the least-squares one. Each of 50,000 draws resamples the residuals, refits the line, predicts at the specimen and adds normal noise with the full fit's residual spread; the interval is the percentiles of the draws. The draws are seeded from the model's data, so the same specimen and reference data always give the same interval.

**Units.** Measurements are in millimetres. ARDS holds stature in centimetres; inches are centimetres divided by 2.54.

## Local development

You need Docker, Julia 1.13 and a copy of ARDS running as a container named `ards-db`.

```sh
docker network create sid-dev
docker network connect sid-dev ards-db
```

Create `.env` in the repository root (git-ignored), with no quotes around the values:

```
DB_HOST=ards-db
DB_PORT=5432
DB_NAME=ards
DB_USER=statureid
DB_PASS=<the statureid user's password>
```

Run the server:

```sh
dev/julia.sh -e 'using Pkg; Pkg.instantiate()'                 # first time only
dev/julia.sh -e 'using SIDServer; SIDServer.main()'            # http://127.0.0.1:3838/
```

Changes in `web/` show on reload; changes to Julia code need a restart. `dev/run-image.sh` compiles the Julia side, builds the image and runs it as Atlas does, on http://127.0.0.1:3839/.

### Tests

| What | Command | Needs |
|---|---|---|
| `test/sidj`: the method | `PROJECT=SIDJ dev/julia.sh -e 'using Pkg; Pkg.test()'` | nothing |
| `test/server`: the API | `dev/julia.sh -e 'using Pkg; Pkg.test()'` | ARDS |
| `test/browser`: the page in a headless browser | below | a running server |

```sh
docker run --rm --network host --user "$(id -u):$(id -g)" -e HOME=/tmp \
  -v "$PWD:/app:z" -w /app mcr.microsoft.com/playwright/python:v1.49.0-jammy \
  sh -c "pip install -q playwright==1.49.0 && python test/browser/test_ui.py"
```

The first two run on GitHub for every push; there the server's tests skip the parts that need ARDS.

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| `DB_NAME`, `DB_USER`, `DB_PASS` | required | ARDS database and read-only login |
| `DB_HOST` | `host.docker.internal` | ARDS host |
| `DB_PORT` | `5432` | ARDS port |
| `PORT` | `3838` | Port the server listens on |
| `REFERENCE_MAX_AGE_SECONDS` | `30` | How old the loaded reference data may be before a page load re-reads ARDS |

`server/config/default_references.csv` lists the groups selected when the page opens.

## Deployment

SID is deployed through Atlas, which builds the `Dockerfile` and runs the image.

| Atlas setting | Value |
|---|---|
| Dockerfile path | `Dockerfile` |
| Container port | `3838` |
| Launch path | `/` |
| Health-check path | `/healthz` |
| ARDS database access | Read-only |

The image compiles nothing: the `Dockerfile` downloads the compiled Julia side from the GitHub Release for its tag. So a release must have its asset before that tag is deployed.

### Releasing

1. Set the version in `VERSION` and `ARG SID_VERSION=vX.Y.Z` in the `Dockerfile`. Update the citation here and in `CITATION`. Commit and push.
2. Publish a GitHub Release with tag `vX.Y.Z` (for a pre-release, `vX.Y.Z-alpha.1`, with `X.Y.Z-alpha.1` in `VERSION`).
3. The release workflow checks the versions match the tag, compiles the program, checks the image starts, and attaches `sid-linux-x86_64.tar.gz` to the release.
4. Once the asset is on the release, deploy the tag in Atlas.

If the workflow fails, nothing is attached and a deploy of that tag fails at the download step. Fix the problem and re-run the workflow.

## Open questions

**The bootstrap's noise.** Each bootstrap draw adds noise from a normal distribution whose spread is the full fit's residual standard error. With the small samples the bootstrap is used for, the residuals may not be normal and that spread is only an estimate, yet most of the interval's width comes from it. One effect is an interval narrower than the least-squares one, which allows for the uncertain spread with the t distribution. Drawing the noise from the resampled residuals instead would assume no shape. This is undecided; the procedure is kept as specified until it is.

## Citation

Lynch, J.J. 2026 SID. Stature Identification. Version 1.0.0. Defense POW/MIA Accounting Agency, Offutt AFB, NE.

## License

GNU General Public License v2.0
