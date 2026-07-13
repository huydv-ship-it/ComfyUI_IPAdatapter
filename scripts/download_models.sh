#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
COMFYUI_DIR="$REPO_DIR/ComfyUI"

echo "[Download Models] Tạo thư mục models..."
mkdir -p "$COMFYUI_DIR/models/unet"
mkdir -p "$COMFYUI_DIR/models/clip"
mkdir -p "$COMFYUI_DIR/models/vae"
mkdir -p "$COMFYUI_DIR/models/ipadapter"
mkdir -p "$COMFYUI_DIR/models/controlnet"

# Chọn công cụ download ưu tiên: huggingface-cli > curl > wget > python
DOWNLOADER=""
if command -v huggingface-cli &>/dev/null; then
    DOWNLOADER="hf"
elif command -v curl &>/dev/null; then
    DOWNLOADER="curl"
elif command -v wget &>/dev/null; then
    DOWNLOADER="wget"
elif command -v python3 &>/dev/null; then
    # Kiểm tra requests có sẵn không
    if python3 -c "import requests" 2>/dev/null; then
        DOWNLOADER="py"
    else
        echo "  → Cài requests cho Python fallback..."
        pip install requests -q 2>/dev/null || python3 -m pip install requests -q 2>/dev/null || true
        if python3 -c "import requests" 2>/dev/null; then
            DOWNLOADER="py"
        fi
    fi
fi

download_file() {
    local url="$1"
    local output_dir="$2"
    local filename="$3"
    
    if [ -f "$output_dir/$filename" ]; then
        local size=$(stat -c%s "$output_dir/$filename" 2>/dev/null || stat -f%z "$output_dir/$filename" 2>/dev/null)
        if [ "${size:-0}" -gt 1048576 ]; then
            echo "  → $filename đã tồn tại ($(( size / 1048576 )) MB), bỏ qua..."
            return 0
        fi
    fi
    
    echo "  → Downloading $filename..."
    
    case "$DOWNLOADER" in
        hf)
            # huggingface-cli: parse repo_id và filename từ URL
            local repo_file=$(echo "$url" | sed 's|https://huggingface.co/||' | sed 's|/resolve/main/| |')
            local repo_id=$(echo "$repo_file" | awk '{print $1}')
            local file_path=$(echo "$repo_file" | awk '{print $2}')
            huggingface-cli download "$repo_id" "$file_path" --local-dir "$output_dir" --local-dir-use-symlinks False --resume-download 2>&1 | tail -1
            ;;
        curl)
            curl -L -C - --retry 3 --retry-delay 5 -o "$output_dir/$filename" "$url" 2>&1
            ;;
        wget)
            wget -q --show-progress -O "$output_dir/$filename" "$url" 2>&1 || \
                wget -q -O "$output_dir/$filename" "$url" 2>&1
            ;;
        py)
            python3 -c "
import requests, sys, os
url = '$url'
out = '$output_dir/$filename'
os.makedirs(os.path.dirname(out), exist_ok=True)
resp = requests.get(url, stream=True, timeout=300)
resp.raise_for_status()
total = int(resp.headers.get('content-length', 0))
downloaded = 0
with open(out, 'wb') as f:
    for chunk in resp.iter_content(chunk_size=8192):
        f.write(chunk)
        downloaded += len(chunk)
        if total:
            pct = downloaded * 100 // total
            sys.stderr.write(f'\r  {pct}% ({downloaded//1048576}MB/{total//1048576}MB)')
sys.stderr.write('\n')
" 2>&1
            ;;
        *)
            echo "  LỖI: Không tìm thấy curl, wget hay python3 để download!"
            return 1
            ;;
    esac
    
    # Verify file không bị lỗi (check size > 1MB)
    local size=$(stat -c%s "$output_dir/$filename" 2>/dev/null || stat -f%z "$output_dir/$filename" 2>/dev/null)
    if [ "${size:-0}" -lt 1048576 ]; then
        echo "  LỖI: $filename quá nhỏ (${size:-0} bytes), download thất bại!"
        rm -f "$output_dir/$filename" 2>/dev/null
        return 1
    fi
    echo "  → OK! ($(( size / 1048576 )) MB)"
}

echo ""
echo "=================================================="
echo "  Download FLUX.1-schnell + IPAdapter models"
echo "=================================================="
echo ""

# Danh sách models cần tải (hỗ trợ cả ComfyUI cũ và mới)
# Model paths auto-detect: diffusion_models (mới) hoặc unet (cũ)
if [ -d "$COMFYUI_DIR/models/diffusion_models" ]; then
    UNET_DIR="$COMFYUI_DIR/models/diffusion_models"
else
    UNET_DIR="$COMFYUI_DIR/models/unet"
fi
if [ -d "$COMFYUI_DIR/models/text_encoders" ]; then
    CLIP_DIR="$COMFYUI_DIR/models/text_encoders"
else
    CLIP_DIR="$COMFYUI_DIR/models/clip"
fi
mkdir -p "$UNET_DIR" "$CLIP_DIR"

# 1. FLUX.1-schnell UNET (fp8) - dùng source từ Comfy-Org (tin cậy hơn)
download_file \
    "https://huggingface.co/Comfy-Org/flux1-schnell/resolve/main/flux1-schnell-fp8.safetensors" \
    "$UNET_DIR" \
    "flux1-schnell-fp8.safetensors"

# 2. CLIP-L
download_file \
    "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors" \
    "$CLIP_DIR" \
    "clip_l.safetensors"

# 3. T5-XXL fp8
download_file \
    "https://huggingface.co/Kijai/flux-fp8/resolve/main/t5xxl_fp8_e4m3fn.safetensors" \
    "$CLIP_DIR" \
    "t5xxl_fp8.safetensors"

# 4. VAE (ae.safetensors)
download_file \
    "https://huggingface.co/black-forest-labs/FLUX.1-schnell/resolve/main/ae.safetensors" \
    "$COMFYUI_DIR/models/vae" \
    "ae.safetensors"

# 5. CLIP Vision (SigLIP cho IPAdapter) - cần cho IPAdapter hoạt động
mkdir -p "$COMFYUI_DIR/models/clip_vision"
download_file \
    "https://huggingface.co/Comfy-Org/sigclip_vision_384/resolve/main/sigclip_vision_patch14_384.safetensors" \
    "$COMFYUI_DIR/models/clip_vision" \
    "sigclip_vision_patch14_384.safetensors"

# 6. IPAdapter FLUX - thử nhiều source
mkdir -p "$COMFYUI_DIR/models/ipadapter"
download_file \
    "https://huggingface.co/h94/IP-Adapter-Flux/resolve/main/ip-adapter-flux-fp8.safetensors" \
    "$COMFYUI_DIR/models/ipadapter" \
    "ip-adapter-flux-fp8.safetensors"

echo ""
echo "=================================================="
echo "  Download hoàn tất!"
echo "=================================================="

# Show tổng dung lượng
echo ""
echo "Thống kê models:"
echo "  UNET:       $(ls -lh "$COMFYUI_DIR/models/unet/" 2>/dev/null | awk '{print $5, $NF}')"
echo "  CLIP:       $(ls -lh "$COMFYUI_DIR/models/clip/" 2>/dev/null | awk '{print $5, $NF}')"
echo "  VAE:        $(ls -lh "$COMFYUI_DIR/models/vae/" 2>/dev/null | awk '{print $5, $NF}')"
echo "  IPAdapter:  $(ls -lh "$COMFYUI_DIR/models/ipadapter/" 2>/dev/null | awk '{print $5, $NF}')"
echo ""
echo "Tổng dung lượng:"
du -sh "$COMFYUI_DIR/models/unet" "$COMFYUI_DIR/models/clip" "$COMFYUI_DIR/models/vae" "$COMFYUI_DIR/models/ipadapter" 2>/dev/null