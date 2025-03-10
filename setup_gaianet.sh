#!/bin/bash

# Ensure script runs as root
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ This script must be run as root. Try: sudo $0"
    exit 1
fi

echo "🚀 Updating system and installing dependencies..."
sudo apt update && sudo apt install -y \
    nvidia-driver-535 \
    cuda-toolkit-12-2 \
    libcudnn8 \
    libnccl2 libnccl-dev \
    python3-pip git curl screen build-essential

echo "🐍 Installing PyTorch with CUDA support..."
pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118

echo "⚡ Installing NVIDIA TensorRT..."
sudo apt install -y nvidia-tensorrt
pip3 install nvidia-pyindex nvidia-tensorrt

echo "🔍 Verifying TensorRT installation..."
python3 -c "import tensorrt as trt; print('TensorRT Version:', trt.__version__)"

echo "📊 Detecting GPU & VRAM..."
GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n 1)
VRAM=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -n 1)

echo "🖥 GPU Detected: $GPU_NAME ($VRAM MB VRAM)"

# Automatically select the best AI model
if (( VRAM >= 24000 )); then
    MODEL="mixtral-12.7b"  # Best for 24GB+
elif (( VRAM >= 16000 )); then
    MODEL="llama-3.1-8b-instruct"
elif (( VRAM >= 12000 )); then
    MODEL="mistral-7b-instruct"
elif (( VRAM >= 8000 )); then
    MODEL="phi-2"
else
    MODEL="tiny-llama-1b"  # Best for low VRAM
fi

echo "✅ Selected model: $MODEL"

echo "🛠 Setting up GaiaNet..."
rm -rf ~/Gaia ~/gaianet
git clone https://github.com/Debrajkhanra88/Gaia.git ~/Gaia
cd ~/Gaia
chmod +x *.sh

echo "🔧 Building GaiaNet binary..."
export GOPATH=$HOME/go
export PATH=$PATH:/usr/local/go/bin:$GOPATH/bin
mkdir -p $GOPATH
go mod tidy
go build -v -o $HOME/gaianet/bin/gaianet . 2> build_errors.log

if [ ! -f $HOME/gaianet/bin/gaianet ]; then
  echo "❌ Build failed! Check build_errors.log"
  cat build_errors.log
  exit 1
fi

echo "📥 Downloading AI model: $MODEL..."
# Simulate download command (replace with actual model source if available)
mkdir -p ~/models
curl -o ~/models/$MODEL.onnx "https://your-model-hosting.com/$MODEL.onnx"

echo "⏳ Converting $MODEL to TensorRT format..."
trtexec --onnx=~/models/$MODEL.onnx --saveEngine=~/models/$MODEL.trt --fp16

echo "🚀 Starting GaiaNet with CUDA & TensorRT optimizations..."
screen -dmS gaianet_node ~/gaianet/bin/gaianet --model ~/models/$MODEL.trt --cuda --tensorrt

echo "✅ GaiaNet is running in the background with the best model for your system!"
