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
    
    # Check memory
    local mem_available=$(awk '/MemTotal/ {print $2/1024/1024}' /proc/meminfo | awk '{print int($1+0.5)}')  # Round to nearest GB
    
    if [ "$mem_available" -lt 16 ]; then
        log "⚠️ Warning: Only ${mem_available}GB RAM available. Some models may not run efficiently."
        local max_nodes=$((mem_available / 5))  # Approximate 5GB RAM per node
        if [ "$max_nodes" -lt 1 ]; then
            max_nodes=1  # Ensure at least 1 node can run
        fi
        log "⚠️ Recommended: Run a maximum of $max_nodes node(s)."
    fi

    # Check disk space
    local disk_available=$(df --output=avail -BG / | tail -1 | tr -dc '0-9')
    if [ "$disk_available" -lt 50 ]; then
        log "⚠️ Warning: Only ${disk_available}GB free disk space. 50GB is recommended."
    fi

    # Check ports availability using 'ss' instead of 'netstat'
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
        log "❌ nvidia-smi not found. Running in CPU mode."
        return 1
    fi

    if ! nvidia-smi &>/dev/null; then
        log "❌ nvidia-smi failed to run. Running in CPU mode."
        return 1
    fi

    local gpu_count=$(nvidia-smi --list-gpus | wc -l)
    if [ "$gpu_count" -eq 0 ]; then
        log "❌ No NVIDIA GPUs detected. Running in CPU mode."
        return 1
    fi

    log "✅ Found $gpu_count NVIDIA GPU(s)"
    return 0
}

install_gpu_dependencies() {
    log "🛠️ Installing GPU dependencies..."
    apt update
    apt install -y nvidia-driver-535 cuda-toolkit-12-2 || {
        log "❌ Failed to install GPU dependencies"
        exit 1
    }
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
init_node() {
    local node_num="$1"
    local config_url="$2"
    local node_dir="$HOME/gaianet_node_$node_num"

    log "🔧 Initializing node $node_num..."
    
    mkdir -p "$node_dir"
    cd "$node_dir" || exit 1
    
    if ! curl -s "$config_url" | jq empty; then
        log "❌ Invalid JSON configuration at $config_url"
        return 1
    fi

    if ! ~/gaianet/bin/gaianet init --config "$config_url"; then
        log "❌ Failed to initialize node $node_num"
        return 1
    fi

    return 0
}

start_node() {
    local node_num="$1"
    local port=$((8080 + node_num))
    local node_dir="$HOME/gaianet_node_$node_num"

    log "🚀 Starting node $node_num on port $port..."
    screen -dmSL "gaianet_node_$node_num" ~/gaianet/bin/gaianet start \
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

    apt install -y curl git screen jq || exit 1

    if detect_gpu; then
        install_gpu_dependencies
    else
        install_cpu_dependencies
    fi

    log "📥 Cloning GaiaNet repository..."
    rm -rf ~/Gaia
    git clone https://github.com/Debrajkhanra88/Gaia.git ~/Gaia || exit 1
    cd ~/Gaia || exit 1
    chmod +x *.sh

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

    for i in {1..3}; do
        init_node "$i" "$config_url" && start_node "$i"
    done

    log "✅ GaiaNet nodes setup completed"
}

if [[ $# -gt 0 ]]; then
    log "🔄 Starting node with parameters: $@"
    exec ~/gaianet/bin/gaianet start "$@"
    exit 0
fi

main
