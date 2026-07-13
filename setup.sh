#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# ComfyUI + FLUX.1-schnell + IPAdapter + Batch Gen - Full Setup
# Dành cho Ubuntu VPS (RTX 3090, user thường)
# ============================================================
# Cách dùng: chmod +x setup.sh && ./setup.sh
# ============================================================

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_DIR"

echo "========================================================================"
echo "  ComfyUI + FLUX.1-schnell + IPAdapter - Batch Gen Setup"
echo "  Repo: $REPO_DIR"
echo "========================================================================"

# Kiểm tra GPU
echo "[1/6] Kiểm tra GPU NVIDIA..."
if command -v nvidia-smi &>/dev/null; then
    nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
else
    echo "WARNING: Không tìm thấy nvidia-smi. Đảm bảo driver NVIDIA đã được cài."
fi

# Cài đặt dependencies hệ thống
echo "[2/6] Cài đặt system dependencies..."
sudo apt-get update -qq
sudo apt-get install -y -qq git python3 python3-venv python3-pip wget curl unzip

# Cài đặt ComfyUI
echo "[3/6] Cài đặt ComfyUI..."
bash "$REPO_DIR/scripts/install_comfyui.sh"

# Cài đặt custom nodes
echo "[4/6] Cài đặt custom nodes..."
bash "$REPO_DIR/scripts/install_custom_nodes.sh"

# Download models
echo "[5/6] Download models..."
bash "$REPO_DIR/scripts/download_models.sh"

# Cài đặt ngrok
echo "[6/6] Cài đặt ngrok..."
bash "$REPO_DIR/scripts/install_ngrok.sh"

echo ""
echo "========================================================================"
echo "  Setup hoàn tất!"
echo ""
echo "  Tiếp theo:"
echo "    1. Cấu hình token ngrok trong config/settings.env"
echo "    2. Đặt ảnh style vào input/styles/"
echo "    3. Chạy: bash scripts/start.sh"
echo "    4. Mở URL ngrok trên máy chính để truy cập ComfyUI"
echo "    5. Chạy batch gen: python scripts/batch_gen.py"
echo "========================================================================"