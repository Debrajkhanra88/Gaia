#!/bin/bash

set -e  # Exit on any error

# --- Utility Functions ---
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then 
        log "❌ Please run as root or with sudo"
        exit 1
    fi
}

# --- System Requirements Check ---
check_system_requirements() {
    log "🔍 Checking system requirements..."
    
    # Check memory (Warn if below 16GB, suggest nodes based on available memory)
    local mem_available=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$mem_available" -lt 16 ]; then
        log "⚠️  Warning: Low memory detected (${mem_available}GB). Recommended: 16GB."
        local max_nodes=$((mem_available / 4))
        if [ "$max_nodes" -lt 1 ]; then
            max_nodes=1
        fi
        log "👉 You can install up to $max_nodes node(s) based on available RAM."
    else
        max_nodes=3
    fi

    # Check disk space (50GB minimum, but warn instead of exiting)
    local disk_available=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$disk_available" -lt 50 ]; then
        log "⚠️  Warning: Low disk space (${disk_available}GB). Recommended: 50GB."
    fi

    # Check ports availability
    for port in {8080..8083}; do
        if netstat -tuln | grep -q ":$port "; then
            log "❌ Port $port is already in use"
            exit 1
        fi
    done
}

# --- Main Script ---
main() {
    check_root
    check_system_requirements

    # Install base dependencies
    apt install -y curl git screen jq || exit 1

    # Clone GaiaNet repository
    log "📥 Cloning GaiaNet repository..."
    rm -rf ~/Gaia
    git clone https://github.com/Debrajkhanra88/Gaia.git ~/Gaia || exit 1
    cd ~/Gaia || exit 1
    chmod +x *.sh

    # Ask user how many nodes to install (based on system memory check)
    read -rp "How many nodes do you want to install? (Max: $max_nodes) " node_count
    if [[ "$node_count" -gt "$max_nodes" ]]; then
        log "⚠️  Reducing node count to $max_nodes due to memory limits."
        node_count=$max_nodes
    fi

    log "🔧 Proceeding with installation of $node_count node(s)..."

    # Continue with installation process...
}

# --- Script Entry Point ---
main
