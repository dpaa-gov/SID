## SID (Stature Identification) 0.0.2

## Changes

## Docker Container
`docker build -t statureid .`

## Start Container
`docker run -p 8180:8180 statureid`

## R Dependencies
* shiny
* ggplot2
* shinyalert
* dplyr
* shinyBS
* gridExtra
* ggpubr
* DT

## TODO
1. Add all reference data
2. Fix table select hover color
3. Verify how to sum the measurements for association. is it log sum?
4. Reports need better formatting when using multiple reference sets its out of bounds in the pdf
5. Should stature estimation allow selection of side? We likely don't have enough data yet.