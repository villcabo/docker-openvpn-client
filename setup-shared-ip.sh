#!/bin/bash

# Colors for logs
GREEN="\033[0;32m"
RED="\033[0;31m"
RESET="\033[0m"
CYAN="\033[0;36m"
BOLD="\033[1m"
NORMAL="\033[0m"
YELLOW="\033[0;33m"

# Detect OS type
OS_TYPE="$(uname -s)"
case "${OS_TYPE}" in
    Linux*)     OS_TYPE="Linux";;
    Darwin*)    OS_TYPE="macOS";;
    *)          OS_TYPE="Unknown";;
esac

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

# Check if OS is supported
if [ "$OS_TYPE" == "Unknown" ]; then
    error_exit "Sistema operativo no soportado: $(uname -s)"
fi

info_message "Sistema operativo detectado: ${GREEN}${BOLD}${OS_TYPE}${NORMAL}${RESET}"

# Function to add route based on OS
add_route() {
    local subnet=$1
    local gateway=$2
    local interface=$3

    if [ "$OS_TYPE" == "Linux" ]; then
        sudo ip route add $subnet via $gateway dev $interface 2>/dev/null
    elif [ "$OS_TYPE" == "macOS" ]; then
        sudo route -n add -net $subnet $gateway 2>/dev/null
    fi
    
    return $?
}

# Function to delete route based on OS
delete_route() {
    local subnet=$1
    local gateway=$2
    local interface=$3

    if [ "$OS_TYPE" == "Linux" ]; then
        sudo ip route del $subnet 2>/dev/null
    elif [ "$OS_TYPE" == "macOS" ]; then
        sudo route -n delete -net $subnet 2>/dev/null
    fi
    
    return $?
}

# Function to check if route exists based on OS
check_route_exists() {
    local subnet=$1
    local gateway=$2

    if [ "$OS_TYPE" == "Linux" ]; then
        ip route show | grep "$subnet" | grep "via $gateway" > /dev/null
    elif [ "$OS_TYPE" == "macOS" ]; then
        netstat -nr | grep "$subnet" | grep "$gateway" > /dev/null
    fi
    
    return $?
}

# Function to get interface for container IP based on OS
get_interface_for_ip() {
    local ip=$1
    local interface=""

    if [ "$OS_TYPE" == "Linux" ]; then
        interface=$(ip route get "$ip" | awk '{for(i=1;i<=NF;i++){if($i=="dev"){print $(i+1); exit}}}')
    elif [ "$OS_TYPE" == "macOS" ]; then
        # On macOS, we determine the interface connected to the Docker network
        # This is typically bridge0 or similar when using Docker Desktop
        interface=$(route -n get "$ip" 2>/dev/null | grep "interface" | awk '{print $2}')
        
        # If not found, try en0 (common for Wi-Fi) or en1 (common for Ethernet)
        if [ -z "$interface" ]; then
            # Check which interface is active
            if ifconfig en0 | grep "status: active" > /dev/null; then
                interface="en0"
            elif ifconfig en1 | grep "status: active" > /dev/null; then
                interface="en1"
            else
                # Find first active interface
                interface=$(ifconfig -a | grep -B 1 "status: active" | grep -v "status" | head -n 1 | cut -d: -f1)
            fi
        fi
    fi

    echo "$interface"
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
        delete_route $IP "" ""
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

    # Get container IP - Same for both OS types
    info_message "Getting IP for container ${GREEN}${BOLD}${CONTAINER_NAME}${NORMAL}${RESET}..."
    CONTAINER_IP=$(docker inspect "$CONTAINER_NAME" --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')

    if [ -z "$CONTAINER_IP" ]; then
        error_exit "Could not get container IP."
    fi

    info_message "Container IP: ${GREEN}${BOLD}${CONTAINER_IP}${NORMAL}${RESET}"
    info_message "Shared subnets (SHARED_IPS): ${GREEN}${BOLD}${SHARED_IPS}${NORMAL}${RESET}"

    # Get network interface associated with container IP
    LOCAL_INTERFACE=$(get_interface_for_ip "$CONTAINER_IP")

    if [ -z "$LOCAL_INTERFACE" ]; then
        error_exit "Could not get local network interface."
    fi

    info_message "Local interface: ${GREEN}${BOLD}${LOCAL_INTERFACE}${NORMAL}${RESET}"

    # Iterate through all SHARED_IPS subnets
    echo -e "➔ --------------------------------------------------------------------------"
    for IP in $SHARED_IPS; do
        # Check if route exists
        check_route_exists "$IP" "$CONTAINER_IP"
        ROUTE_EXISTS=$?
        
        # If route exists, remove it first
        if [ $ROUTE_EXISTS -eq 0 ]; then
            delete_route "$IP" "$CONTAINER_IP" "$LOCAL_INTERFACE"
        fi

        # Add new route
        add_route "$IP" "$CONTAINER_IP" "$LOCAL_INTERFACE"
        if [ $? -eq 0 ]; then
            if [ "$OS_TYPE" == "Linux" ]; then
                success_message "Route added: ${GREEN}${BOLD}${IP} via ${CONTAINER_IP} dev ${LOCAL_INTERFACE}${NORMAL}${RESET}"
            else
                success_message "Route added: ${GREEN}${BOLD}${IP} gateway ${CONTAINER_IP}${NORMAL}${RESET}"
            fi
        else
            if [ "$OS_TYPE" == "Linux" ]; then
                echo -e "${RED}➔ Error adding route: ${BOLD}${IP} via ${CONTAINER_IP} dev ${LOCAL_INTERFACE}${NORMAL}${RESET}"
            else
                echo -e "${RED}➔ Error adding route: ${BOLD}${IP} gateway ${CONTAINER_IP}${NORMAL}${RESET}"
            fi
        fi
    done
    echo -e "➔ --------------------------------------------------------------------------"
    success_message "Route configuration completed."
fi
