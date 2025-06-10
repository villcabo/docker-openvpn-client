#!/bin/bash
set -e

echo "Killing any existing openvpn processes (if any)..."
pkill openvpn 2>/dev/null || true

VPN_INTERFACE="tun0"           # VPN interface (change if necessary)
VPN_CONF_FILE="/root/vpn.ovpn" # OpenVPN configuration file
VPN_AUTH_FILE="/root/vpn.auth" # OpenVPN authentication file

# Write credentials to the authentication file
echo "$OVPN_USERNAME" >$VPN_AUTH_FILE
echo "$OVPN_PASSWORD" >>$VPN_AUTH_FILE

# Launch OpenVPN
echo "Configuring OpenVPN..."
openvpn --config $VPN_CONF_FILE --auth-user-pass $VPN_AUTH_FILE --daemon

COUNT=0
while [ $COUNT -lt 30 ]; do
    if ip link show | grep -q $VPN_INTERFACE; then
        echo "VPN interface $VPN_INTERFACE detected!"
        break
    fi
    echo "Waiting for VPN interface $VPN_INTERFACE... ($COUNT/30)"
    sleep 1
    COUNT=$((COUNT + 1))
done

if ! ip link show | grep -q $VPN_INTERFACE; then
    echo "Error: Unable to establish VPN interface $VPN_INTERFACE after 30 seconds."
    echo "Displaying OpenConnect logs:"
    cat /var/log/openconnect.log 2>/dev/null || echo "Log file not found."
    exit 1
fi
echo "OpenVPN connection established."

# -----------------------------------------------------------------------------------
# Function to configure the container (run INSIDE the container)
echo ""
echo "Configuring the container as a bridge..."

# Configure NAT for the VPN
# Only add MASQUERADE rule if it does not already exist
if ! iptables -t nat -C POSTROUTING -o $VPN_INTERFACE -j MASQUERADE 2>/dev/null; then
    iptables -t nat -A POSTROUTING -o $VPN_INTERFACE -j MASQUERADE
fi
iptables -A FORWARD -i eth0 -o $VPN_INTERFACE -j ACCEPT
iptables -A FORWARD -i $VPN_INTERFACE -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT

echo "Container configured. Rules applied:"
iptables -t nat -L POSTROUTING -n -v

# -----------------------------------------------------------------------------------
# Keep the container running
echo ""
echo "VPN connected and configured. Keeping the container active."
tail -f /dev/null
