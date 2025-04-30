#!/bin/bash

# Colors for logs
GREEN="\033[0;32m"
RED="\033[0;31m"
RESET="\033[0m"
CYAN="\033[0;36m"
BOLD="\033[1m"
NORMAL="\033[0m"
YELLOW="\033[0;33m"

# Function to print error messages and exit
error_exit() {
    echo -e "➔ ${RED}${BOLD}$1${NORMAL}${RESET} ❌"
    exit 1
}

error_message() {
    echo -e "➔ ${RED}${BOLD}$1${NORMAL}${RESET} ❌"
}

# Function to print info messages
info_message() {
    echo -e "➔ $1"
}

# Function to print success messages
success_message() {
    echo -e "➔ ${GREEN}${BOLD}$1${NORMAL}${RESET} \t🚀"
}

warning_message() {
    echo -e "➔ ${YELLOW}${BOLD}$1${NORMAL}${RESET} \t⚠️"
}

# Check if running with delete parameter
DELETE_MODE=false
for arg in "$@"; do
    if [ "$arg" == "-del" ] || [ "$arg" == "--delete" ]; then
        DELETE_MODE=true
        break
    fi
done

# Read variables from .env file
ENV_FILE="$(dirname "$0")/.env"
if [ ! -f "$ENV_FILE" ]; then
    error_exit ".env file does not exist in script directory"
fi

# Load variables from .env
source "$ENV_FILE"

# Process according to mode (delete or configure)
if [ "$DELETE_MODE" = true ]; then
    # DELETE MODE
    # In delete mode, we only need SHARED_IPS
    if [ -z "$SHARED_IPS" ]; then
        error_exit "SHARED_IPS variable not defined in .env"
    fi
    
    echo -e "➔ =========================================================================="
    info_message "Removing previously configured routes ⏳..."
    info_message "Shared subnets (SHARED_IPS): ${GREEN}${BOLD}${SHARED_IPS}${NORMAL}${RESET}"
    
    # Iterate through all SHARED_IPS subnets and remove them
    echo -e "➔ --------------------------------------------------------------------------"
    for IP in $SHARED_IPS; do
        # Remove route directly without container verification
        sudo ip route del $IP 2>/dev/null
        if [ $? -eq 0 ]; then
            info_message "Route removed: ${YELLOW}${BOLD}${IP}${NORMAL}${RESET}"
        else
            warning_message "Route does not exist or couldn't be removed: ${BOLD}${IP}${NORMAL}${RESET}"
        fi
    done
    echo -e "➔ --------------------------------------------------------------------------"
    success_message "Route removal completed."
else
    # CONFIGURATION MODE
    # Verify required variables for configuration
    if [ -z "$CONTAINER_NAME" ]; then
        error_exit "CONTAINER_NAME variable not defined in .env"
    fi

    if [ -z "$SHARED_IPS" ]; then
        error_exit "SHARED_IPS variable not defined in .env"
    fi

    echo -e "➔ =========================================================================="
    info_message "Configuring routes on local machine ⏳..."

    # Get container IP
    info_message "Getting IP for container ${GREEN}${BOLD}${CONTAINER_NAME}${NORMAL}${RESET}..."
    CONTAINER_IP=$(docker inspect "$CONTAINER_NAME" --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')

    if [ -z "$CONTAINER_IP" ]; then
        error_exit "Could not get container IP."
    fi

    info_message "Container IP: ${GREEN}${BOLD}${CONTAINER_IP}${NORMAL}${RESET}"
    info_message "Shared subnets (SHARED_IPS): ${GREEN}${BOLD}${SHARED_IPS}${NORMAL}${RESET}"

    # Get network interface associated with container IP
    LOCAL_INTERFACE=$(ip route get "$CONTAINER_IP" | awk '{for(i=1;i<=NF;i++){if($i=="dev"){print $(i+1); exit}}}')

    if [ -z "$LOCAL_INTERFACE" ]; then
        error_exit "Could not get local network interface."
    fi

    info_message "Local interface: ${GREEN}${BOLD}${LOCAL_INTERFACE}${NORMAL}${RESET}"

    # Iterate through all SHARED_IPS subnets
    echo -e "➔ --------------------------------------------------------------------------"
    for IP in $SHARED_IPS; do
        # Check if route exists
        EXISTING_ROUTE=$(ip route show | grep "$IP" | grep "via $CONTAINER_IP")
        
        # If route exists, remove it first
        if [ -n "$EXISTING_ROUTE" ]; then
            sudo ip route del $IP via $CONTAINER_IP dev $LOCAL_INTERFACE 2>/dev/null
        fi

        # Add new route
        sudo ip route add $IP via $CONTAINER_IP dev $LOCAL_INTERFACE 2>/dev/null
        if [ $? -eq 0 ]; then
            success_message "Route added: ${GREEN}${BOLD}${IP} via ${CONTAINER_IP} dev ${LOCAL_INTERFACE}${NORMAL}${RESET}"
        else
            echo -e "${RED}➔ Error adding route: ${BOLD}${IP} via ${CONTAINER_IP} dev ${LOCAL_INTERFACE}${NORMAL}${RESET}"
        fi
    done
    echo -e "➔ --------------------------------------------------------------------------"
    success_message "Route configuration completed."
fi
