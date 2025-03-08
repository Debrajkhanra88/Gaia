#!/bin/bash
set -eo pipefail

# --- Configuration ---
INSTALL_DIR="${GAIA_INSTALL_DIR:-$HOME/gaianet}"
NODE_BASE_DIR="$INSTALL_DIR/nodes"
LOG_FILE="$INSTALL_DIR/installation.log"
REPO_URL="https://github.com/Debrajkhanra88/Gaia.git"
REPO_DIR="$INSTALL_DIR/repo"
NODE_COUNT=3
BASE_PORT=8080

# --- Text Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- Logging System ---
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local log_entry="[$timestamp] [$level] $message"
    
    case "$level" in
        "ERROR") echo -e "${RED}$log_entry${NC}" ;;
        "WARN")  echo -e "${YELLOW}$log_entry${NC}" ;;
        "INFO")  echo -e "${GREEN}$log_entry${NC}" ;;
        *)       echo "$log_entry" ;;
    esac
    
    echo "$log_entry" >> "$LOG_FILE"
}

# --- Cleanup Handler ---
cleanup() {
    log "WARN" "Cleaning up after error..."
    # Add any necessary cleanup operations here
    exit 1
}

# --- Dependency Check ---
check_dependencies() {
    local dependencies=("git" "curl" "jq" "tee")
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

# --- Directory Management ---
safe_create_dir() {
    local dir_path="$1"
    log "INFO" "Creating directory: $dir_path"
    if ! mkdir -p "$dir_path"; then
        log "ERROR" "Failed to create directory: $dir_path"
        exit 1
    fi
}

# --- Repository Management ---
clone_repository() {
    log "INFO" "Cloning repository from $REPO_URL"
    if ! git clone "$REPO_URL" "$REPO_DIR"; then
        log "ERROR" "Failed to clone repository"
        exit 1
    fi
}

# --- Node Initialization ---
init_node() {
    local node_id="$1"
    local node_dir="$NODE_BASE_DIR/node-$node_id"
    local port=$((BASE_PORT + node_id))

    log "INFO" "Initializing node $node_id (Port: $port)"
    
    safe_create_dir "$node_dir"
    
    # Simulate node initialization
    if ! touch "$node_dir/config.json"; then
        log "ERROR" "Failed to create node configuration"
        exit 1
    fi
}

# --- Main Installation ---
main() {
    trap cleanup ERR
    
    log "INFO" "Starting GaiaNet installation"
    
    # System checks
    check_dependencies
    safe_create_dir "$INSTALL_DIR"
    touch "$LOG_FILE" || {
        log "ERROR" "Failed to create log file"
        exit 1
    }

    # Repository setup
    if [ -d "$REPO_DIR" ]; then
        log "WARN" "Repository directory already exists, removing..."
        rm -rf "$REPO_DIR"
    fi
    clone_repository

    # Node initialization
    for ((node_id=1; node_id<=NODE_COUNT; node_id++)); do
        init_node "$node_id"
    done

    log "INFO" "Installation completed successfully"
    log "INFO" "Installation directory: $INSTALL_DIR"
    log "INFO" "Log file: $LOG_FILE"
}

# --- Execution ---
main "$@"
