# Base R Shiny image
FROM rocker/shiny

# Make a directory in the container
RUN mkdir /home/SID

# Install R dependencies
RUN R -e "install.packages(c('dplyr', 'ggplot2', 'shinyalert', 'shinyBS', 'DT', 'gridExtra', 'ggpubr'))"

# Set the working directory
WORKDIR /home/SID

# Copy the Shiny app code
COPY . /home/SID

# Expose the application port
EXPOSE 8180

# Run the R Shiny app
CMD Rscript /home/SID/SID.r
