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

ENTRYPOINT_SCRIPT="/entrypoint.sh"
ENV_FILE="${SCRIPT_DIR}/.env"
DEBUG_MODE="false"

# Load .env if exists (single source of truth for CONTAINER_NAME and SHARED_IPS)
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
fi

# Fallback if .env did not define CONTAINER_NAME
CONTAINER_NAME="${CONTAINER_NAME:-openvpn-client}"

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
    echo -e "  bash manage.sh --stop  | -k      Remove host routes (container stays running)"
    echo -e "  bash manage.sh --down            Remove routes AND stop/remove the container"
    echo -e "  bash manage.sh --debug           Enable verbose debug output (modifier or standalone check)"
    echo -e "  bash manage.sh --help  | -h      Show this help"
    echo -e ""
    echo -e "  --debug can be combined: sudo bash manage.sh --start --debug"
}

is_container_running() {
    docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"
}

# Checks that the OpenVPN process is running AND a tun* interface exists
# inside the container. This is the real source of truth — do NOT rely on
# grepping container logs for a sentinel string.
is_service_running() {
    log debug "Starting OpenVPN service validation..."

    log debug "Checking if OpenVPN process is running in container..."
    if ! docker exec "${CONTAINER_NAME}" pgrep -x openvpn >/dev/null 2>&1; then
        log debug "OpenVPN process check failed - no process found"
        log error "OpenVPN process is NOT running in the container ${ICON_ERROR}."
        return 1
    fi
    log debug "OpenVPN process check passed - process found"
    log success "OpenVPN process is running in the container ${ICON_SUCCESS}."

    log debug "Checking for VPN interface (tun/tap)..."
    VPN_INTERFACE=$(docker exec "${CONTAINER_NAME}" ip -o -4 addr show 2>/dev/null | awk '/tun[0-9]/ {print $2}')
    if [ -n "$VPN_INTERFACE" ]; then
        log debug "VPN interface found: $VPN_INTERFACE"
        log info "VPN interface '$VPN_INTERFACE' is up ${ICON_SUCCESS}."
        return 0
    fi

    log debug "No VPN interface found in container"
    log error "No VPN interface (tun/tap) found in the container ${ICON_ERROR}."
    return 1
}

# Waits until is_service_running succeeds (tun* up + openvpn process alive).
# This replaces the old log-sentinel approach which was fragile against log
# message changes and --tail 1 race conditions.
wait_for_vpn_startup() {
    log info "Waiting for VPN to come up ${ICON_LOADING}..."
    local attempts=0
    local max_attempts=30

    while [ $attempts -lt $max_attempts ]; do
        if docker exec "${CONTAINER_NAME}" pgrep -x openvpn >/dev/null 2>&1 && \
           docker exec "${CONTAINER_NAME}" ip -o -4 addr show 2>/dev/null | awk '/tun[0-9]/ {found=1} END {exit !found}'; then
            log success "VPN is up ${ICON_SUCCESS}"
            return 0
        fi
        log debug "VPN not ready yet (attempt $((attempts+1))/$max_attempts)"
        sleep 1
        attempts=$((attempts+1))
    done

    log warning "VPN did not come up within ${max_attempts}s ${ICON_WARNING}"
    return 1
}

# Resolves CONTAINER_IP (VPN container bridge IP) and LOCAL_INTERFACE (the host
# bridge device that fronts that IP, e.g. br-xxxx). Sets them as globals so the
# routing and Docker-forwarding helpers share a single source of truth.
resolve_container_net() {
    CONTAINER_IP=$(docker inspect "$CONTAINER_NAME" --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null)
    if [ -z "$CONTAINER_IP" ]; then
        log error "Could not get container IP ${ICON_ERROR}"
        return 1
    fi
    LOCAL_INTERFACE=$(ip route get "$CONTAINER_IP" | awk '{for(i=1;i<=NF;i++){if($i=="dev"){print $(i+1); exit}}}')
    if [ -z "$LOCAL_INTERFACE" ]; then
        log error "Could not resolve host interface for $CONTAINER_IP ${ICON_ERROR}"
        return 1
    fi
    log debug "Resolved $CONTAINER_IP via interface $LOCAL_INTERFACE"
    return 0
}

# Normalizes SHARED_IPS into one valid entry per line. Accepts one entry per
# line or several per line, `#` starts a comment until end of line, and commas
# are treated as separators. Duplicates are dropped (`x/32` == `x`); anything
# that is not an IPv4 host or CIDR, or is a `/0` default route, is skipped with
# a warning on stderr.
parse_shared_ips() {
    local line token
    local -a tokens
    local -A seen=()
    while IFS= read -r line; do
        line="${line%%#*}"
        read -ra tokens <<< "${line//,/ }"
        for token in "${tokens[@]}"; do
            token="${token%/32}"
            if [[ ! "$token" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(/([1-9]|[12][0-9]|3[01]))?$ ]]; then
                log warning "Ignoring invalid SHARED_IPS entry: '$token' ${ICON_WARNING}"
                continue
            fi
            [ -n "${seen[$token]}" ] && continue
            seen[$token]=1
            echo "$token"
        done
    done <<< "$SHARED_IPS"
}

add_routes() {
    log info "Obtaining container IP and local interface..."
    local routes existing failed=0
    routes=$(parse_shared_ips)
    if [ -z "$routes" ]; then
        log error "SHARED_IPS has no valid entries in .env ${ICON_ERROR}"
        return 1
    fi
    resolve_container_net || return 1
    log info "Container IP: $GREEN$BOLD$CONTAINER_IP$NC"
    log info "Local interface: $GREEN$LOCAL_INTERFACE$NC"
    log info "Shared subnets: $GREEN$(echo $routes)$NC"
    printf "\n${BOLD}%-25s %-18s %-18s %-3s${NC}\n" "Subnet" "Gateway" "Interface" "Status"
    printf "%-25s %-18s %-18s %-3s\n" "-------------------------" "------------------" "------------------" "------"
    for IP in $routes; do
        existing=$(ip route show exact "$IP")
        if [[ "$existing" == *"via $CONTAINER_IP "* ]]; then
            printf "%-25s %-18s %-18s ${YELLOW}%s ${ICON_WARNING}${NC}\n" "$IP" "$CONTAINER_IP" "$LOCAL_INTERFACE" "Already exists"
        elif [ -n "$existing" ]; then
            # Same prefix already routed elsewhere (e.g. local LAN); don't hijack it.
            printf "%-25s %-18s %-18s ${RED}%s ${ICON_ERROR}${NC}\n" "$IP" "$CONTAINER_IP" "$LOCAL_INTERFACE" "Conflict: $existing"
            failed=$((failed + 1))
        elif ip route add "$IP" via "$CONTAINER_IP" dev "$LOCAL_INTERFACE" 2>/dev/null; then
            printf "%-25s %-18s %-18s ${GREEN}%s ${ICON_SUCCESS}${NC}\n" "$IP" "$CONTAINER_IP" "$LOCAL_INTERFACE" "Added"
        else
            printf "%-25s %-18s %-18s ${RED}%s ${ICON_WARNING}${NC}\n" "$IP" "$CONTAINER_IP" "$LOCAL_INTERFACE" "Error"
            failed=$((failed + 1))
        fi
    done
    [ "$failed" -eq 0 ]
}

delete_routes() {
    local routes
    routes=$(parse_shared_ips)
    if [ -z "$routes" ]; then
        log error "SHARED_IPS has no valid entries in .env ${ICON_ERROR}"
        return 1
    fi
    printf "\n${BOLD}%-25s %-10s${NC}\n" "Subnet" "Status"
    printf "%-25s %-10s\n" "-------------------------" "----------"
    for IP in $routes; do
        if [ -n "$(ip route show exact "$IP")" ]; then
            ip route del "$IP" 2>/dev/null
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

# Opens cross-network forwarding to the VPN container's bridge via the DOCKER-USER
# chain (the supported hook that is evaluated BEFORE Docker's inter-network
# isolation). Without this, only host-originated traffic reaches the VPN; other
# containers live on different bridges and Docker's DOCKER-ISOLATION rules drop
# the cross-bridge forward. Rules match on the bridge INTERFACE, not the container
# IP — the forwarded packet's destination is the final shared IP, not the gateway.
# NOTE: DOCKER-USER is flushed when the Docker daemon restarts, so --start re-adds.
add_forwarding() {
    resolve_container_net || return 1
    log info "Bridge interface: $GREEN$LOCAL_INTERFACE$NC"
    printf "\n${BOLD}%-45s %-3s${NC}\n" "DOCKER-USER rule" "Status"
    printf "%-45s %-3s\n" "---------------------------------------------" "------"
    for spec in "-o $LOCAL_INTERFACE" "-i $LOCAL_INTERFACE"; do
        if iptables -C DOCKER-USER $spec -j ACCEPT 2>/dev/null; then
            printf "%-45s ${YELLOW}%s ${ICON_WARNING}${NC}\n" "$spec -j ACCEPT" "Exists"
        elif iptables -I DOCKER-USER $spec -j ACCEPT 2>/dev/null; then
            printf "%-45s ${GREEN}%s ${ICON_SUCCESS}${NC}\n" "$spec -j ACCEPT" "Added"
        else
            printf "%-45s ${RED}%s ${ICON_ERROR}${NC}\n" "$spec -j ACCEPT" "Error"
        fi
    done
}

delete_forwarding() {
    if ! resolve_container_net; then
        log warning "Could not resolve VPN bridge; skipping DOCKER-USER cleanup ${ICON_WARNING}"
        return 0
    fi
    printf "\n${BOLD}%-45s %-3s${NC}\n" "DOCKER-USER rule" "Status"
    printf "%-45s %-3s\n" "---------------------------------------------" "------"
    for spec in "-o $LOCAL_INTERFACE" "-i $LOCAL_INTERFACE"; do
        if iptables -C DOCKER-USER $spec -j ACCEPT 2>/dev/null; then
            iptables -D DOCKER-USER $spec -j ACCEPT 2>/dev/null \
                && printf "%-45s ${GREEN}%s ${ICON_SUCCESS}${NC}\n" "$spec -j ACCEPT" "Removed" \
                || printf "%-45s ${RED}%s ${ICON_ERROR}${NC}\n" "$spec -j ACCEPT" "Error"
        else
            printf "%-45s ${YELLOW}%s ${ICON_WARNING}${NC}\n" "$spec -j ACCEPT" "Not found"
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

    section "[3/3] Route & Forwarding Configuration"
    log info "Configuring routes for shared subnets..."
    local routes_ok=true
    add_routes || routes_ok=false
    log info "Opening cross-container forwarding (DOCKER-USER)..."
    add_forwarding
    echo
    if [ "$routes_ok" = false ]; then
        log error "Some routes could not be configured, check the table above ${ICON_ERROR}"
        exit 1
    fi
    log success "All operations completed successfully ${ICON_READY}!"
    echo
}

stop_vpn() {
    section "Route & Forwarding Removal"
    log info "Removing routes for shared subnets ${ICON_LOADING}..."
    delete_routes
    log info "Closing cross-container forwarding (DOCKER-USER)..."
    delete_forwarding
    echo
    log success "Routes and forwarding removed. Container left running ${ICON_READY}."
    log info "To also stop and remove the container: sudo bash manage.sh --down"
    echo
}

down_vpn() {
    section "[1/2] Route & Forwarding Removal"
    log info "Removing routes for shared subnets ${ICON_LOADING}..."
    delete_routes
    log info "Closing cross-container forwarding (DOCKER-USER)..."
    delete_forwarding
    section "[2/2] Container Shutdown"
    if is_container_running; then
        log info "Stopping and removing container ${ICON_LOADING}..."
        docker compose down
        echo
        log success "Container stopped and removed ${ICON_READY}."
        echo
    else
        log success "Container is already stopped ${ICON_READY}."
        echo
    fi
}

# Parse arguments — support --debug as a modifier combined with --start/--stop
ACTION=""
for arg in "$@"; do
    case "$arg" in
        --start|-s) ACTION="start" ;;
        --stop|-k)  ACTION="stop" ;;
        --down)     ACTION="down" ;;
        --debug)    DEBUG_MODE="true" ;;
        --help|-h)  show_help; exit 0 ;;
        *)
            log error "Unknown option: $arg"
            show_help
            exit 1
            ;;
    esac
done

if [ "$DEBUG_MODE" = "true" ]; then
    echo -e "${GRAY}[DEBUG MODE ENABLED]${NC}"
fi

case "$ACTION" in
    start)
        start_vpn
        ;;
    stop)
        stop_vpn
        ;;
    down)
        down_vpn
        ;;
    "")
        # No action given — if --debug alone, run the standalone validation
        if [ "$DEBUG_MODE" = "true" ]; then
            if is_container_running; then
                is_service_running
            else
                log error "Container '${CONTAINER_NAME}' is not running ${ICON_ERROR}."
                log info "Start the container first with: sudo bash manage.sh --start"
            fi
        else
            show_help
            exit 1
        fi
        ;;
esac
