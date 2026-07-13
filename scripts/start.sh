#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
COMFYUI_DIR="$REPO_DIR/ComfyUI"
VENV_DIR="$REPO_DIR/venv"
NGROK="$REPO_DIR/ngrok"

# Load settings
SETTINGS="$REPO_DIR/config/settings.env"
if [ -f "$SETTINGS" ]; then
    set -a
    source "$SETTINGS"
    set +a
fi

# Default values
NGROK_TOKEN="${NGROK_TOKEN:-}"
COMFYUI_PORT="${COMFYUI_PORT:-8188}"
COMFYUI_EXTRA_ARGS="${COMFYUI_EXTRA_ARGS:---highvram}"

echo "========================================================================"
echo "  Starting ComfyUI + Ngrok Tunnel"
echo "  Port: $COMFYUI_PORT"
echo "  VRAM mode: $COMFYUI_EXTRA_ARGS"
echo "========================================================================"

# Kill old processes
echo "  → Dọn dẹp tiến trình cũ..."
pkill -f "ComfyUI/main.py" 2>/dev/null || true
pkill -f "ngrok.*$COMFYUI_PORT" 2>/dev/null || true
sleep 1

# Kiểm tra venv
if [ ! -f "$VENV_DIR/bin/python" ]; then
    echo "  → Venv chưa tồn tại, tạo mới..."
    bash "$REPO_DIR/scripts/install_comfyui.sh"
fi

# Auth ngrok nếu có token
NGROK_CMD=$(command -v ngrok 2>/dev/null || echo "$NGROK")
if [ -n "$NGROK_TOKEN" ] && [ -f "$NGROK_CMD" ]; then
    echo "  → Cấu hình ngrok token..."
    "$NGROK_CMD" config add-authtoken "$NGROK_TOKEN" 2>/dev/null || true
fi

# Start ComfyUI
echo "  → Starting ComfyUI backend..."
cd "$COMFYUI_DIR"
"$VENV_DIR/bin/python" main.py \
    --port "$COMFYUI_PORT" \
    --listen 127.0.0.1 \
    $COMFYUI_EXTRA_ARGS \
    > "$REPO_DIR/logs/comfyui.log" 2>&1 &
COMFYUI_PID=$!

# Start ngrok tunnel
echo "  → Starting ngrok tunnel..."
cd "$REPO_DIR"
mkdir -p logs
"$NGROK" http "$COMFYUI_PORT" \
    --log=stdout \
    > "$REPO_DIR/logs/ngrok.log" 2>&1 &
NGROK_PID=$!

# Wait for services
echo "  → Đợi ComfyUI khởi động..."
sleep 5
for i in $(seq 1 30); do
    if curl -s "http://127.0.0.1:$COMFYUI_PORT" >/dev/null 2>&1; then
        echo "  ✓ ComfyUI đã sẵn sàng tại http://127.0.0.1:$COMFYUI_PORT"
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo "  ✗ ComfyUI không khởi động kịp, kiểm tra logs/comfyui.log"
    fi
    sleep 2
done

# Get ngrok URL
echo "  → Đợi ngrok tunnel..."
sleep 3
NGROK_URL=""
for i in $(seq 1 15); do
    NGROK_API=$(curl -s http://127.0.0.1:4040/api/tunnels 2>/dev/null)
    NGROK_URL=$(echo "$NGROK_API" | python3 -c "import sys,json; tunnels=json.load(sys.stdin).get('tunnels',[]); print(tunnels[0]['public_url'] if tunnels else '')" 2>/dev/null || true)
    if [ -n "$NGROK_URL" ]; then
        break
    fi
    sleep 2
done

echo ""
echo "========================================================================"
echo "  🚀 MỞ TRÌNH DUYỆT: $NGROK_URL"
echo "========================================================================"
echo ""
echo "  PIDs: ComfyUI=$COMFYUI_PID, Ngrok=$NGROK_PID"
echo "  Logs:"
echo "    ComfyUI: $REPO_DIR/logs/comfyui.log"
echo "    Ngrok:   $REPO_DIR/logs/ngrok.log"
echo ""
echo "  Để dừng: pkill -f 'ComfyUI/main.py' && pkill -f ngrok"
echo ""

# Save URL to file
echo "$NGROK_URL" > "$REPO_DIR/logs/ngrok_url.txt"