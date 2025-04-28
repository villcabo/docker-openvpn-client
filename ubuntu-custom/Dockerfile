FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
LABEL maintainer="Bismarck Villca <bismarck.villca@gmail.com>"

# Install dependencies
RUN apt-get update && \
    apt-get install -y \
    openvpn \
    iptables \
    net-tools \
    iproute2 \
    iputils-ping \
    curl \
    dnsutils \
    procps \
    sudo \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy files
COPY entrypoint.sh /entrypoint.sh

# Entrypoint
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
