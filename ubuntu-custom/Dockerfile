FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive
LABEL maintainer="Bismarck Villca <bismarck.villca@gmail.com>"

# Install only what entrypoint.sh actually uses:
# - openvpn: the VPN client
# - iptables: NAT/forwarding rules
# - iproute2: `ip` command
# - procps: `pgrep` (used by manage.sh health check)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    openvpn \
    iptables \
    iproute2 \
    procps \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy files
COPY entrypoint.sh /entrypoint.sh

# Entrypoint
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
