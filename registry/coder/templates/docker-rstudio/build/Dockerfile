ARG RSTUDIO_VERSION=4
FROM rocker/rstudio:${RSTUDIO_VERSION}

RUN apt-get update \
 && apt-get install -y \
  curl \
  cmake \
 && rm -rf /var/lib/apt/lists/*
