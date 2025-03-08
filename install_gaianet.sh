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
    
    # Check memory (16GB minimum)
    local mem_available=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$mem_available" -lt 16 ]; then
        log "❌ Insufficient memory: ${mem_available}GB available, 16GB required"
        exit 1
    fi

    # Check disk space (50GB minimum)
    local disk_available=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$disk_available" -lt 50 ]; then
        log "❌ Insufficient disk space: ${disk_available}GB available, 50GB required"
        exit 1
    fi

    # Check ports availability
    for port in {8080..8083}; do
        if netstat -tuln | grep -q ":$port "; then
            log "❌ Port $port is already in use"
            exit 1
        fi
    done
}

# --- GPU Detection and Setup ---
detect_gpu() {
    if ! command -v nvidia-smi &>/dev/null; then
        log "❌ nvidia-smi not found"
        return 1
    fi

    if ! nvidia-smi &>/dev/null; then
        log "❌ nvidia-smi failed to run"
        return 1
    }

    local gpu_count=$(nvidia-smi --query-gpu=gpu_name --format=csv,noheader | wc -l)
    if [ "$gpu_count" -eq 0 ]; then
        log "❌ No NVIDIA GPUs detected"
        return 1
    fi

    log "✅ Found $gpu_count NVIDIA GPU(s)"
main
