#!/bin/bash
set -eo pipefail

# --- Configuration ---
INSTALL_DIR="${GAIA_INSTALL_DIR:-$HOME/gaianet}"
LOG_FILE="$INSTALL_DIR/installation.log"

# --- Pre-Logging Setup ---
# Create installation directory first
mkdir -p "$INSTALL_DIR" || {
    echo -e "\033[0;31mCRITICAL ERROR: Failed to create installation directory: $INSTALL_DIR\033[0m"
    exit 1
}

# Create log file immediately
touch "$LOG_FILE" || {
    echo -e "\033[0;31mCRITICAL ERROR: Failed to create log file: $LOG_FILE\033[0m"
    exit 1
}

# --- Text Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# --- Logging System ---
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local log_entry="[$timestamp] [$level] $message"
    
    # Always show on console
    case "$level" in
        "ERROR") echo -e "${RED}$log_entry${NC}" ;;
        "WARN")  echo -e "${YELLOW}$log_entry${NC}" ;;
        "INFO")  echo -e "${GREEN}$log_entry${NC}" ;;
        *)       echo "$log_entry" ;;
    esac
    
    # Write to log file
    echo "$log_entry" >> "$LOG_FILE"
}

# --- Cleanup Handler ---
cleanup() {
    log "WARN" "Script execution failed - performing cleanup"
    exit 1
}

# --- Dependency Check ---
check_dependencies() {
    local dependencies=("git" "curl" "jq")
    local missing=()
    
    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        log "ERROR" "Missing required dependencies: ${missing[*]}"
        exit 1
    fi
}

# --- Main Installation ---
main() {
    trap cleanup ERR
    
    log "INFO" "Starting GaiaNet installation"
    check_dependencies
    
    # Your installation logic here
    
    log "INFO" "Installation completed successfully"
}

# --- Execution ---
main "$@"
