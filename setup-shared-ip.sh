# Nombre del contenedor en Docker
CONTAINER_NAME="ovpn-client" # Reemplaza esto por tu nombre real
SHARED_IPS="10.10.0.0/24 10.20.0.0/24" # Reemplaza esto por tus IPs reales

# Colores para los logs
GREEN="\033[0;32m"
RED="\033[0;31m"
RESET="\033[0m"
CYAN="\033[0;36m"
BOLD="\033[1m"
NORMAL="\033[0m"
YELLOW="\033[0;33m"


echo -e "➔ =========================================================================="
echo -e "➔ Configurando rutas en la máquina local ⏳..."

# Obtener IP del contenedor
CONTAINER_IP=$(docker inspect "$CONTAINER_NAME" --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')

echo -e "➔ Obteniendo IP del contenedor ${GREEN}${BOLD}${CONTAINER_NAME}${NORMAL}${RESET}..."
if [ -z "$CONTAINER_IP" ]; then
    echo -e "➔ ${RED}${BOLD}No se pudo obtener la IP del contenedor.${NORMAL}${RESET} ❌"
    exit 1
fi

echo -e "➔ IP del contenedor: ${GREEN}${BOLD}${CONTAINER_IP}${NORMAL}${RESET}"

echo -e "➔ Subredes compartidas (SHARED_IPS): ${GREEN}${BOLD}${SHARED_IPS}${NORMAL}${RESET}"

# Obtener interfaz de red asociada a la IP del contenedor
LOCAL_INTERFACE=$(ip route get "$CONTAINER_IP" | awk '{for(i=1;i<=NF;i++){if($i=="dev"){print $(i+1); exit}}}')

if [ -z "$LOCAL_INTERFACE" ]; then
    echo -e "➔ ${RED}${BOLD}No se pudo obtener la interfaz de red local.${NORMAL}${RESET} ❌"
    exit 1
fi

echo -e "➔ Interfaz local: ${GREEN}${BOLD}${LOCAL_INTERFACE}${NORMAL}${RESET}"

# Iterar sobre todas las subredes de SHARED_IPS
echo -e "➔ --------------------------------------------------------------------------"
for IP in $SHARED_IPS; do
    # Verificar si la ruta ya existe
    EXISTING_ROUTE=$(ip route show | grep "$IP" | grep "via $CONTAINER_IP")
    if [ -n "$EXISTING_ROUTE" ]; then
        sudo ip route del $IP via $CONTAINER_IP dev $LOCAL_INTERFACE 2>/dev/null
        # echo -e "${YELLOW}➔ Ruta eliminada: ${BOLD}${IP} via ${CONTAINER_IP} dev ${LOCAL_INTERFACE}${NORMAL}${RESET}"
    fi

    # Agregar la nueva ruta
    sudo ip route add $IP via $CONTAINER_IP dev $LOCAL_INTERFACE 2>/dev/null

    # Mostrar la ruta recién agregada
    echo -e "${CYAN}➔ Ruta agregada: ${GREEN}${BOLD}${IP} via ${CONTAINER_IP} dev ${LOCAL_INTERFACE}${NORMAL}${RESET}"
done
echo -e "➔ --------------------------------------------------------------------------"
echo -e "➔ ${GREEN}${BOLD}Configuración de rutas completada.${NORMAL}${RESET} 🚀"
