#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# run.sh - 1 file để chạy TẤT CẢ
# Clone + Setup + Cấu hình + Start + Gen 200 ảnh
# Chỉ cần: bash run.sh
# ============================================================

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_DIR"

# Màu sắc
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; }
info() { echo -e "${CYAN}[i]${NC} $1"; }
sep()  { echo "──────────────────────────────────────────────"; }

# -----------------------------------------------------------
# PHASE 1 - Kiểm tra & Setup
# -----------------------------------------------------------
setup_phase() {
    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║   🚀 ComfyUI + FLUX + IPAdapter - RUN           ║"
    echo "║   1 file duy nhất - chạy từ A → Z              ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo ""

    sep
    echo "🔍 PHASE 1: Kiểm tra môi trường..."

    # Kiểm tra GPU
    if command -v nvidia-smi &>/dev/null; then
        GPU_INFO=$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null | head -1)
        log "GPU: $GPU_INFO"
    else
        warn "Không tìm thấy NVIDIA GPU! Tiếp tục nhưng có thể lỗi..."
    fi

    # Kiểm tra git
    if ! command -v git &>/dev/null; then
        info "Cài đặt git..."
        sudo apt-get update -qq && sudo apt-get install -y -qq git
    fi
    log "Git: $(git --version)"

    # Kiểm tra python
    if ! command -v python3 &>/dev/null; then
        info "Cài đặt python3..."
        sudo apt-get update -qq && sudo apt-get install -y -qq python3
    fi
    log "Python: $(python3 --version)"

    # Kiểm tra python3-venv
    if ! python3 -c "import venv" 2>/dev/null; then
        info "Cài đặt python3-venv python3-pip..."
        sudo apt-get update -qq && sudo apt-get install -y -qq python3-venv python3-pip
    fi

    # Kiểm tra đang chạy bằng root không
    if [ "$EUID" = "0" ] 2>/dev/null || [ "$(id -u)" = "0" ] 2>/dev/null; then
        warn "⚠️  BẠN ĐANG CHẠY BẰNG ROOT! Nên dùng user thường."
        warn "   Tạo user mới: sudo adduser ubuntu && sudo usermod -aG sudo ubuntu && su - ubuntu"
        warn "   Hoặc: export COMFYUI_NONROOT=1 (bỏ qua cảnh báo)"
    fi

    # Đã setup chưa?
    if [ -f "$REPO_DIR/.setup_done" ]; then
        log "Setup đã hoàn thành trước đó, bỏ qua PHASE 1."
        return 0
    fi

    sep
    echo "🔧 PHASE 1a: Cài đặt system dependencies..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq wget curl unzip

    sep
    echo "🔧 PHASE 1b: Cài đặt ComfyUI..."
    bash "$REPO_DIR/scripts/install_comfyui.sh"

    sep
    echo "🔧 PHASE 1c: Cài đặt custom nodes..."
    bash "$REPO_DIR/scripts/install_custom_nodes.sh"

    sep
    echo "🔧 PHASE 1d: Download models (có thể mất 15-30 phút)..."
    bash "$REPO_DIR/scripts/download_models.sh"

    sep
    echo "🔧 PHASE 1e: Cài đặt ngrok..."
    bash "$REPO_DIR/scripts/install_ngrok.sh"

    # Đánh dấu đã setup
    touch "$REPO_DIR/.setup_done"
    log "✅ PHASE 1 HOÀN TẤT!"
}

# -----------------------------------------------------------
# PHASE 2 - Cấu hình ngrok token
# -----------------------------------------------------------
configure_phase() {
    sep
    echo "🔑 PHASE 2: Cấu hình Ngrok Token"

    # Load settings
    SETTINGS="$REPO_DIR/config/settings.env"
    NGROK_TOKEN=""
    if [ -f "$SETTINGS" ]; then
        source "$SETTINGS" 2>/dev/null || true
        NGROK_TOKEN="${NGROK_TOKEN:-}"
    fi

    # Kiểm tra token đã config chưa
    if [ -n "$NGROK_TOKEN" ] && [ "$NGROK_TOKEN" != "your-ngrok-auth-token-here" ]; then
        log "Ngrok token đã được cấu hình sẵn."
    else
        warn "🟡 CHƯA CÓ NGROK TOKEN!"
        echo ""
        echo "  Lấy token tại: https://dashboard.ngrok.com/get-started/your-authtoken"
        echo "  (Đăng nhập → copy token)"
        echo ""
        echo "  Nhập token của bạn (hoặc Enter để bỏ qua, sẽ dùng free tunnel):"
        read -p "  → " USER_TOKEN

        if [ -n "$USER_TOKEN" ]; then
            NGROK_TOKEN="$USER_TOKEN"
            # Ghi vào settings.env
            if grep -q "^NGROK_TOKEN=" "$SETTINGS" 2>/dev/null; then
                sed -i "s/^NGROK_TOKEN=.*/NGROK_TOKEN=\"$USER_TOKEN\"/" "$SETTINGS"
            else
                echo "NGROK_TOKEN=\"$USER_TOKEN\"" >> "$SETTINGS"
            fi
            log "Token đã được lưu!"
        else
            warn "Bỏ qua cấu hình token. Ngrok sẽ dùng free tunnel."
        fi
    fi

    # Apply token
    if [ -n "$NGROK_TOKEN" ] && [ "$NGROK_TOKEN" != "your-ngrok-auth-token-here" ] && [ -f "$REPO_DIR/ngrok" ]; then
        "$REPO_DIR/ngrok" config add-authtoken "$NGROK_TOKEN" 2>/dev/null || true
    fi
}

# -----------------------------------------------------------
# PHASE 3 - Chuẩn bị ảnh style
# -----------------------------------------------------------
prepare_styles_phase() {
    sep
    echo "🖼️  PHASE 3: Chuẩn bị ảnh Style"

    STYLE_DIR="$REPO_DIR/input/styles"
    mkdir -p "$STYLE_DIR"

    # Đếm ảnh hiện có
    STYLE_COUNT=$(find "$STYLE_DIR" -maxdepth 1 -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.webp" \) 2>/dev/null | wc -l)

    if [ "$STYLE_COUNT" -gt 0 ]; then
        log "Đã có $STYLE_COUNT ảnh style trong $STYLE_DIR"
        return 0
    fi

    warn "🟡 CHƯA CÓ ẢNH STYLE NÀO!"
    echo ""
    echo "  Bạn cần đặt 20 ảnh style vào thư mục:"
    echo "    $STYLE_DIR"
    echo ""
    echo "  Hỗ trợ: .png, .jpg, .jpeg, .webp"
    echo "  (Ví dụ: anime_style.png, oil_painting.jpg, ...)"
    echo ""
    echo "  Bạn có thể:"
    echo "    1. Dùng scp từ máy tính:"
    echo "       scp -P PORT *.png user@VPS:$STYLE_DIR/"
    echo "    2. Dùng rsync:"
    echo "       rsync -avP style_images/ user@VPS:$STYLE_DIR/"
    echo "    3. Dùng curl/wget để tải từ URL"
    echo ""

    read -p "  Nhấn Enter sau khi đã đặt ảnh xong... "

    # Kiểm tra lại
    STYLE_COUNT=$(find "$STYLE_DIR" -maxdepth 1 -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.webp" \) 2>/dev/null | wc -l)
    if [ "$STYLE_COUNT" -gt 0 ]; then
        log "Đã tìm thấy $STYLE_COUNT ảnh style!"
    else
        warn "Vẫn chưa có ảnh nào. Batch gen sẽ bỏ qua, nhưng bạn có thể dùng ComfyUI web."
    fi
}

# -----------------------------------------------------------
# PHASE 4 - Start ComfyUI + Ngrok
# -----------------------------------------------------------
start_phase() {
    sep
    echo "▶️  PHASE 4: Khởi động ComfyUI + Ngrok Tunnel"

    # Kill old processes
    pkill -f "ComfyUI/main.py" 2>/dev/null || true
    pkill -f "ngrok.*8188" 2>/dev/null || true
    sleep 1

    mkdir -p "$REPO_DIR/logs"

    # Start ComfyUI
    cd "$REPO_DIR/ComfyUI"
    log "Starting ComfyUI (port 8188)..."
    "$REPO_DIR/venv/bin/python" main.py \
        --port 8188 \
        --listen 127.0.0.1 \
        --highvram \
        > "$REPO_DIR/logs/comfyui.log" 2>&1 &
    COMFYUI_PID=$!

    # Start Ngrok
    cd "$REPO_DIR"
    if [ -f "$REPO_DIR/ngrok" ]; then
        log "Starting ngrok tunnel..."
        "$REPO_DIR/ngrok" http 8188 --log=stdout > "$REPO_DIR/logs/ngrok.log" 2>&1 &
        NGROK_PID=$!
    else
        warn "Ngrok không tìm thấy, bỏ qua tunnel."
        NGROK_PID=""
    fi

    # Đợi ComfyUI sẵn sàng
    echo ""
    info "Đợi ComfyUI khởi động..."
    for i in $(seq 1 30); do
        if curl -s "http://127.0.0.1:8188" >/dev/null 2>&1; then
            log "ComfyUI sẵn sàng!"
            break
        fi
        if [ "$i" -eq 30 ]; then
            err "ComfyUI không khởi động được. Kiểm tra logs/comfyui.log"
        fi
        sleep 2
    done

    # Lấy URL ngrok
    NGROK_URL=""
    if [ -n "$NGROK_PID" ]; then
        info "Đợi ngrok tunnel..."
        sleep 3
        for i in $(seq 1 15); do
            API=$(curl -s http://127.0.0.1:4040/api/tunnels 2>/dev/null || echo "")
            NGROK_URL=$(echo "$API" | python3 -c "
import sys, json
try:
    tunnels = json.load(sys.stdin).get('tunnels', [])
    print(tunnels[0]['public_url'] if tunnels else '')
except:
    print('')
" 2>/dev/null || true)
            if [ -n "$NGROK_URL" ]; then
                break
            fi
            sleep 2
        done
    fi

    # Hiển thị kết quả
    echo ""
    sep
    echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  🎉 MỞ TRÌNH DUYỆT (BROWSER)                   ║${NC}"
    echo -e "${GREEN}║                                               ║${NC}"
    if [ -n "$NGROK_URL" ]; then
        echo -e "${GREEN}║  ${CYAN}$NGROK_URL${NC}  ║${NC}"
    else
        echo -e "${GREEN}║  ${YELLOW}http://VPS_IP:8188${NC}  ║${NC}"
    fi
    echo -e "${GREEN}║                                               ║${NC}"
    echo -e "${GREEN}║  ComfyUI PID: $COMFYUI_PID              ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
    sep

    # Lưu URL
    echo "$NGROK_URL" > "$REPO_DIR/logs/ngrok_url.txt"
    echo "$COMFYUI_PID" > "$REPO_DIR/logs/comfyui.pid"
}

# -----------------------------------------------------------
# PHASE 5 - Batch Gen 200 ảnh
# -----------------------------------------------------------
gen_phase() {
    sep
    echo "🎨 PHASE 5: Batch Gen 200 ảnh (20 style × 10 prompts)"

    # Đếm style images
    STYLE_DIR="$REPO_DIR/input/styles"
    STYLE_COUNT=$(find "$STYLE_DIR" -maxdepth 1 -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.webp" \) 2>/dev/null | wc -l)

    if [ "$STYLE_COUNT" -eq 0 ]; then
        warn "Không có ảnh style nào để gen."
        warn "Đặt ảnh vào $STYLE_DIR và chạy lại: python scripts/batch_gen.py"
        return 0
    fi

    echo ""
    echo "  Số style: $STYLE_COUNT"
    echo "  Số ảnh mỗi style: 10"
    echo "  Tổng: $((STYLE_COUNT * 10)) ảnh"
    echo ""

    echo "  Bạn có muốn gen ngay bây giờ không?"
    read -p "  (y/N): " GEN_NOW

    if [ "$GEN_NOW" = "y" ] || [ "$GEN_NOW" = "Y" ]; then
        log "Bắt đầu batch gen..."
        cd "$REPO_DIR"
        "$REPO_DIR/venv/bin/python" "$REPO_DIR/scripts/batch_gen.py"
    else
        info "Bỏ qua batch gen. Chạy sau: python scripts/batch_gen.py"
    fi
}

# -----------------------------------------------------------
# MAIN
# -----------------------------------------------------------
main() {
    setup_phase
    configure_phase
    prepare_styles_phase
    start_phase
    gen_phase

    echo ""
    sep
    echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ✅ HOÀN TẤT!                                   ║${NC}"
    echo -e "${GREEN}║                                               ║${NC}"
    echo -e "${GREEN}║  📂 Output:  $REPO_DIR/output/        ║${NC}"
    echo -e "${GREEN}║  📋 Logs:    $REPO_DIR/logs/          ║${NC}"
    echo -e "${GREEN}║                                               ║${NC}"
    echo -e "${GREEN}║  Để dừng:   bash scripts/stop.sh               ║${NC}"
    echo -e "${GREEN}║  Gen lại:   python scripts/batch_gen.py        ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
    sep
    echo ""
}

main "$@"