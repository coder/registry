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

# Set locale to UTF-8
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# Optional: Update TeX Live packages
# Only enable if you need the latest packages
# RUN tlmgr update --self --all

# Working directory inside the container
WORKDIR /home/texlive

# Icon
COPY icon/ /icon/
