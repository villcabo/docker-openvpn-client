# Nombre del contenedor en Docker
CONTAINER_NAME="vpn_sintesis" # Reemplaza esto por tu nombre real

# Colores para los logs
GREEN="\033[0;32m"
RED="\033[0;31m"
RESET="\033[0m"
CYAN="\033[0;36m"
BOLD=$(tput bold)
NORMAL=$(tput sgr0)

echo -e "➔ Configurando rutas en la máquina local ⏳..."

# Obtener IP del contenedor
CONTAINER_IP=$(docker inspect "$CONTAINER_NAME" --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')

echo -e "➔ Obteniendo IP del contenedor ${GREEN}${BOLD}${CONTAINER_NAME}${NORMAL}${RESET}... ⏳"
if [ -z "$CONTAINER_IP" ]; then
    echo -e "➔ ${RED}${BOLD}No se pudo obtener la IP del contenedor.${NORMAL}${RESET} ❌"
    exit 1
fi

echo -e "➔ IP del contenedor: ${GREEN}${BOLD}${CONTAINER_IP}${NORMAL}${RESET}"

# Obtener la variable SHARED_IPS desde el contenedor
SHARED_IPS=$(docker exec -it "$CONTAINER_NAME" env | grep '^SHARED_IPS=' | cut -d'=' -f2)

if [ -z "$SHARED_IPS" ]; then
    echo -e "➔ ${RED}${BOLD}No se pudo obtener la variable SHARED_IPS del contenedor.${NORMAL}${RESET} ❌"
    exit 1
fi

echo -e "➔ Subredes compartidas (SHARED_IPS): ${GREEN}${BOLD}${SHARED_IPS}${NORMAL}${RESET}"

# Obtener interfaz de red asociada a la IP del contenedor
LOCAL_INTERFACE=$(ip route get "$CONTAINER_IP" | awk '{for(i=1;i<=NF;i++){if($i=="dev"){print $(i+1); exit}}}')

if [ -z "$LOCAL_INTERFACE" ]; then
    echo -e "➔ ${RED}${BOLD}No se pudo obtener la interfaz de red local.${NORMAL}${RESET} ❌"
    exit 1
fi

echo -e "➔ Interfaz local: ${GREEN}${BOLD}${LOCAL_INTERFACE}${NORMAL}${RESET}"

# Iterar sobre todas las subredes de SHARED_IPS
for VPN_SUBNET in $SHARED_IPS; do
    # Verificar si la ruta ya existe
    EXISTING_ROUTE=$(ip route show | grep "$VPN_SUBNET" | grep "via $CONTAINER_IP dev $LOCAL_INTERFACE")
    if [ -n "$EXISTING_ROUTE" ]; then
        echo -e "${RED}➔ La ruta para ${BOLD}${VPN_SUBNET}${NORMAL}${RED} ya existe. Eliminándola... ${RESET}"
        sudo ip route del "$VPN_SUBNET" via "$CONTAINER_IP" dev "$LOCAL_INTERFACE" 2>/dev/null
    fi

    # Agregar la nueva ruta
    sudo ip route add "$VPN_SUBNET" via "$CONTAINER_IP" dev "$LOCAL_INTERFACE" 2>/dev/null

    # Mostrar la ruta recién agregada
    echo -e "${CYAN}➔ Ruta agregada: ${GREEN}${BOLD}${VPN_SUBNET} via ${CONTAINER_IP} dev ${LOCAL_INTERFACE}${NORMAL}${RESET}"
done

echo -e "➔ ${GREEN}${BOLD}Configuración de rutas completada.${NORMAL}${RESET} 🚀"
