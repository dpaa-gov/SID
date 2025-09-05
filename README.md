## SID (Stature Identification) 0.0.4

## Changes

## Installation
```sh
docker build -t statureid .
docker run --restart=on-failure:10 --name=statureid -d -p 4002:3838 statureid
docker network connect app_bridge statureid # add to custom bridge to enable host name resolves between containers; see docker network create my_bridge --driver bridge
```

## R Dependencies
* shiny
* ggplot2
* shinyalert
* dplyr
* shinyBS
* gridExtra
* ggpubr
* DT
* DBI
* RPostgres
* dotenv
* pkgconfig (required for ggplot2)
* Formula (required for ggpubr)

## Citation
Lynch, J.J. 2025 SID. Stature Identification. Version 0.0.4. Defense POW/MIA Accounting Agency, Offutt AFB, NE.

## TODO
1. Verify how to sum the measurements for association. is it log sum?
2. Reports need better formatting when using multiple reference sets its out of bounds in the pdf
3. Should stature estimation allow selection of side? We likely don't have enough data yet.
4. Do we need batch processing?
5. Bootstrapping option for smaller samples.