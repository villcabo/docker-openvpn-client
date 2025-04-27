#!/bin/sh

VPN_INTERFACE="tun0"      # Interfaz VPN (cambiar si es necesario)
VPN_CONF_FILE="/root/vpn.ovpn" # Archivo de configuración de OpenVPN
VPN_AUTH_FILE="/root/vpn.auth" # Archivo de autenticación de OpenVPN

# -----------------------------------------------------------------------------------
echo "$OVPN_USERNAME" >$VPN_AUTH_FILE
echo "$OVPN_PASSWRD" >>$VPN_AUTH_FILE
# chmod 0600 $auth

# Launch Openvpn
openvpn --config $VPN_CONF_FILE --auth-user-pass $VPN_AUTH_FILE --daemon

# Esperar a que se establezca la interfaz tun0
COUNT=0
while [ $COUNT -lt 30 ]; do
    if ip link show | grep -q $VPN_INTERFACE; then
        echo "➔ Interfaz $VPN_INTERFACE detectada!"
        break
    fi
    echo "➔ Esperando a la interfaz $VPN_INTERFACE... ($COUNT/30)"
    sleep 1
    COUNT=$((COUNT + 1))
done

if ! ip link show | grep -q $VPN_INTERFACE; then
    echo "➔ Error: No se pudo establecer la interfaz tun0 después de 30 segundos"
    echo "Mostrando logs de OpenConnect:"
    cat /var/log/openconnect.log 2>/dev/null || echo "No se encontró el archivo de log"
    exit 1
fi
echo "➔ OpenVPN connection established."

# -----------------------------------------------------------------------------------
# Función para configurar el contenedor (ejecutar DENTRO del contenedor)
echo -e "➔ Configurando el contenedor como puente..."

# Configurar NAT para la VPN
iptables -t nat -A POSTROUTING -o $VPN_INTERFACE -j MASQUERADE
iptables -A FORWARD -i eth0 -o $VPN_INTERFACE -j ACCEPT
iptables -A FORWARD -i $VPN_INTERFACE -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT

echo -e "➔ Contenedor configurado. Reglas aplicadas:"
iptables -t nat -L POSTROUTING -n -v
# -----------------------------------------------------------------------------------
# Start SSH server
# echo -e "[+] Iniciando el servidor SSH..."
# ssh-keygen -A
# exec /usr/sbin/sshd -D -e "$@"

# echo -e "[+] Servidor SSH iniciado."
# -----------------------------------------------------------------------------------
