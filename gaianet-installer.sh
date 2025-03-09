#!/bin/bash

# Ensure the script is running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ This script must be run as root. Try: sudo $0"
    exit 1
fi

# Function to check if a package is installed
is_installed() {
    dpkg -l | grep -qw "$1"
}

# Fix Google Chrome GPG Key Issue
GOOGLE_KEY="/etc/apt/trusted.gpg.d/google-chrome.asc"
if ! test -f "$GOOGLE_KEY"; then
    echo "🔑 Adding Google Chrome GPG key..."
    wget -qO- https://dl.google.com/linux/linux_signing_key.pub | sudo tee "$GOOGLE_KEY" >/dev/null
    if [ $? -eq 0 ]; then
        echo "✅ Google Chrome GPG key added successfully."
    else
        echo "❌ Failed to add Google Chrome GPG key!"
    fi
else
    echo "✅ Google Chrome GPG key already exists. Skipping."
fi

# --- Update Package Lists ---
echo "🔄 Updating package list..."
apt update -q

# --- Check for Upgradable Packages ---
echo "📦 Checking for upgradable packages..."
UPGRADABLE=$(apt list --upgradable 2>/dev/null | grep -v "Listing..." || true)

if [ -z "$UPGRADABLE" ]; then
    echo "✅ All packages are up to date. Skipping upgrade."
else
    echo "🔼 Upgradable packages found:"
    echo "$UPGRADABLE"
    echo "🚀 Upgrading packages..."
    apt upgrade -y
fi

# --- Install Required Packages ---
REQUIRED_PACKAGES=(nvtop sudo curl htop systemd fonts-noto-color-emoji)
echo "🛠️ Checking required packages..."

for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if is_installed "$pkg"; then
        echo "✅ $pkg is already installed. Skipping."
    else
        echo "📥 Installing $pkg..."
        apt install -y "$pkg"
    fi
done

# --- Detect Hardware ---
echo "🔍 Detecting hardware..."
GPU_COUNT=0
CPU_CORES=$(nproc)

if command -v nvidia-smi &>/dev/null; then
    GPU_COUNT=$(nvidia-smi --query-gpu=gpu_name --format=csv,noheader | wc -l)
fi

echo "💻 CPU Cores: $CPU_CORES"
echo "🎮 GPU(s) Detected: $GPU_COUNT"

# --- Model Selection Based on Hardware ---
declare -A model_configs=(
    ["1"]="https://raw.githubusercontent.com/GaiaNet-AI/node-configs/main/mixtral-12.7b/config.json"
    ["2"]="https://raw.githubusercontent.com/GaiaNet-AI/node-configs/main/llama-3.1-8b-instruct/config.json"
    ["3"]="https://raw.githubusercontent.com/GaiaNet-AI/node-configs/main/mistral-7b-instruct/config.json"
    ["4"]="https://raw.githubusercontent.com/GaiaNet-AI/node-configs/main/llama-2-7b-cpu/config.json"
    ["5"]="https://raw.githubusercontent.com/GaiaNet-AI/node-configs/main/phi-2/config.json"
    ["6"]="https://raw.githubusercontent.com/GaiaNet-AI/node-configs/main/tiny-llama-1b/config.json"
)

BEST_MODEL=""
BEST_CHOICE=""

if [[ $GPU_COUNT -ge 1 ]]; then
    GPU_NAME=$(nvidia-smi --query-gpu=gpu_name --format=csv,noheader | head -n1)
    echo "🎮 Detected GPU: $GPU_NAME"

    case $GPU_NAME in
        *A100*|*H100*|*4090*)
            BEST_MODEL="Mixtral 12.7B"
            BEST_CHOICE="1"
            ;;
        *A40*|*A100*|*3090*)
            BEST_MODEL="LLaMA 3 (8B)"
            BEST_CHOICE="2"
            ;;
        *T4*|*3060*|*3070*)
            BEST_MODEL="Mistral 7B"
            BEST_CHOICE="3"
            ;;
        *)
            BEST_MODEL="Mistral 7B"
            BEST_CHOICE="3"
            ;;
    esac
else
    echo "⚠️ No GPU detected, using CPU models."
    if [[ $CPU_CORES -ge 16 ]]; then
        BEST_MODEL="LLaMA 2 (7B CPU)"
        BEST_CHOICE="4"
    elif [[ $CPU_CORES -ge 8 ]]; then
        BEST_MODEL="Phi-2 (2.7B)"
        BEST_CHOICE="5"
    else
        BEST_MODEL="TinyLLaMA (1.1B)"
        BEST_CHOICE="6"
    fi
fi

echo "🔹 Recommended model for your system: **$BEST_MODEL**"
echo ""
echo "🚀 Select the AI Model to Install:"
echo "1) Mixtral 12.7B  (High-end GPUs: A100, H100, 4090)"
echo "2) LLaMA 3 (8B)   (Mid-High GPUs: A40, 3090, 4090)"
echo "3) Mistral 7B     (Mid GPUs: T4, 3060, 3090)"
echo "4) LLaMA 2 (7B)   (CPU Optimized - 16+ Cores)"
echo "5) Phi-2 (2.7B)   (Best for CPUs - 8+ Cores)"
echo "6) TinyLLaMA (1B) (Ultra-lightweight CPU Model)"

read -rp "Press ENTER to continue with '$BEST_MODEL' or enter another number: " model_choice

if [[ -z "$model_choice" ]]; then
    model_choice="$BEST_CHOICE"
fi

if [[ ! ${model_configs[$model_choice]} ]]; then
    echo "❌ Invalid choice. Using recommended model: $BEST_MODEL"
    model_choice="$BEST_CHOICE"
fi

CONFIG_URL="${model_configs[$model_choice]}"
echo "✅ Selected model config: $CONFIG_URL"

# --- Download and Execute Gaia Installer ---
INSTALLER="gaiainstaller.sh"
INSTALLER_URL="https://raw.githubusercontent.com/abhiag/Gaiatest/main/gaiainstaller.sh"

# Remove existing installer if present
if [ -f "$INSTALLER" ]; then
    echo "🗑️ Removing old Gaia installer script..."
    rm -f "$INSTALLER"
fi

# Download the latest Gaia installer
echo "🌍 Downloading the latest Gaia installer script..."
if curl -fsSL -o "$INSTALLER" "$INSTALLER_URL"; then
    echo "✅ Gaia installer downloaded successfully."
    chmod +x "$INSTALLER"
    
    # Execute Gaia installer with selected model config
    echo "🚀 Running Gaia installer with selected model..."
    ./"$INSTALLER" --config "$CONFIG_URL"
else
    echo "❌ Failed to download Gaia installer! Check your internet connection."
    exit 1
fi
