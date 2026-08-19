FROM ghcr.io/astral-sh/uv:latest AS uv

FROM node:24-bookworm-slim

ARG PI_UID=1001
ARG PI_GID=1001

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash \
    build-essential \
    ca-certificates \
    cmake \
    curl \
    file \
    git \
    iproute2 \
    jq \
    less \
    libcairo2-dev \
    libgif-dev \
    libjpeg-dev \
    libpango1.0-dev \
    librsvg2-dev \
    lsof \
    netcat-openbsd \
    ninja-build \
    openssh-client \
    pkg-config \
    procps \
    ripgrep \
    rsync \
    sqlite3 \
    tini \
    tree \
    unzip \
    zip \
  && rm -rf /var/lib/apt/lists/*

COPY --from=uv /uv /uvx /usr/local/bin/

RUN existing_user="$(getent passwd "${PI_UID}" | cut -d: -f1 || true)" \
  && if [ -n "$existing_user" ]; then userdel "$existing_user"; fi \
  && existing_group="$(getent group "${PI_GID}" | cut -d: -f1 || true)" \
  && if [ -n "$existing_group" ]; then groupmod --new-name pi "$existing_group"; else groupadd --gid "${PI_GID}" pi; fi \
  && useradd \
       --uid "${PI_UID}" \
       --gid "${PI_GID}" \
       --create-home \
       --shell /bin/bash \
       pi \
  && mkdir -p /workspace /pi /evolution /home/pi/.pi-agent/bin \
  && chown -R pi:pi /workspace /pi /evolution /home/pi

RUN git config --system --add safe.directory /pi

ENV HOME=/home/pi
ENV PI_CODING_AGENT_DIR=/home/pi/.pi-agent
ENV PATH="/home/pi/.pi-agent/bin:${PATH}"

USER pi
WORKDIR /workspace

ENTRYPOINT ["tini", "--", "/pi/pi-test.sh"]
