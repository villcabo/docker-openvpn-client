#!/bin/bash

# Colors and icons
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'
UNDERLINE='\033[4m'
GRAY='\033[0;37m'
# Modern and clean icons
ICON_SUCCESS='✔'
ICON_WARNING='⚠️'
ICON_ERROR='❌'
ICON_START='🚀'
ICON_READY='🎉'
ICON_LOADING='⏳'


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
VPN_STARTUP_MESSAGE="VPN connected and configured. Keeping the container active."
DEBUG_MODE="false"

# Load .env if exists
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
fi

# Logging functions
log() {
    local type="$1"
    local message="${*:2}"
    case "$type" in
        success)
            echo -e "${GREEN}${message}${NC}"
            ;;
        warning)
            echo -e "${YELLOW}${message}${NC}" >&2
            ;;
        error)
            echo -e "${RED}${message}${NC}" >&2
            ;;
        info)
            echo -e "${message}"
            ;;
        debug)
            if [ "$DEBUG_MODE" = "true" ]; then
                echo -e "${GRAY}[DEBUG] ${message}${NC}"
            fi
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
    echo -e "  bash manage.sh --start | -s      Start VPN service and configure routes"
    echo -e "  bash manage.sh --stop  | -k      Stop VPN service and remove routes"
    echo -e "  bash manage.sh --debug           Enable debug mode for service validation"
    echo -e "  bash manage.sh --help | -h       Show this help"
}

is_container_running() {
    docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"
}

is_service_running() {
    log debug "Starting OpenVPN service validation..."
    
    # Check if OpenVPN process is running
    log debug "Checking if OpenVPN process is running in container..."
    if ! docker exec "${CONTAINER_NAME}" pgrep -x openvpn >/dev/null 2>&1; then
        log debug "OpenVPN process check failed - no process found"
        log error "OpenVPN process is NOT running in the container ${ICON_ERROR}."
        return 1
    else
        log debug "OpenVPN process check passed - process found"
        log success "OpenVPN process is running in the container ${ICON_SUCCESS}."
    fi

    # Check if VPN interface exists and has an IP address
    log debug "Checking for VPN interface (tun/tap)..."
    VPN_INTERFACE=$(docker exec "${CONTAINER_NAME}" ip -o -4 addr show | awk '/tun[0-9]/ {print $2}')
    if [ -n "$VPN_INTERFACE" ]; then
        log debug "VPN interface found: $VPN_INTERFACE"
        log info "VPN interface '$VPN_INTERFACE' is up ${ICON_SUCCESS}."
        return 0
    else
        log debug "No VPN interface found in container"
        log error "No VPN interface (tun/tap) found in the container ${ICON_ERROR}."
        return 1
    fi
}

wait_for_vpn_startup() {
    log info "Waiting for VPN to start up ${ICON_LOADING}..."
    local attempts=0
    local max_attempts=10
    
    while [ $attempts -lt $max_attempts ]; do
        # Check if the VPN startup message appears in logs
        if docker logs --tail 1 "${CONTAINER_NAME}" 2>&1 | grep -q "$VPN_STARTUP_MESSAGE"; then
            log success "VPN startup completed successfully ${ICON_SUCCESS}"
            return 0
        else
            log info "Waiting for VPN startup... (attempt $((attempts+1))/$max_attempts)"
            sleep 1
            attempts=$((attempts+1))
        fi
    done
    
    log warning "VPN startup message not detected within 5 seconds, continuing anyway ${ICON_WARNING}..."
    return 1
}

add_routes() {
    log info "Obtaining container IP and local interface..."
    if [ -z "$SHARED_IPS" ]; then
        log error "SHARED_IPS not defined in .env ${ICON_ERROR}"
        return 1
    fi
    CONTAINER_IP=$(docker inspect "$CONTAINER_NAME" --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
    if [ -z "$CONTAINER_IP" ]; then
        log error "Could not get container IP ${ICON_ERROR}"
        return 1
    fi
    LOCAL_INTERFACE=$(ip route get "$CONTAINER_IP" | awk '{for(i=1;i<=NF;i++){if($i=="dev"){print $(i+1); exit}}}')
    log info "Container IP: $GREEN$BOLD$CONTAINER_IP$NC"
    log info "Local interface: $GREEN$LOCAL_INTERFACE$NC"
    log info "Shared subnets: $GREEN$SHARED_IPS$NC"
    printf "\n${BOLD}%-25s %-18s %-18s %-3s${NC}\n" "Subnet" "Gateway" "Interface" "Status"
    printf "%-25s %-18s %-18s %-3s\n" "-------------------------" "------------------" "------------------" "------"
    for IP in $SHARED_IPS; do
        # Check if route already exists
        if ip route show | grep -q "^$IP "; then
            printf "%-25s %-18s %-18s ${YELLOW}%s ${ICON_WARNING}${NC}\n" "$IP" "$CONTAINER_IP" "$LOCAL_INTERFACE" "Already exists"
        else
            ip route add $IP via $CONTAINER_IP dev $LOCAL_INTERFACE 2>/dev/null
            if [ $? -eq 0 ]; then
                printf "%-25s %-18s %-18s ${GREEN}%s ${ICON_SUCCESS}${NC}\n" "$IP" "$CONTAINER_IP" "$LOCAL_INTERFACE" "Added"
            else
                printf "%-25s %-18s %-18s ${RED}%s ${ICON_WARNING}${NC}\n" "$IP" "$CONTAINER_IP" "$LOCAL_INTERFACE" "Error"
            fi
        fi
    done
}

delete_routes() {
    if [ -z "$SHARED_IPS" ]; then
        log error "SHARED_IPS not defined in .env ${ICON_ERROR}"
        return 1
    fi
    printf "\n${BOLD}%-25s %-10s${NC}\n" "Subnet" "Status"
    printf "%-25s %-10s\n" "-------------------------" "----------"
    for IP in $SHARED_IPS; do
        if ip route show | grep -q "^$IP "; then
            ip route del $IP 2>/dev/null
            if [ $? -eq 0 ]; then
                printf "%-25s ${GREEN}%s ${ICON_SUCCESS}${NC}\n" "$IP" "Removed"
            else
                printf "%-25s ${RED}%s ${ICON_WARNING}${NC}\n" "$IP" "Error"
            fi
        else
            printf "%-25s ${YELLOW}%s ${ICON_WARNING}${NC}\n" "$IP" "Not found"
        fi
    done
}

start_vpn() {
    section "[1/3] Container Status"
    if is_container_running; then
        log success "Container '${CONTAINER_NAME}' is already running ${ICON_SUCCESS}."
    else
        log success "Starting container ${ICON_LOADING}..."
        docker compose up -d
        wait_for_vpn_startup
    fi

    section "[2/3] OpenVPN Service Validation"
    log info "Checking OpenVPN service status ${ICON_LOADING}..."
    if is_service_running; then
        log success "OpenVPN service is active in the container ${ICON_SUCCESS}."
    else
        log warning "Container is running but OpenVPN service is not active ${ICON_WARNING}."
        log info "Trying to start OpenVPN service inside the container ${ICON_LOADING}..."
        if docker exec -d "${CONTAINER_NAME}" bash "${ENTRYPOINT_SCRIPT}"; then
            sleep 3
            wait_for_vpn_startup
            if is_service_running; then
                log success "OpenVPN service started successfully ${ICON_SUCCESS}."
            else
                log error "Could not start OpenVPN service ${ICON_ERROR}."
                exit 1
            fi
        else
            log error "Could not execute entrypoint inside the container ${ICON_ERROR}."
            exit 1
        fi
    fi

    section "[3/3] Route Configuration"
    log info "Configuring routes for shared subnets..."
    add_routes
    log ""
    log success "All operations completed successfully ${ICON_READY}!"
    log ""
}

stop_vpn() {
    section "[1/2] Route Removal"
    log info "Removing routes for shared subnets ${ICON_LOADING}..."
    delete_routes
    section "[2/2] Container Shutdown"
    if is_container_running; then
        log info "Stopping container ${ICON_LOADING}..."
        docker stop "$CONTAINER_NAME"
        log ""
        log success "Container stopped ${ICON_READY}."
        log ""
    else
        log success "Container is already stopped ${ICON_READY}."
        log ""
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
    --debug)
        DEBUG_MODE="true"
        echo -e "${GRAY}[DEBUG MODE ENABLED]${NC}"
        echo -e "${GRAY}Running service validation with debug information...${NC}\n"
        if is_container_running; then
            is_service_running
        else
            log error "Container '${CONTAINER_NAME}' is not running ${ICON_ERROR}."
            log info "Start the container first with: sudo bash manage.sh --start"
        fi
        ;;
    --help|-h|*)
        show_help
        ;;
esac
