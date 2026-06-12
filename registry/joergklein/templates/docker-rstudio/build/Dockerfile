# syntax=docker/dockerfile:1

ARG RSTUDIO_VERSION=latest
FROM rocker/rstudio:${RSTUDIO_VERSION}

USER root

RUN apt-get update && apt-get install -y \
    curl \
    git \
    sudo \
    procps \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp

# TeX Live Installer
RUN wget https://mirror.ctan.org/systems/texlive/tlnet/install-tl-unx.tar.gz \
 && tar -xzf install-tl-unx.tar.gz \
 && cd install-tl-* \
 && echo "selected_scheme scheme-medium" > profile.txt \
 && ./install-tl -profile profile.txt \
 && cd / \
 && rm -rf /tmp/install-tl-* /tmp/install-tl-unx.tar.gz

# Set PATH
ENV PATH="/usr/local/texlive/2026/bin/x86_64-linux:${PATH}"

# Optional: LuaLaTeX-Pakete
RUN tlmgr install unicode-math luacode

# R Pakete
RUN R -e "install.packages(c('rmarkdown'), repos='https://cloud.r-project.org')"

# RStudio Konfiguration (kein Login nötig)
RUN echo "auth-minimum-user-id=0" >> /etc/rstudio/rserver.conf

# Environment
ENV HOME=/home/rstudio \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

RUN chown -R rstudio:rstudio /home/rstudio

USER rstudio
WORKDIR /home/rstudio
