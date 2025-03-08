#!/bin/bash
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
main
