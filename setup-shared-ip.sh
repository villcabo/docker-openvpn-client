#!/bin/bash

# Colores para los logs
GREEN="\033[0;32m"
RED="\033[0;31m"
RESET="\033[0m"
CYAN="\033[0;36m"
BOLD="\033[1m"
NORMAL="\033[0m"
YELLOW="\033[0;33m"

# Función para imprimir mensajes de error y salir
error_exit() {
    echo -e "➔ ${RED}${BOLD}$1${NORMAL}${RESET} ❌"
    exit 1
}

error_message() {
    echo -e "➔ ${RED}${BOLD}$1${NORMAL}${RESET} ❌"
}

# Función para imprimir mensajes de información
info_message() {
    echo -e "➔ $1"
}

# Función para imprimir mensajes de éxito
success_message() {
    echo -e "➔ ${GREEN}${BOLD}$1${NORMAL}${RESET} \t🚀"
}

warning_message() {
    echo -e "➔ ${YELLOW}${BOLD}$1${NORMAL}${RESET} \t⚠️"
}

# Verificar si se ejecuta con parámetro de eliminación
DELETE_MODE=false
for arg in "$@"; do
    if [ "$arg" == "-del" ] || [ "$arg" == "--delete" ]; then
        DELETE_MODE=true
        break
    fi
done

# Leer variables del archivo .env
ENV_FILE="$(dirname "$0")/.env"
if [ ! -f "$ENV_FILE" ]; then
    error_exit "El archivo .env no existe en la ruta del script"
fi

# Cargar variables desde .env
source "$ENV_FILE"

# Procesar según el modo (eliminación o configuración)
if [ "$DELETE_MODE" = true ]; then
    # MODO DE ELIMINACIÓN
    # En modo eliminación, solo necesitamos SHARED_IPS
    if [ -z "$SHARED_IPS" ]; then
        error_exit "La variable SHARED_IPS no está definida en .env"
    fi
    
    echo -e "➔ =========================================================================="
    info_message "Eliminando rutas previamente configuradas ⏳..."
    info_message "Subredes compartidas (SHARED_IPS): ${GREEN}${BOLD}${SHARED_IPS}${NORMAL}${RESET}"
    
    # Iterar sobre todas las subredes de SHARED_IPS y eliminarlas
    echo -e "➔ --------------------------------------------------------------------------"
    for IP in $SHARED_IPS; do
        # Eliminar la ruta directamente sin verificar el contenedor
        sudo ip route del $IP 2>/dev/null
        if [ $? -eq 0 ]; then
            info_message "Ruta eliminada: ${YELLOW}${BOLD}${IP}${NORMAL}${RESET}"
        else
            warning_message "No existe o no se pudo eliminar la ruta: ${BOLD}${IP}${NORMAL}${RESET}"
        fi
    done
    echo -e "➔ --------------------------------------------------------------------------"
    success_message "Eliminación de rutas completada."
else
    # MODO DE CONFIGURACIÓN
    # Verificar las variables necesarias para la configuración
    if [ -z "$CONTAINER_NAME" ]; then
        error_exit "La variable CONTAINER_NAME no está definida en .env"
    fi

    if [ -z "$SHARED_IPS" ]; then
        error_exit "La variable SHARED_IPS no está definida en .env"
    fi

    echo -e "➔ =========================================================================="
    info_message "Configurando rutas en la máquina local ⏳..."

    # Obtener IP del contenedor
    info_message "Obteniendo IP del contenedor ${GREEN}${BOLD}${CONTAINER_NAME}${NORMAL}${RESET}..."
    CONTAINER_IP=$(docker inspect "$CONTAINER_NAME" --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')

    if [ -z "$CONTAINER_IP" ]; then
        error_exit "No se pudo obtener la IP del contenedor."
    fi

    info_message "IP del contenedor: ${GREEN}${BOLD}${CONTAINER_IP}${NORMAL}${RESET}"
    info_message "Subredes compartidas (SHARED_IPS): ${GREEN}${BOLD}${SHARED_IPS}${NORMAL}${RESET}"

    # Obtener interfaz de red asociada a la IP del contenedor
    LOCAL_INTERFACE=$(ip route get "$CONTAINER_IP" | awk '{for(i=1;i<=NF;i++){if($i=="dev"){print $(i+1); exit}}}')

    if [ -z "$LOCAL_INTERFACE" ]; then
        error_exit "No se pudo obtener la interfaz de red local."
    fi

    info_message "Interfaz local: ${GREEN}${BOLD}${LOCAL_INTERFACE}${NORMAL}${RESET}"

    # Iterar sobre todas las subredes de SHARED_IPS
    echo -e "➔ --------------------------------------------------------------------------"
    for IP in $SHARED_IPS; do
        # Verificar si la ruta existe
        EXISTING_ROUTE=$(ip route show | grep "$IP" | grep "via $CONTAINER_IP")
        
        # Si la ruta ya existe, eliminarla primero
        if [ -n "$EXISTING_ROUTE" ]; then
            sudo ip route del $IP via $CONTAINER_IP dev $LOCAL_INTERFACE 2>/dev/null
        fi

        # Agregar la nueva ruta
        sudo ip route add $IP via $CONTAINER_IP dev $LOCAL_INTERFACE 2>/dev/null
        if [ $? -eq 0 ]; then
            success_message "Ruta agregada: ${GREEN}${BOLD}${IP} via ${CONTAINER_IP} dev ${LOCAL_INTERFACE}${NORMAL}${RESET}"
        else
            echo -e "${RED}➔ Error al agregar ruta: ${BOLD}${IP} via ${CONTAINER_IP} dev ${LOCAL_INTERFACE}${NORMAL}${RESET}"
        fi
    done
    echo -e "➔ --------------------------------------------------------------------------"
    success_message "Configuración de rutas completada."
fi
