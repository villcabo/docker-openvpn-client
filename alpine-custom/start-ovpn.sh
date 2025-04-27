#!/bin/sh

conf="/vpn.conf"
auth="/vpn.auth"

echo "$OVPN_USERNAME" > $auth
echo "$OVPN_PASSWRD" >> $auth
chmod 0600 $auth

# Launch Openvpn
openvpn --config $conf --auth-user-pass $auth --daemon

# Wait for OpenVPN to establish the connection
while ! ip addr show tun0 | grep -q "inet "; do
    sleep 1
done
echo "➔ OpenVPN connection established."

# Configure NAT for the VPN
iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE
iptables -A FORWARD -i eth0 -o tun0 -j ACCEPT
iptables -A FORWARD -i tun0 -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT
echo "➔ NAT rules applied."
