ARG RSTUDIO_VERSION=4
FROM rocker/rstudio:${RSTUDIO_VERSION}

RUN apt-get update \
 && apt-get install -y \
  curl \
  cmake \
 && rm -rf /var/lib/apt/lists/*

RUN R -e "install.packages('rmarkdown')"

RUN echo "auth-minimum-user-id=0" >>/etc/rstudio/rserver.conf
