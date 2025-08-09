#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
CONTAINER_NAME="openvpn-client"
ENTRYPOINT_SCRIPT="/entrypoint.sh"
SETUP_SCRIPT="${SCRIPT_DIR}/setup-shared-ip.sh"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
BOLD='\033[1m'
UNDERLINE='\033[4m'

# Function to log messages with color and type
log() {
    local type="$1"
    local message="${*:2}"
    
    case "$type" in
        success)
            echo -e "${GREEN}✓ SUCCESS: ${message}${NC}"
            ;;
        info)
            echo -e "${BLUE}ℹ INFO: ${message}${NC}"
            ;;
        warning)
            echo -e "${YELLOW}⚠ WARNING: ${message}${NC}" >&2
            ;;
        error)
            echo -e "${RED}✗ ERROR: ${message}${NC}" >&2
            ;;
        *)
            echo -e "${message}"
            ;;
    esac
}

# Function to print section header
section() {
    echo -e "\n${BOLD}${UNDERLINE}${BLUE}==> ${1}${NC}\n"
}

# Function to check if container is running
is_container_running() {
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log info "Container '${CONTAINER_NAME}' is running"
        return 0
    else
        log warning "Container '${CONTAINER_NAME}' is not running"
        return 1
    fi
}

# Function to check if OpenVPN service is running inside container
is_service_running() {
    log info "Checking if OpenVPN service is running and connected..."
    
    # First check if openvpn process is running
    if ! docker exec "${CONTAINER_NAME}" pgrep -x openvpn >/dev/null; then
        log warning "OpenVPN process is not running"
        return 1
    fi
    
    # Then check if VPN connection is actually working by pinging a VPN server
    if docker exec "${CONTAINER_NAME}" ping -c 1 -W 3 199.3.0.108 >/dev/null 2>&1; then
        log success "OpenVPN service is running and connected"
        return 0
    else
        log warning "OpenVPN process is running but VPN connection is not working"
        return 1
    fi
}

# Function to start container service
start_container_service() {
    section "Starting OpenVPN Service"
    
    if is_service_running; then
        log info "Service is already running in ${CONTAINER_NAME}"
        return 0
    fi
    
    log info "Starting OpenVPN service..."
    # Execute entrypoint script in background to avoid blocking
    if docker exec -d "${CONTAINER_NAME}" bash "${ENTRYPOINT_SCRIPT}"; then
        # Give the service time to start
        log info "Waiting for service to initialize..."
        sleep 5
        
        # Check multiple times to ensure service is stable
        local attempts=0
        local max_attempts=10
        
        while [ $attempts -lt $max_attempts ]; do
            if is_service_running; then
                log success "Service started successfully"
                return 0
            else
                log info "Checking service status... (attempt $((attempts + 1))/$max_attempts)"
                sleep 2
                attempts=$((attempts + 1))
            fi
        done
        
        log warning "Service script executed but OpenVPN process not detected after $max_attempts attempts"
        return 1
    else
        log error "Failed to execute service script"
        return 1
    fi
}

# Function to run setup script
run_setup_script() {
    section "Running Setup Script"
    
    if [ -f "${SETUP_SCRIPT}" ]; then
        log info "Found setup script: ${SETUP_SCRIPT}"
        if bash "${SETUP_SCRIPT}"; then
            log success "Setup script completed successfully"
            return 0
        else
            log warning "Setup script completed with errors"
            return 1
        fi
    else
        log warning "Setup script not found at ${SETUP_SCRIPT}"
        return 1
    fi
}

# Function to show container status
show_container_status() {
    section "Container Status"
    docker ps --filter "name=^${CONTAINER_NAME}$" --format "table {{.ID}}\t{{.Names}}\t{{.Status}}"
}

# Main execution
section "Starting VPN Service Manager"

# Change to script's directory
cd "${SCRIPT_DIR}" || {
    log error "Failed to change to script directory: ${SCRIPT_DIR}"
    exit 1
}

if is_container_running; then
    show_container_status
    
    # Start the service
    if start_container_service; then
        # Run setup script only if service start was successful
        run_setup_script
    else
        log error "Failed to start service"
        exit 1
    fi
    
    show_container_status
else
    section "Starting Container"
    log info "Container '${CONTAINER_NAME}' is not running. Starting container..."
    
    if docker compose up -d; then
        log success "Container started successfully"
        
        # Wait a moment for container to fully start
        sleep 3
        
        if start_container_service; then
            run_setup_script
        else
            log error "Failed to start service in container"
            exit 1
        fi
    else
        log error "Failed to start container"
        exit 1
    fi
fi

section "VPN Service Manager Completed"
log success "All operations completed successfully"
exit 0
