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
    fi

    local gpu_count=$(nvidia-smi --query-gpu=gpu_name --format=csv,noheader | wc -l)
    if [ "$gpu_count" -eq 0 ]; then
        log "❌ No NVIDIA GPUs detected"
        return 1
    fi

    log "✅ Found $gpu_count NVIDIA GPU(s)"
    return 0
}

install_gpu_dependencies() {
    log "🛠️ Installing GPU dependencies..."
    
    # Add NVIDIA repository
    if ! grep -q "nvidia-driver-535" /etc/apt/sources.list.d/* 2>/dev/null; then
        add-apt-repository ppa:graphics-drivers/ppa -y
    fi

    # Install NVIDIA drivers and CUDA
    apt update
    apt install -y nvidia-driver-535 || {
        log "❌ Failed to install NVIDIA drivers"
        exit 1
    }

    # Install CUDA Toolkit
    wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-ubuntu2204.pin
    mv cuda-ubuntu2204.pin /etc/apt/preferences.d/cuda-repository-pin-600
    wget https://developer.download.nvidia.com/compute/cuda/12.2.0/local_installers/cuda-repo-ubuntu2204-12-2-local_12.2.0-535.54.03-1_amd64.deb
    dpkg -i cuda-repo-ubuntu2204-12-2-local_12.2.0-535.54.03-1_amd64.deb
    cp /var/cuda-repo-ubuntu2204-12-2-local/cuda-*-keyring.gpg /usr/share/keyrings/
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
validate_config() {
    local config_url="$1"
    if ! curl -s "$config_url" | jq empty; then
        log "❌ Invalid JSON configuration at $config_url"
        return 1
    fi
    return 0
}

init_node() {
    local node_num="$1"
    local config_url="$2"
    local node_dir="$HOME/gaianet_node_$node_num"

    log "🔧 Initializing node $node_num..."
    
    mkdir -p "$node_dir"
    cd "$node_dir" || exit 1
    
    if ! validate_config "$config_url"; then
        log "❌ Failed to validate config for node $node_num"
        return 1
    }

    if ! ~/gaianet/bin/gaianet init --config "$config_url"; then
        log "❌ Failed to initialize node $node_num"
        return 1
    }

    return 0
}

start_node() {
    local node_num="$1"
    local port=$((8080 + node_num))
    local node_dir="$HOME/gaianet_node_$node_num"

    log "🚀 Starting node $node_num on port $port..."
    screen -dmS "gaianet_node_$node_num" ~/gaianet/bin/gaianet start \
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

    # Clone GaiaNet repository
    log "📥 Cloning GaiaNet repository..."
    rm -rf ~/Gaia
    git clone https://github.com/Debrajkhanra88/Gaia.git ~/Gaia || exit 1
    cd ~/Gaia || exit 1
    chmod +x *.sh

    # Model selection menu
    declare -A model_configs=(
        ["1"]="https://raw.githubusercontent.com/GaiaNet-AI/node-configs/main/llama-3.1-8b-instruct/config.json"
        ["2"]="https://raw.githubusercontent.com/GaiaNet-AI/node-configs/main/mistral-7b-instruct/config.json"
        ["3"]="https://raw.githubusercontent.com/GaiaNet-AI/node-configs/main/mixtral-12.7b/config.json"
        ["4"]="https://raw.githubusercontent.com/GaiaNet-AI/node-configs/main/phi-2/config.json"
        ["5"]="https://raw.githubusercontent.com/GaiaNet-AI/node-configs/main/llama-2-7b-cpu/config.json"
        ["6"]="https://raw.githubusercontent.com/GaiaNet-AI/node-configs/main/tiny-llama-1b/config.json"
    )

    echo "🚀 Select the AI Model to Install:"
    echo "1) LLaMA 3 (8B) - Best for GPU Servers"
    echo "2) Mistral 7B - Mid-range GPUs (Tesla T4, 3090)"
    echo "3) Mixtral 12.7B - High-end GPUs (A100, H100)"
    echo "4) Phi-2 (2.7B) - Best for CPU Servers"
    echo "5) LLaMA 2 (7B) - CPU Optimized"
    echo "6) TinyLLaMA (1.1B) - Ultra-lightweight CPU Model"
    
    read -rp "Enter the number of your choice: " model_choice

    if [[ ! ${model_configs[$model_choice]} ]]; then
        log "❌ Invalid model choice"
        exit 1
    fi

    local config_url="${model_configs[$model_choice]}"

    # Initialize and start nodes
    for i in {1..3}; do
        if ! init_node "$i" "$config_url"; then
            log "❌ Failed to initialize node $i"
            continue
        fi
        if ! start_node "$i"; then
            log "❌ Failed to start node $i"
            continue
        fi
    done

    log "✅ GaiaNet nodes setup completed"

    # Node management menu
    while true; do
        echo "==================================="
        echo "🔍 GaiaNet Node Management Menu"
        echo "1) 🌍 Check Node Info"
        echo "2) 🚀 Start Node"
        echo "3) ⛔ Stop Node"
        echo "4) 🔄 Restart All Nodes"
        echo "5) ✅ Check Running Nodes"
        echo "6) 🔗 Attach to Node Session"
        echo "7) ❌ Exit"
        echo "==================================="

        read -rp "Enter your choice: " option
        case $option in
            1)
                for i in {1..3}; do
                    echo "🔹 Node $i Info:"
                    ~/gaianet/bin/gaianet info --data-dir=~/gaianet_node_$i
                    echo "---------------------------------"
                done
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
                log "✅ Running nodes:"
                screen -ls | grep "gaianet_node_" || log "No nodes running"
                ;;
            6)
                read -rp "Enter Node Number (1-3): " node_number
                if [[ "$node_number" =~ ^[1-3]$ ]]; then
                    screen -r "gaianet_node_$node_number"
                else
                    log "❌ Invalid node number"
                fi
                ;;
            7)
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
