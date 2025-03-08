#!/bin/bash

set -euo pipefail

# --- Configuration ---
INSTALL_DIR="$HOME/gaianet"
NODE_BASE_DIR="$INSTALL_DIR/nodes"
LOG_FILE="$INSTALL_DIR/installation.log"

# --- Safe Directory Management ---
change_directory() {
    local target_dir="$1"
    if ! cd "$target_dir"; then
        echo "ERROR: Failed to change to directory: $target_dir" | tee -a "$LOG_FILE"
        exit 1
    fi
}

# --- Fixed Installation Function ---
install_gaianet() {
    # Create installation directory
    mkdir -p "$INSTALL_DIR" || exit 1
    
    # Clone repository safely
    echo "Cloning GaiaNet repository..."
    if ! git clone https://github.com/Debrajkhanra88/Gaia.git "$INSTALL_DIR/repo"; then
        echo "ERROR: Failed to clone repository" | tee -a "$LOG_FILE"
        exit 1
    fi

    # Change to repo directory with error checking
    change_directory "$INSTALL_DIR/repo"
    
    # Install dependencies
    echo "Installing dependencies..."
    chmod +x *.sh || {
        echo "ERROR: Failed to make scripts executable" | tee -a "$LOG_FILE"
        exit 1
    }

    # Rest of installation logic...
}

# --- Node Initialization ---
init_node() {
    local node_id="$1"
    local node_dir="$NODE_BASE_DIR/node-$node_id"
    
    echo "Initializing node $node_id..."
    mkdir -p "$node_dir" || exit 1
    change_directory "$node_dir"
    
    # Node initialization logic...
}

# --- Main Execution ---
main() {
    # Clean log file
    > "$LOG_FILE"
    
    # Start installation
    install_gaianet
    
    # Initialize nodes
    for node_id in {1..3}; do
        init_node "$node_id"
    done
    
    echo "Installation completed successfully!"
    echo "Details logged to: $LOG_FILE"
}

# Run main function
main "$@"
