FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive
LABEL maintainer="Bismarck Villca <bismarck.villca@gmail.com>"

# Runtime (used by entrypoint.sh and manage.sh):
# - openvpn: the VPN client
# - iptables: NAT/forwarding rules
# - iproute2: `ip` command
# - procps: `pgrep` (used by manage.sh health check)
# Network troubleshooting from inside the tunnel (`docker exec -it openvpn-client bash`):
# - iputils-ping, traceroute, mtr-tiny: reachability and path
# - telnet, netcat-openbsd: TCP port checks
# - dnsutils: dig / nslookup
# - curl, ca-certificates: HTTP(S) checks
# - tcpdump: see whether packets leave tun0 and whether replies come back
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    openvpn \
    iptables \
    iproute2 \
    procps \
    iputils-ping \
    traceroute \
    mtr-tiny \
    telnet \
    netcat-openbsd \
    dnsutils \
    curl \
    ca-certificates \
    tcpdump \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy files
COPY entrypoint.sh /entrypoint.sh

# Entrypoint
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
