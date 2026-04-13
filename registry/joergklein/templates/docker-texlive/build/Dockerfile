# syntax=docker/dockerfile:1

ARG TEXLIVE_VERSION=latest
FROM registry.gitlab.com/islandoftex/images/texlive:${TEXLIVE_VERSION}

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
  curl \
  inkscape \
  unzip \
  vim \
  wget \
 && rm -rf /var/lib/apt/lists/*

# UTF-8
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

RUN useradd -m -s /bin/bash texlive || true

ENV HOME=/home/texlive

RUN chown -R texlive:texlive /home/texlive

USER texlive

WORKDIR /home/texlive

RUN mkdir -p /home/texlive/texmf/web2c \
 && echo "save_size = 300000" >/home/texlive/texmf/web2c/texmf.cnf \
 && chown -R texlive:texlive /home/texlive/texmf

# Icon
COPY icon/ /icon/

  vim \
  wget \
 && rm -rf /var/lib/apt/lists/*
