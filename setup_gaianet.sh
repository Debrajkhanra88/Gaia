#!/bin/bash

# Ensure script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ This script must be run as root. Try: sudo bash $0"
    exit 1
fi

echo "🔍 Checking GPU..."
GPU_INFO=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits)
VRAM=$(echo $GPU_INFO | awk '{print $1}')

echo "💾 Detected VRAM: ${VRAM}MB"

# Determine the best model based on VRAM
if [ "$VRAM" -ge 24000 ]; then
    MODEL="llama-3.1-8b-instruct"
elif [ "$VRAM" -ge 16000 ]; then
    MODEL="mistral-7b-instruct"
elif [ "$VRAM" -ge 12000 ]; then
    MODEL="phi-2"
else
    echo "❌ Not enough VRAM to run GaiaNet efficiently."
    exit 1
fi

echo "✅ Selecting model: $MODEL"

# Install dependencies
echo "🔧 Installing required packages..."
apt update && apt install -y curl git screen tmux build-essential golang

# Set up directories
echo "📂 Setting up GaiaNet..."
rm -rf ~/Gaia ~/gaianet
git clone https://github.com/Debrajkhanra88/Gaia.git ~/Gaia
mkdir -p ~/gaianet/bin

# Install Go and build GaiaNet
echo "🛠 Building GaiaNet..."
export GOPATH=$HOME/go
export PATH=$PATH:/usr/local/go/bin:$GOPATH/bin
cd ~/Gaia
git pull origin main
go mod tidy
go build -v -o ~/gaianet/bin/gaianet .

# Run GaiaNet in a persistent session
echo "🚀 Launching GaiaNet..."
screen -dmS gaianet_session ~/gaianet/bin/gaianet --model $MODEL

echo "✅ GaiaNet is running with model: $MODEL"
echo "🔍 Use 'screen -r gaianet_session' to check logs."
