## SID (Stature Identification) 0.0.4

## Changes

## Installation
```sh
git clone https://github.com/jjlynch2/SID
docker build -t statureid .
docker run --restart=on-failure:10 -d -p 4002:3838 statureid
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

## Citation
Lynch, J.J. 2025 SID. Stature Identification. Version 0.0.3. Defense POW/MIA Accounting Agency, Offutt AFB, NE.

## TODO
1. Verify how to sum the measurements for association. is it log sum?
2. Reports need better formatting when using multiple reference sets its out of bounds in the pdf
3. Should stature estimation allow selection of side? We likely don't have enough data yet.
4. Do we need batch processing?
5. Bootstrapping option for smaller samples.
6. Update for the collection names inh ARDS