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
    local mem_available=$(awk '/MemTotal/ {print $2/1024/1024}' /proc/meminfo | cut -d. -f1)
    if [ "$mem_available" -lt 16 ]; then
        log "❌ Insufficient memory: ${mem_available}GB available, 16GB required"
        exit 1
    fi

    # Check disk space (50GB minimum)
    local disk_available=$(df --output=avail -BG / | tail -1 | tr -dc '0-9')
    if [ "$disk_available" -lt 50 ]; then
        log "❌ Insufficient disk space: ${disk_available}GB available, 50GB required"
        exit 1
    fi

    # Check ports availability
    for port in {8080..8083}; do
        if ss -tuln | grep -q ":$port "; then
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

    if ! nvidia-smi --list-gpus | grep -q "GPU"; then
        log "❌ No NVIDIA GPUs detected"
        return 1
    fi

    local gpu_count=$(nvidia-smi --query-gpu=gpu_name --format=csv,noheader | wc -l)
    log "✅ Found $gpu_count NVIDIA GPU(s)"
    return 0
}

install_gpu_dependencies() {
    log "🛠️ Installing GPU dependencies..."
    
    # Add NVIDIA repository
    add-apt-repository ppa:graphics-drivers/ppa -y
    apt update
    apt install -y nvidia-driver-535 || {
        log "❌ Failed to install NVIDIA drivers"
        exit 1
    }

    # Install CUDA Toolkit
    apt-key adv --fetch-keys https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/3bf863cc.pub
    wget https://developer.download.nvidia.com/compute/cuda/12.2.0/local_installers/cuda-repo-ubuntu2204-12-2-local_12.2.0-535.54.03-1_amd64.deb
    dpkg -i cuda-repo-ubuntu2204-12-2-local_12.2.0-535.54.03-1_amd64.deb
    apt update
    apt install -y cuda-toolkit-12-2 || {
        log "❌ Failed to install CUDA Toolkit"
        exit 1
    }

    # Install PyTorch with CUDA support
    pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118 || {
        log "❌ Failed to install PyTorch"
        exit 1
    }
}

install_cpu_dependencies() {
    log "🛠️ Installing CPU dependencies..."
    apt update
    apt install -y libopenblas-dev libmkl-dev python3-pip || {
        log "❌ Failed to install CPU dependencies"
        exit 1
    }
    
    pip3 install torch torchvision torchaudio || {
        log "❌ Failed to install PyTorch"
        exit 1
    }
}

# --- Node Management ---
start_node() {
    local node_num="$1"
    local port=$((8080 + node_num))
    local node_dir="$HOME/gaianet_node_$node_num"

    log "🚀 Starting node $node_num on port $port..."
    screen -dmL -Logfile gaianet_node_$node_num.log -S "gaianet_node_$node_num" ~/gaianet/bin/gaianet start \
        --port="$port" \
        --data-dir="$node_dir" || {
        log "❌ Failed to start node $node_num"
        return 1
    }
    return 0
}

# --- Main Script ---
main() {
    check_root
    check_system_requirements

    # Install base dependencies
    apt install -y curl git screen jq || exit 1

    # GPU/CPU setup
    if detect_gpu; then
        install_gpu_dependencies
    else
        install_cpu_dependencies
    fi

    log "✅ GaiaNet nodes setup completed"

    # Node management menu
    while true; do
        echo "==================================="
        echo "🔍 GaiaNet Node Management Menu"
        echo "1) ✅ Check Running Nodes"
        echo "2) 🚀 Start Node"
        echo "3) ⛔ Stop Node"
        echo "4) 🔄 Restart All Nodes"
        echo "5) ❌ Exit"
        echo "==================================="

        read -rp "Enter your choice: " option
        case $option in
            1)
                log "✅ Running nodes:"
                screen -ls | grep -q "gaianet_node_" && screen -ls || log "No nodes running"
                ;;
            2)
                read -rp "Enter Node Number (1-3): " node_number
                if [[ "$node_number" =~ ^[1-3]$ ]]; then
                    start_node "$node_number"
                else
                    log "❌ Invalid node number"
                fi
                ;;
            3)
                read -rp "Enter Node Number (1-3): " node_number
                if [[ "$node_number" =~ ^[1-3]$ ]]; then
                    screen -S "gaianet_node_$node_number" -X quit
                    log "⛔ Stopped node $node_number"
                else
                    log "❌ Invalid node number"
                fi
                ;;
            4)
                log "🔄 Restarting all nodes..."
                for i in {1..3}; do
                    screen -S "gaianet_node_$i" -X quit 2>/dev/null
                    start_node "$i"
                done
                log "✅ All nodes restarted"
                ;;
            5)
                log "👋 Exiting..."
                break
                ;;
            *)
                log "❌ Invalid choice"
                ;;
        esac
    done
}

# --- Script Entry Point ---
if [[ $# -gt 0 ]]; then
    log "🔄 Starting node with parameters: $@"
    exec ~/gaianet/bin/gaianet start "$@"
    exit 0
fi

main
