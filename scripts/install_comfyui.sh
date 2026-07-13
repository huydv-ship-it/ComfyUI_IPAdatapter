#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_DIR"

COMFYUI_DIR="$REPO_DIR/ComfyUI"
VENV_DIR="$REPO_DIR/venv"

# Clone ComfyUI nếu chưa có
if [ ! -d "$COMFYUI_DIR" ]; then
    echo "[ComfyUI] Cloning ComfyUI..."
    git clone https://github.com/comfyanonymous/ComfyUI.git "$COMFYUI_DIR"
else
    echo "[ComfyUI] ComfyUI đã tồn tại, pull cập nhật..."
    cd "$COMFYUI_DIR"
    git pull
    cd "$REPO_DIR"
fi

# Clone ComfyUI-Manager
echo "[ComfyUI] Cài đặt ComfyUI-Manager..."
MANAGER_DIR="$COMFYUI_DIR/custom_nodes/ComfyUI-Manager"
if [ ! -d "$MANAGER_DIR" ]; then
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git "$MANAGER_DIR"
else
    cd "$MANAGER_DIR" && git pull && cd "$REPO_DIR"
fi

# Kiểm tra python3-venv
if ! python3 -c "import venv" 2>/dev/null; then
    echo "[ComfyUI] python3-venv chưa được cài, đang cài đặt..."
    sudo apt-get install -y -qq python3-venv python3-pip 2>/dev/null || true
fi

# Tạo virtual environment
if [ ! -d "$VENV_DIR" ]; then
    echo "[ComfyUI] Tạo Python venv..."
    if python3 -m venv "$VENV_DIR" 2>/dev/null; then
        echo "[ComfyUI] Venv tạo thành công."
    else
        echo "[ComfyUI] ensurepip lỗi, thử fallback --without-pip..."
        python3 -m venv --without-pip "$VENV_DIR"
        echo "[ComfyUI] Cài pip thủ công..."
        curl -sS https://bootstrap.pypa.io/get-pip.py | "$VENV_DIR/bin/python"
    fi
fi

# Cài đặt requirements ComfyUI
echo "[ComfyUI] Cài pip requirements cho ComfyUI..."
"$VENV_DIR/bin/pip" install --upgrade pip wheel setuptools 2>/dev/null || \
    "$VENV_DIR/bin/python" -m pip install --upgrade pip wheel setuptools
"$VENV_DIR/bin/pip" install -r "$COMFYUI_DIR/requirements.txt" 2>/dev/null || \
    "$VENV_DIR/bin/python" -m pip install -r "$COMFYUI_DIR/requirements.txt"
"$VENV_DIR/bin/pip" install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124 2>/dev/null || \
    "$VENV_DIR/bin/python" -m pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124

echo "[ComfyUI] OK!"