## SID (Stature Identification) 0.0.3

## Changes

## Installation
```sh
git clone https://github.com/SID
docker build -t statureid .
docker run -d -p 4002:3838 statureid
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

## Citation
Lynch, J.J. 2025 SID. Stature Identification. Version 0.0.3. Defense POW/MIA Accounting Agency, Offutt AFB, NE.

## TODO
1. Add all reference data
2. Fix table select hover color
3. Verify how to sum the measurements for association. is it log sum?
4. Reports need better formatting when using multiple reference sets its out of bounds in the pdf
5. Should stature estimation allow selection of side? We likely don't have enough data yet.
6. Do we need batch processing?