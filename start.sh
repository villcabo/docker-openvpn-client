#!/bin/bash

# Configuration
CONTAINER_NAME="openvpn-client"
ENTRYPOINT_SCRIPT="/entrypoint.sh"
SETUP_SCRIPT="./setup-shared-ip.sh"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to log messages with timestamp
log() {
    local message="$1"
    echo -e "${message}"
}

# Function to check if container is running
is_container_running() {
    docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"
    return $?
}

# Function to check if OpenVPN service is running inside container
is_service_running() {
    if docker exec -it "${CONTAINER_NAME}" pgrep -x openvpn >/dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to restart container service
restart_container_service() {
    log "Checking service status in ${CONTAINER_NAME}..."
    
    if is_service_running; then
        log "Service is already running in ${CONTAINER_NAME}"
        return 0
    fi
    
    log "Service not running, attempting to start..."
    if docker exec -it "${CONTAINER_NAME}" bash "${ENTRYPOINT_SCRIPT}"; then
        # Give the service a moment to start
        sleep 2
        
        if is_service_running; then
            log "${GREEN}Service started successfully${NC}"
            return 0
        else
            log "${YELLOW}Warning: Service script executed but OpenVPN process not detected${NC}"
            return 1
        fi
    else
        log "${RED}Failed to execute service script${NC}"
        return 1
    fi
}

# Function to run setup script
run_setup_script() {
    if [ -f "${SETUP_SCRIPT}" ]; then
        log "Running setup script: ${SETUP_SCRIPT}"
        if bash "${SETUP_SCRIPT}"; then
            log "${GREEN}Setup script completed successfully${NC}"
        else
            log "${YELLOW}Warning: Setup script completed with errors${NC}"
            return 1
        fi
    else
        log "${YELLOW}Warning: Setup script not found at ${SETUP_SCRIPT}${NC}"
        return 1
    fi
}

# Main execution
log "=== Starting VPN Service Manager ==="

if is_container_running; then
    log "Container ${CONTAINER_NAME} is running"
    
    # Get container status before restart
    log "Container status before restart:"
    docker ps --filter "name=^${CONTAINER_NAME}$" --format "table {{.ID}}\t{{.Names}}\t{{.Status}}"
    
    # Restart the service
    if restart_container_service; then
        # Run setup script only if service restart was successful
        log "Service restart successful, running setup script..."
        run_setup_script
    else
        log "${RED}Failed to restart service, skipping setup script${NC}"
        exit 1
    fi
    
    # Show container status after restart
    log "Container status after restart:"
    docker ps --filter "name=^${CONTAINER_NAME}$" --format "table {{.ID}}\t{{.Names}}\t{{.Status}}"
else
    log "${YELLOW}Container ${CONTAINER_NAME} is not running. Starting container...${NC}"
    if docker compose up -d; then
        log "${GREEN}Container started successfully${NC}"
        run_setup_script
    else
        log "${RED}Failed to start container${NC}"
        exit 1
    fi
fi

log "=== VPN Service Manager completed ==="
exit 0
