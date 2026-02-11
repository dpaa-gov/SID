# SID 0.1.0

![Build](https://img.shields.io/badge/build-passing-brightgreen)
![R](https://img.shields.io/badge/R-4.x-blue)
![Status](https://img.shields.io/badge/status-beta%20testing%20needed-yellow)

Stature estimation and association application built with R/Shiny. SID uses regression-based methods to estimate stature from skeletal measurements and assess stature association strength against reference populations.

**Key Features:**
- **Stature Estimation** — predict living stature from skeletal measurements using OLS regression
- **Bootstrap Prediction Intervals** — optional bootstrap resampling (5000 iterations) for small reference samples (n < 100), applied per-combination with results flagged in the output table
- **Stature Association** — evaluate whether a known stature is consistent with skeletal measurements
- Interactive Plotly visualizations with prediction intervals
- PostgreSQL-backed reference populations (ARDS)

## Architecture

| Layer | Technology |
|-------|------------|
| Frontend | R/Shiny UI |
| Backend (statistical) | R |
| Database | PostgreSQL (ARDS) |
| Deployment | Docker (rocker/shiny) |

## Prerequisites

- Docker
- A running PostgreSQL instance with the ARDS osteometry schema
- A `.env` file inside `SID/` with database credentials:
  ```
  DB_HOST=<host>
  DB_PORT=<port>
  DB_USER=<user>
  DB_PASS=<password>
  ```

## Installation

```sh
git clone https://github.com/dpaa-gov/SID
cd SID
docker build -t statureid .
docker run --restart=on-failure:10 --name=statureid -d -p 4002:3838 statureid
docker network connect app_bridge statureid
```

The app will be available at `http://localhost:4002/SID`.

## Local Development (Without Docker)

### Requirements

- R 4.x with packages listed in [Dependencies](#dependencies)
- PostgreSQL client library (`libpq-dev` on Debian/Ubuntu)
- `.env` file in `SID/` with DB credentials (see [Prerequisites](#prerequisites))

### Run

```sh
Rscript start_dev.R
```

The app will open at `http://127.0.0.1:4002`.

## Project Structure

```
SID/
├── Dockerfile
├── SID/                   # Shiny application
│   ├── server.r           # Server entry point
│   ├── ui.r               # UI entry point
│   ├── R/                 # Analytical R functions
│   ├── server/            # Server modules (reference, estimation, association)
│   ├── ui/                # UI modules
│   └── www/               # Static assets (CSS, images)
└── start_dev.R            # Local development launcher
```

## Dependencies

### R
| Package | Purpose |
|---------|---------|
| shiny | Web framework |
| plotly | Interactive plots |
| DT | Interactive data tables |
| dplyr | Data manipulation |
| shinyalert | Alert dialogs |
| DBI | Database interface |
| RPostgres | PostgreSQL driver |
| dotenv | Environment variable loading |

## Bootstrap Methodology

When enabled, bootstrap prediction intervals replace the standard normal-theory intervals from `predict(lm, interval="prediction")` for reference samples with **n < 100**. This is applied **per-combination** — within a single estimation run, large-sample combinations use OLS while small-sample combinations use bootstrap. The results table `method` column flags which approach was used.

**Algorithm** (per combination where n < 100):
1. **Point estimate** from OLS on the full (non-resampled) reference data — not the bootstrap mean, so the estimate is identical whether bootstrap is on or off and avoids contamination from the `rnorm` noise draws
2. Fit full model once to obtain fitted values (ŷᵢ) and residuals (eᵢ = yᵢ − ŷᵢ)
3. For each of 5,000 bootstrap iterations:
   - Resample **residuals** with replacement (not cases — avoids σ̂ bias from duplicate observations)
   - Create synthetic response: y*ᵢ = ŷᵢ + e*ᵢ
   - Refit regression on (X, y*) using `lm.fit()` (no formula overhead)
   - Predict at the specimen value
   - Draw from `N(ŷ, σ)` using the full-model residual SD to incorporate observation scatter
4. Derive prediction interval bounds from the percentile method on the 5,000 draws

The residual noise draw in step 2 is what distinguishes a **prediction interval** from a confidence interval for the mean — it captures both coefficient uncertainty and the irreducible scatter of individual observations around the regression line.

## Acknowledgments

- **Alex Moore** — UI styling suggestions and design inspiration

## Citation

Lynch, J.J. 2026 SID. Stature Identification. Version 0.1.0. Defense POW/MIA Accounting Agency, Offutt AFB, NE.

## TODO

1. Fix data table selected row color

## License

GNU General Public License v2.0 — see [LICENSE](LICENSE) for details.