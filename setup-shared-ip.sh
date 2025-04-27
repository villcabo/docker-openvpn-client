# Nombre del contenedor en Docker
CONTAINER_NAME="vpn_sintesis" # Reemplaza esto por tu nombre real

echo "➔ Configurando rutas en la máquina local..."

# Obtener IP del contenedor
CONTAINER_IP=$(docker inspect "$CONTAINER_NAME" \
    --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')

if [ -z "$CONTAINER_IP" ]; then
    echo "➔ No se pudo obtener la IP del contenedor."
    exit 1
fi

echo "➔ IP del contenedor: $CONTAINER_IP"

# Obtener la variable SHARED_IPS desde el contenedor
SHARED_IPS=$(docker exec -it "$CONTAINER_NAME" env | grep '^SHARED_IPS=' | cut -d'=' -f2)

if [ -z "$SHARED_IPS" ]; then
    echo "➔ No se pudo obtener la variable SHARED_IPS del contenedor."
    exit 1
fi

echo "➔ Subredes compartidas (SHARED_IPS): $SHARED_IPS"

# Obtener interfaz de red asociada a la IP del contenedor
LOCAL_INTERFACE=$(ip route get "$CONTAINER_IP" | awk '{for(i=1;i<=NF;i++){if($i=="dev"){print $(i+1); exit}}}')

if [ -z "$LOCAL_INTERFACE" ]; then
    echo "➔ No se pudo obtener la interfaz de red local."
    exit 1
fi

echo "➔ Interfaz local: $LOCAL_INTERFACE"

# Iterar sobre todas las subredes de SHARED_IPS
for VPN_SUBNET in $SHARED_IPS; do
    # Verificar si la ruta ya existe
    EXISTING_ROUTE=$(ip route show | grep "$VPN_SUBNET" | grep "via $CONTAINER_IP dev $LOCAL_INTERFACE")
    if [ -n "$EXISTING_ROUTE" ]; then
        echo "➔ La ruta para $VPN_SUBNET ya existe. Eliminándola..."
        sudo ip route del "$VPN_SUBNET" via "$CONTAINER_IP" dev "$LOCAL_INTERFACE" 2>/dev/null
    fi

    # Agregar la nueva ruta
    echo "➔ Agregando ruta para $VPN_SUBNET vía $CONTAINER_IP en $LOCAL_INTERFACE..."
    sudo ip route add "$VPN_SUBNET" via "$CONTAINER_IP" dev "$LOCAL_INTERFACE" 2>/dev/null

    # Mostrar la ruta recién agregada
    ip route show | grep "$VPN_SUBNET"
done

echo "➔ Configuración de rutas completada."
