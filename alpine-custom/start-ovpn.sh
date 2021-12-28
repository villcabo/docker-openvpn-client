#!/bin/sh

conf="/vpn.conf" auth="/vpn.auth" origconf="/conf.ovpn"

if [ -f "$origconf" ];
then
    if [ -z ${OVPN_USERNAME+x} ];
    then
        echo "No username set..."
        exit 1
    fi
    if [ -z ${OVPN_PASSWORD+x} ];
    then
        echo "No password set..."
        exit 1
    fi
else
    echo "Please provide a configuration file"
    exit 1
fi

cat $origconf > $conf
echo "auth-user-pass $auth" >> $conf
echo "$OVPN_USERNAME" > $auth
echo "$OVPN_PASSWORD" >> $auth
chmod 0600 $auth

# Launch Openvpn

openvpn --config $conf

# if we are here, it is because something wen terribly wrong...
echo "Failed..."
echo "Usage: docker run -it -e \"OVPN_USERNAME=your-username-here\" -e \"OVPN_PASSWORD=your-password-here\" -v /path/to/conf.ovpn:/conf.ovpn --cap-add=NET_ADMIN --device /dev/net/tun --name vpn villcabo/ovpn-client"
exit 1