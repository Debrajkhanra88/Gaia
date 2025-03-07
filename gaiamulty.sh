#!/bin/bash

# Function to detect GPU
detect_gpu() {
    if command -v nvidia-smi &>/dev/null; then
        echo "✅ NVIDIA GPU detected"
        return 0
    else
        echo "❌ No NVIDIA GPU detected (Running on CPU)"
        return 1
    fi
}

# Function to install GPU dependencies
install_gpu_tools() {
    echo "🛠️ Installing GPU dependencies..."
    sudo apt update && sudo apt install -y nvidia-driver-535 cuda-toolkit-12-2 \
        libcudnn8 libnccl2 libnccl-dev python3-pip
    pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118
}

# Function to install CPU dependencies
install_cpu_tools() {
    echo "🛠️ Installing CPU dependencies..."
    sudo apt update && sudo apt install -y libopenblas-dev libmkl-dev python3-pip
    pip3 install torch torchvision torchaudio
}

# Detect GPU and install necessary tools
if detect_gpu; then
    install_gpu_tools
else
    install_cpu_tools
fi

# Install other required dependencies
sudo apt install -y curl git screen

# Clone the GaiaNet repo
rm -rf ~/Gaia
git clone https://github.com/Debrajkhanra88/Gaia.git ~/Gaia
cd ~/Gaia

# Make scripts executable
chmod +x *.sh

# Model Selection Menu
echo "🚀 Select the AI Model to Install:"
echo "1) LLaMA 3 (8B) - Best for GPU Servers"
echo "2) Mistral 7B - Mid-range GPUs (Tesla T4, 3090)"
echo "3) Mixtral 12.7B - High-end GPUs (A100, H100)"
echo "4) Phi-2 (2.7B) - Best for CPU Servers"
echo "5) LLaMA 2 (7B) - CPU Optimized"
echo "6) TinyLLaMA (1.1B) - Ultra-lightweight CPU Model"
read -rp "Enter the number of your choice: " model_choice

# Assign model config based on selection
case $model_choice in
    1) model_url="https://raw.githubusercontent.com/GaiaNet-AI/node-configs/main/llama-3.1-8b-instruct/config.json" ;;
    2) model_url="https://raw.githubusercontent.com/GaiaNet-AI/node-configs/main/mistral-7b-instruct/config.json" ;;
    3) model_url="https://raw.githubusercontent.com/GaiaNet-AI/node-configs/main/mixtral-12.7b/config.json" ;;
    4) model_url="https://raw.githubusercontent.com/GaiaNet-AI/node-configs/main/phi-2/config.json" ;;
    5) model_url="https://raw.githubusercontent.com/GaiaNet-AI/node-configs/main/llama-2-7b-cpu/config.json" ;;
    6) model_url="https://raw.githubusercontent.com/GaiaNet-AI/node-configs/main/tiny-llama-1b/config.json" ;;
    *) echo "❌ Invalid choice. Exiting..." && exit 1 ;;
esac

# Run multiple nodes (3 nodes as example)
for i in {1..3}; do
    mkdir -p ~/gaianet_node_$i
    cd ~/gaianet_node_$i
    curl -O https://raw.githubusercontent.com/Debrajkhanra88/Gaia/main/gaiamulty.sh
    chmod +x gaiamulty.sh
    ./gaiamulty.sh --port=$((8080 + i)) --data-dir=~/gaianet_node_$i

    # Start each node inside a screen session
    screen -dmS gaianet_node_$i ~/gaianet/bin/gaianet start --data-dir=~/gaianet_node_$i
    ~/gaianet/bin/gaianet init --config "$model_url"
done

echo "✅ Multiple GaiaNet Nodes Installed & Running Successfully!"

# Node Management Menu
while true; do
    echo "==================================="
    echo "🔍 GaiaNet Node Management Menu"
    echo "1) 🌍 Check Node Info (Node ID & Device ID)"
    echo "2) 🚀 Start a Specific Node"
    echo "3) ⛔ Stop a Specific Node"
    echo "4) 🔄 Restart All Nodes"
    echo "5) ✅ Check Running Nodes"
    echo "6) 🔗 Attach to a Node Session"
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
                echo "🚀 Starting Node $node_number..."
                screen -dmS gaianet_node_$node_number ~/gaianet/bin/gaianet start --data-dir=~/gaianet_node_$node_number
            else
                echo "❌ Invalid Node Number"
            fi
            ;;
        3)
            read -rp "Enter Node Number (1-3) to Stop: " node_number
            if [[ "$node_number" =~ ^[1-3]$ ]]; then
                echo "⛔ Stopping Node $node_number..."
                screen -S gaianet_node_$node_number -X quit
            else
                echo "❌ Invalid Node Number"
            fi
            ;;
        4)
            echo "🔄 Restarting All Nodes..."
            for i in {1..3}; do
                screen -S gaianet_node_$i -X quit
                screen -dmS gaianet_node_$i ~/gaianet/bin/gaianet start --data-dir=~/gaianet_node_$i
            done
            echo "✅ All Nodes Restarted Successfully!"
            ;;
        5)
            echo "✅ Checking Running Nodes..."
            screen -ls | grep gaianet_node_ || echo "❌ No Nodes Running"
            ;;
        6)
            read -rp "Enter Node Number (1-3) to Attach: " node_number
            if [[ "$node_number" =~ ^[1-3]$ ]]; then
                echo "🔗 Attaching to Node $node_number session..."
                screen -r gaianet_node_$node_number
            else
                echo "❌ Invalid Node Number"
            fi
            ;;
        7) echo "👋 Exiting..." && break ;;
        *) echo "❌ Invalid choice. Try again." ;;
    esac
done
