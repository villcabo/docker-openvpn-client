#!/bin/bash
set -e

VPN_INTERFACE="tun0"           # VPN interface (change if necessary)
VPN_CONF_FILE="/root/vpn.ovpn" # OpenVPN configuration file
VPN_AUTH_FILE="/root/vpn.auth" # OpenVPN authentication file

# Write credentials readable by root only
umask 077
printf '%s\n%s\n' "$OVPN_USERNAME" "$OVPN_PASSWORD" >"$VPN_AUTH_FILE"

# -----------------------------------------------------------------------------------
# Configure the container as a gateway. Rules reference the interface by name,
# so they can be installed before OpenVPN creates it.
echo "Configuring the container as a gateway..."
if ! iptables -t nat -C POSTROUTING -o $VPN_INTERFACE -j MASQUERADE 2>/dev/null; then
    iptables -t nat -A POSTROUTING -o $VPN_INTERFACE -j MASQUERADE
fi
if ! iptables -C FORWARD -i eth0 -o $VPN_INTERFACE -j ACCEPT 2>/dev/null; then
    iptables -A FORWARD -i eth0 -o $VPN_INTERFACE -j ACCEPT
fi
if ! iptables -C FORWARD -i $VPN_INTERFACE -o eth0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null; then
    iptables -A FORWARD -i $VPN_INTERFACE -o eth0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
fi
iptables -t nat -S POSTROUTING
iptables -S FORWARD

# -----------------------------------------------------------------------------------
# OpenVPN replaces this shell as PID 1: its output goes to `docker logs`, it gets
# SIGTERM on `docker stop`, and if it exits the container exits and the restart
# policy brings it back.
#   --keepalive 10 60         detect a dead tunnel and reconnect (server may override)
#   --persist-tun             keep tun0 across reconnects so the rules above stay valid
#   --server-poll-timeout 5   skip unreachable `remote` entries quickly
echo "Starting OpenVPN..."
exec openvpn \
    --config "$VPN_CONF_FILE" \
    --auth-user-pass "$VPN_AUTH_FILE" \
    --keepalive 10 60 \
    --persist-tun \
    --server-poll-timeout 5
