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

# Ưu tiên trên Colab: python (urllib có sẵn) > curl > wget > huggingface-cli
# Trên Colab: wget hay bị treo với redirect HuggingFace Xet bridge
# Python urllib.request có sẵn, không cần pip install
DOWNLOADER=""
if command -v python3 &>/dev/null; then
    DOWNLOADER="py"
elif command -v curl &>/dev/null; then
    DOWNLOADER="curl"
elif command -v wget &>/dev/null; then
    DOWNLOADER="wget"
elif command -v huggingface-cli &>/dev/null; then
    DOWNLOADER="hf"
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
        py)
            # Python download - dùng env vars để tránh shell injection từ URL
            export PY_URL="$url"
            export PY_OUT="$output_dir/$filename"
            python3 -u << 'PYEOF' 2>&1
import os, sys, time

url = os.environ['PY_URL']
out = os.environ['PY_OUT']
os.makedirs(os.path.dirname(out), exist_ok=True)

# Download to .part first, rename when done
part = out + '.part'

# Try requests first (faster, better progress)
try:
    import requests
    resp = requests.get(url, stream=True, timeout=600, allow_redirects=True)
    resp.raise_for_status()
    total = int(resp.headers.get('content-length', 0))
    downloaded = 0
    start_t = time.time()
    with open(part, 'wb') as f:
        for chunk in resp.iter_content(chunk_size=65536):
            if chunk:
                f.write(chunk)
                downloaded += len(chunk)
                if total:
                    elapsed = max(time.time() - start_t, 0.001)
                    speed = downloaded / elapsed / 1048576
                    pct = min(downloaded * 100 // total, 100)
                    eta = (total - downloaded) / (downloaded / elapsed) if downloaded > 0 else 0
                    sys.stderr.write(f'\r  {pct}% ({downloaded//1048576}MB/{total//1048576}MB) {speed:.0f}MB/s eta {eta:.0f}s')
    os.rename(part, out)
    sys.stderr.write('\n')
    print('OK')
except Exception:
    # Fallback: urllib.request (built-in, no pip needed)
    try:
        import urllib.request
        def reporthook(block, blocksize, totalsize):
            d = block * blocksize
            if totalsize > 0:
                pct = min(d * 100 // totalsize, 100)
                sys.stderr.write(f'\r  {pct}% ({d//1048576}MB/{totalsize//1048576}MB)')
        urllib.request.urlretrieve(url, part, reporthook)
        os.rename(part, out)
        sys.stderr.write('\n')
        print('OK')
    except Exception as e:
        print(f'FAILED: {e}')
        sys.exit(1)
PYEOF
            # Kiểm tra kết quả
            if [ ! -f "$output_dir/$filename" ]; then
                echo "  Python download thất bại, thử curl..."
                DOWNLOADER="curl"
                download_file "$url" "$output_dir" "$filename"
                return $?
            fi
            ;;
        curl)
            curl -L -C - --retry 3 --retry-delay 5 --connect-timeout 30 --max-time 3600 -o "$output_dir/$filename" "$url" 2>&1
            ;;
        wget)
            # --show-progress có thể lỗi trên Colab, dùng -q -O trước
            wget -q -O "$output_dir/$filename" "$url" 2>&1 || \
                wget -q -O "$output_dir/$filename" "$url" --no-check-certificate 2>&1
            ;;
        hf)
            local repo_file=$(echo "$url" | sed 's|https://huggingface.co/||' | sed 's|/resolve/main/| |')
            local repo_id=$(echo "$repo_file" | awk '{print $1}')
            local file_path=$(echo "$repo_file" | awk '{print $2}')
            huggingface-cli download "$repo_id" "$file_path" --local-dir "$output_dir" --local-dir-use-symlinks False --resume-download 2>&1 | tail -1
            ;;
        *)
            echo "  LỖI: Không tìm thấy Python, curl, wget hay huggingface-cli!"
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

# 3. T5-XXL fp16 (bản fp8 không còn tồn tại, dùng fp16 từ flux_text_encoders)
download_file \
    "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp16.safetensors" \
    "$CLIP_DIR" \
    "t5xxl_fp16.safetensors"

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