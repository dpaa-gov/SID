# Base R Shiny image
FROM rocker/shiny:4.4.3

# Copy shiny-server config file
COPY shiny-server.conf /etc/shiny-server/shiny-server.conf

# Delete example apps from shiny-server
RUN rm -rf /srv/shiny-server/*

# Copy the Shiny app code
COPY SID /srv/shiny-server/SID

# Install R dependencies
RUN R -e "install.packages(c('dplyr', 'ggplot2', 'shinyalert', 'shinyBS', 'DT', 'gridExtra', 'ggpubr'))"

# Change ownership of app directory and home directory recursively
RUN chown -R shiny /srv/shiny-server/SID &&\
    chown -R shiny /home/shiny

# Expose the application port
EXPOSE 3838

# Start shiny-server
CMD shiny-server