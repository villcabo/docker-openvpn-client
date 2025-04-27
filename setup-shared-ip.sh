# Nombre del servicio en docker-compose
SERVICE_NAME="vpn_container" # <-- reemplaza esto por tu nombre real

echo "[+] Configurando rutas en la máquina local..."

# Obtener IP del contenedor
CONTAINER_IP=$(docker compose inspect "$SERVICE_NAME" \
    --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')

if [ -z "$CONTAINER_IP" ]; then
    echo "[-] No se pudo obtener la IP del contenedor."
    exit 1
fi

echo "[+] IP del contenedor: $CONTAINER_IP"

# Obtener interfaz de red asociada a la IP del contenedor
LOCAL_INTERFACE=$(ip route get "$CONTAINER_IP" | awk '{for(i=1;i<=NF;i++){if($i=="dev"){print $(i+1); exit}}}')

if [ -z "$LOCAL_INTERFACE" ]; then
    echo "[-] No se pudo obtener la interfaz de red local."
    exit 1
fi

echo "[+] Interfaz local: $LOCAL_INTERFACE"

# Iterar sobre todas las subredes de SHARED_IPS
for VPN_SUBNET in $SHARED_IPS; do
    echo "[+] Agregando ruta para $VPN_SUBNET vía $CONTAINER_IP en $LOCAL_INTERFACE..."
    sudo ip route add "$VPN_SUBNET" via "$CONTAINER_IP" dev "$LOCAL_INTERFACE" 2>/dev/null

    # Mostrar la ruta recién agregada
    ip route show | grep "$VPN_SUBNET"
done

echo "[+] Configuración de rutas completada."
