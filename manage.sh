#!/bin/bash

# Colors and icons
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'
UNDERLINE='\033[4m'
# Modern and clean icons (suggested)
SUCCESS_ICON='✔'
WARNING_ICON='⚠️'
ERROR_ICON='❌'
START_ICON='🚀'
STOP_ICON='✔'
READY_ICON='🎉'


# Config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}" )" && pwd)"
cd "$SCRIPT_DIR" || { echo "Failed to change to script directory: $SCRIPT_DIR"; exit 1; }

# Validate root permissions
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERROR: This script must be run as root or with sudo.${NC}"
    exit 1
fi

CONTAINER_NAME="openvpn-client"
ENTRYPOINT_SCRIPT="/entrypoint.sh"
ENV_FILE="${SCRIPT_DIR}/.env"
VPN_VALIDATION_IP="199.3.0.108"

# Load .env if exists
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
    # Si la variable está definida en .env, la usamos
    if [ ! -z "$VPN_VALIDATION_IP_ENV" ]; then
        VPN_VALIDATION_IP="$VPN_VALIDATION_IP_ENV"
    elif [ ! -z "$VPN_VALIDATION_IP" ]; then
        VPN_VALIDATION_IP="$VPN_VALIDATION_IP"
    fi
fi

# Logging functions
log() {
    local type="$1"
    local message="${*:2}"
    case "$type" in
        success)
            echo -e "${GREEN}${message} ${SUCCESS_ICON}${NC}"
            ;;
        warning)
            echo -e "${YELLOW}${message} ${WARNING_ICON}${NC}" >&2
            ;;
        error)
            echo -e "${RED}${message} ${ERROR_ICON}${NC}" >&2
            ;;
        start)
            echo -e "${GREEN}${message} ${START_ICON}${NC}"
            ;;
        stop)
            echo -e "${YELLOW}${message} ${STOP_ICON}${NC}"
            ;;
        ready)
            echo -e "${GREEN}${message} ${READY_ICON}${NC}"
            ;;
        *)
            echo -e "${message}"
            ;;
    esac
}

section() {
    echo -e "\n${BOLD}${UNDERLINE}${BLUE}==> ${1}${NC}\n"
}

show_help() {
    echo -e "${BOLD}Usage:${NC}"
    echo -e "  bash manage.sh --start | -s    Start VPN service and configure routes"
    echo -e "  bash manage.sh --stop  | -k    Stop VPN service and remove routes"
    echo -e "  bash manage.sh --help | -h     Show this help"
}

is_container_running() {
    docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"
}

is_service_running() {
    # Check if OpenVPN process is running
    if ! docker exec "${CONTAINER_NAME}" pgrep -x openvpn >/dev/null 2>&1; then
        return 1
    fi
    # Check if VPN connection is working by pinging a VPN server
    if docker exec "${CONTAINER_NAME}" ping -c 1 -W 3 "$VPN_VALIDATION_IP" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

add_routes() {
    log info "Obtaining container IP and local interface..."
    if [ -z "$SHARED_IPS" ]; then
        log error "SHARED_IPS not defined in .env"
        return 1
    fi
    CONTAINER_IP=$(docker inspect "$CONTAINER_NAME" --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
    if [ -z "$CONTAINER_IP" ]; then
        log error "Could not get container IP"
        return 1
    fi
    LOCAL_INTERFACE=$(ip route get "$CONTAINER_IP" | awk '{for(i=1;i<=NF;i++){if($i=="dev"){print $(i+1); exit}}}')
    log info "Container IP: $CONTAINER_IP"
    log info "Local interface: $LOCAL_INTERFACE"
    log info "Shared subnets: $SHARED_IPS"
    printf "\n${BOLD}%-25s %-18s %-18s %-3s${NC}\n" "Subnet" "Gateway" "Interface" "Status"
    printf "%-25s %-18s %-18s %-3s\n" "-------------------------" "------------------" "------------------" "------"
    for IP in $SHARED_IPS; do
        # Check if route already exists
        if ip route show | grep -q "^$IP "; then
            printf "%-25s %-18s %-18s %s ${WARNING_ICON}\n" "$IP" "$CONTAINER_IP" "$LOCAL_INTERFACE" "Already exists"
        else
            ip route add $IP via $CONTAINER_IP dev $LOCAL_INTERFACE 2>/dev/null
            if [ $? -eq 0 ]; then
                printf "%-25s %-18s %-18s %s ${SUCCESS_ICON}\n" "$IP" "$CONTAINER_IP" "$LOCAL_INTERFACE" "Added"
            else
                printf "%-25s %-18s %-18s %s ${WARNING_ICON}\n" "$IP" "$CONTAINER_IP" "$LOCAL_INTERFACE" "Error"
            fi
        fi
    done
}

delete_routes() {
    if [ -z "$SHARED_IPS" ]; then
        log error "SHARED_IPS not defined in .env"
        return 1
    fi
    for IP in $SHARED_IPS; do
        ip route del $IP 2>/dev/null
        if [ $? -eq 0 ]; then
            log stop "Route removed: $IP"
        else
            log warning "Could not remove route (or does not exist): $IP"
        fi
    done
}

start_vpn() {
    section "[1/3] Container Status"
    if is_container_running; then
        log info "Container '${CONTAINER_NAME}' is already running."
    else
        log start "Starting container..."
        docker compose up -d
        sleep 3
        log info "Container started."
    fi

    section "[2/3] OpenVPN Service Validation"
    log info "Checking OpenVPN service status..."
    if is_service_running; then
        log success "OpenVPN service is active in the container."
    else
        log warning "Container is running but OpenVPN service is not active."
        log info "Trying to start OpenVPN service inside the container..."
        if docker exec -d "${CONTAINER_NAME}" bash "${ENTRYPOINT_SCRIPT}"; then
            log info "Waiting for OpenVPN service to start..."
            local attempts=0
            local max_attempts=10
            while [ $attempts -lt $max_attempts ]; do
                if is_service_running; then
                    log success "OpenVPN service started successfully."
                    break
                else
                    log info "Waiting for OpenVPN service... (attempt $((attempts+1))/$max_attempts)"
                    sleep 2
                    attempts=$((attempts+1))
                fi
            done
            if ! is_service_running; then
                log error "Could not start OpenVPN service."
                exit 1
            fi
        else
            log error "Could not execute entrypoint inside the container."
            exit 1
        fi
    fi

    section "[3/3] Route Configuration"
    log info "Configuring routes for shared subnets..."
    add_routes
    log ""
    log ready "All operations completed successfully!"
    log ""
}

stop_vpn() {
    section "[1/2] Route Removal"
    log info "Removing routes for shared subnets..."
    delete_routes
    section "[2/2] Container Shutdown"
    if is_container_running; then
        log stop "Stopping container..."
        docker stop "$CONTAINER_NAME"
        log info "Container stopped."
    else
        log info "Container is already stopped."
    fi
}

# Main
case "$1" in
    --start|-s)
        start_vpn
        ;;
    --stop|-k)
        stop_vpn
        ;;
    --help|-h|*)
        show_help
        ;;
esac
