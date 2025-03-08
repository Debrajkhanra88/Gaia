#!/bin/bash

set -euo pipefail  # More strict error handling

# --- Configuration Variables ---
declare -A MODEL_CONFIGS=(
    ["LLaMA3-8B"]="https://example.com/configs/llama3-8b.json"
    ["Mistral-7B"]="https://example.com/configs/mistral-7b.json"
    # Add other models as needed
)
DEFAULT_NODES=3
MIN_MEMORY=16  # GB
MIN_DISK=50    # GB
BASE_PORT=8080
INSTALL_DIR="$HOME/gaianet"
LOG_FILE="/var/log/gaianet_setup.log"

# --- Enhanced Logging ---
log() {
    local level="$1"
    local message="$2"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [$level] - $message" | tee -a "$LOG_FILE"
}

# --- Root Check ---
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        log "ERROR" "This script must be run as root. Use sudo or switch to root user."
        exit 1
    fi
}

# --- Dependency Checks ---
check_dependencies() {
    local deps=("curl" "git" "jq" "lsof" "free" "df")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        log "ERROR" "Missing required dependencies: ${missing[*]}"
        exit 1
    fi
}

# --- System Validation ---
validate_system() {
    log "INFO" "Validating system requirements..."
    
    # Memory Check
    local mem_total
    mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    mem_total=$((mem_total / 1024 / 1024))
    
    if [ "$mem_total" -lt "$MIN_MEMORY" ]; then
        log "ERROR" "Insufficient memory: ${mem_total}GB available, ${MIN_MEMORY}GB required"
        exit 1
    fi

    # Disk Check
    local disk_avail
    disk_avail=$(df -BG --output=avail "$INSTALL_DIR" | tail -1 | sed 's/G//')
    if [ "$disk_avail" -lt "$MIN_DISK" ]; then
        log "ERROR" "Insufficient disk space in $INSTALL_DIR: ${disk_avail}GB available, ${MIN_DISK}GB required"
        exit 1
    fi

    # Port Check
    for ((port=BASE_PORT; port<BASE_PORT+DEFAULT_NODES; port++)); do
        if lsof -i :"$port" &>/dev/null; then
            log "ERROR" "Port $port is already in use"
            exit 1
        fi
    done
}

# --- GPU Setup ---
setup_gpu() {
    if ! nvidia-smi &>/dev/null; then
        log "WARNING" "NVIDIA GPU not detected or drivers not installed"
        return 1
    fi

    log "INFO" "Detected NVIDIA GPU(s)"
    # Install NVIDIA drivers and CUDA
    # Consider using a driver version from the system's package manager
    # Add secure repository configuration
    add-apt-repository -y ppa:graphics-drivers/ppa
    apt-get update
    apt-get install -y nvidia-driver-535 nvidia-cuda-toolkit
    
    # Verify installation
    if ! nvidia-smi; then
        log "ERROR" "NVIDIA driver installation failed"
        return 1
    fi
}

# --- Node Management ---
init_node() {
    local node_id="$1"
    local config_url="$2"
    local node_dir="$INSTALL_DIR/nodes/node-$node_id"
    local config_file="$node_dir/config.json"

    log "INFO" "Initializing node $node_id in $node_dir"
    
    mkdir -p "$node_dir"
    
    # Secure download with certificate verification
    if ! curl -fsSL --retry 3 --cacert /etc/ssl/certs/ca-certificates.crt "$config_url" -o "$config_file"; then
        log "ERROR" "Failed to download configuration for node $node_id"
        return 1
    fi

    if ! jq empty "$config_file"; then
        log "ERROR" "Invalid JSON configuration for node $node_id"
        return 1
    fi

    # Initialize node using the configuration
    "$INSTALL_DIR/bin/gaianet" init --config "$config_file" --data-dir "$node_dir" || {
        log "ERROR" "Node $node_id initialization failed"
        return 1
    }
}

start_node() {
    local node_id="$1"
    local port=$((BASE_PORT + node_id))
    local node_dir="$INSTALL_DIR/nodes/node-$node_id"
    
    log "INFO" "Starting node $node_id on port $port"
    systemctl start gaianet-node@"$node_id".service || {
        log "ERROR" "Failed to start node $node_id"
        return 1
    }
}

# --- Systemd Service Setup ---
setup_systemd() {
    log "INFO" "Configuring systemd services"
    
    cat > /etc/systemd/system/gaianet-node@.service <<EOF
[Unit]
Description=GaiaNet Node %i
After=network.target

[Service]
User=gaianet
Group=gaianet
WorkingDirectory=$INSTALL_DIR/nodes/node-%i
ExecStart=$INSTALL_DIR/bin/gaianet start \\
    --port=$((BASE_PORT + %i)) \\
    --data-dir=$INSTALL_DIR/nodes/node-%i
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
}

# --- Main Installation ---
install_gaianet() {
    check_root
    check_dependencies
    validate_system

    # Create dedicated user
    if ! id gaianet &>/dev/null; then
        useradd -r -s /usr/sbin/nologin -d "$INSTALL_DIR" gaianet
    fi

    # Clone repository
    if [ ! -d "$INSTALL_DIR" ]; then
        git clone https://github.com/GaiaNet-AI/core.git "$INSTALL_DIR" || {
            log "ERROR" "Failed to clone repository"
            exit 1
        }
    fi

    # GPU setup
    if setup_gpu; then
        log "INFO" "Installing GPU-optimized dependencies"
        pip install -r "$INSTALL_DIR/requirements-gpu.txt"
    else
        log "INFO" "Installing CPU-only dependencies"
        pip install -r "$INSTALL_DIR/requirements-cpu.txt"
    fi

    # Initialize nodes
    for ((node_id=1; node_id<=DEFAULT_NODES; node_id++)); do
        init_node "$node_id" "${MODEL_CONFIGS[$SELECTED_MODEL]}" || {
            log "ERROR" "Aborting installation due to node initialization failure"
            exit 1
        }
    done

    setup_systemd

    # Start nodes
    for ((node_id=1; node_id<=DEFAULT_NODES; node_id++)); do
        start_node "$node_id"
    done

    log "SUCCESS" "GaiaNet installation completed successfully"
}

# --- User Interface ---
select_model() {
    echo "Available AI Models:"
    local i=1
    for model in "${!MODEL_CONFIGS[@]}"; do
        echo "$i) $model"
        ((i++))
    done

    while true; do
        read -rp "Select model (1-${#MODEL_CONFIGS[@]}): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#MODEL_CONFIGS[@]}" ]; then
            SELECTED_MODEL=$(printf "%s\n" "${!MODEL_CONFIGS[@]}" | sed -n "${choice}p")
            break
        fi
        echo "Invalid selection. Please try again."
    done
}

# --- Entry Point ---
main() {
    select_model
    install_gaianet
}

main "$@"
