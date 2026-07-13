# ComfyUI IPAdapter - Batch Gen Setup

> Setup nhanh ComfyUI + FLUX.1-schnell + IPAdapter trên VPS Ubuntu (RTX 3090)
> Gen batch 200 ảnh từ 20 ảnh style, truy cập qua ngrok tunnel

## 🚀 Kiến trúc

```
VPS Ubuntu (RTX 3090 24GB)
├── ComfyUI (ComfyUI/)
├── models/
│   ├── unet/flux1-schnell-fp8.safetensors
│   ├── clip/clip_l.safetensors + t5xxl_fp8.safetensors
│   ├── vae/ae.safetensors
│   └── ipadapter/ip-adapter-flux-fp8.safetensors
├── input/styles/          ← 20 ảnh style của bạn
├── output/                ← 200 ảnh gen ra
├── venv/                  ← Python virtual environment
├── ngrok                  ← Tunnel binary
├── scripts/
│   ├── install_comfyui.sh
│   ├── install_custom_nodes.sh
│   ├── download_models.sh
│   ├── install_ngrok.sh
│   ├── start.sh           ← Start ComfyUI + ngrok
│   └── batch_gen.py       ← Script gen 200 ảnh
└── config/
    ├── settings.env       ← Config (token, port, ...)
    └── workflows/
        └── flux_ipadapter_batch.json
```

## 📋 Yêu cầu

- **VPS**: Ubuntu 22.04+, RAM ≥ 32GB (khuyến nghị)
- **GPU**: NVIDIA RTX 3090 (24GB VRAM) hoặc tương đương
- **Disk**: ≥ 50GB free (models ~25GB)
- **Software**: NVIDIA driver (cu124), git, python3, pip

## ⚡ Cách dùng nhanh (CHỈ 1 LỆNH DUY NHẤT)

```bash
# Trên VPS Ubuntu của bạn:
git clone https://github.com/huydv-ship-it/ComfyUI_IPAdatapter.git
cd ComfyUI_IPAdatapter

# CHẠY 1 LỆNH NÀY:
bash run.sh
```

Script `run.sh` sẽ tự động:
1. Kiểm tra GPU, cài git/python nếu thiếu
2. Clone ComfyUI, tạo venv, cài PyTorch
3. Cài IPAdapter-Plus và các custom nodes
4. Download toàn bộ models (FLUX, CLIP, T5, VAE, IPAdapter) ~25GB
5. Cài đặt ngrok tunnel
6. **Hỏi bạn nhập Ngrok Token** (lấy từ https://dashboard.ngrok.com)
7. **Chờ bạn đặt 20 ảnh style** vào thư mục `input/styles/`
8. Start ComfyUI + ngrok, in ra URL để mở browser
9. **Hỏi có muốn gen 200 ảnh ngay không** (gõ `y` để chạy)

> ✅ **Xong!** Mở URL trên máy tính, bạn có ComfyUI web + 200 ảnh gen sẵn.

## 🔧 Cài đặt thủ công (từng bước)

### 1. Cài đặt ComfyUI

```bash
bash scripts/install_comfyui.sh
```

Script này sẽ:
- Clone ComfyUI vào `ComfyUI/`
- Cài đặt ComfyUI-Manager
- Tạo Python venv
- Cài PyTorch cu124 + requirements

### 2. Cài đặt Custom Nodes

```bash
bash scripts/install_custom_nodes.sh
```

Các nodes được cài:
- **ComfyUI_IPAdapter_plus** - IPAdapter cho style transfer
- **efficiency-nodes-comfyui** - Nodes tiện ích

### 3. Download Models

```bash
bash scripts/download_models.sh
```

Models được tải về (~25GB tổng cộng):
| Model | File | Dung lượng |
|-------|------|-----------|
| UNET | `flux1-schnell-fp8.safetensors` | ~7 GB |
| CLIP-L | `clip_l.safetensors` | ~246 MB |
| T5-XXL | `t5xxl_fp8.safetensors` | ~9 GB |
| VAE | `ae.safetensors` | ~335 MB |
| IPAdapter | `ip-adapter-flux-fp8.safetensors` | ~2 GB |

### 4. Cài đặt Ngrok

```bash
bash scripts/install_ngrok.sh
ngrok config add-authtoken YOUR_TOKEN
```

Lấy token tại: https://dashboard.ngrok.com/get-started/your-authtoken

### 5. Cấu hình

Sửa file `config/settings.env`:

```env
NGROK_TOKEN="your-ngrok-auth-token-here"
COMFYUI_PORT=8188
COMFYUI_EXTRA_ARGS="--highvram"
```

## ▶️ Sử dụng

### Khởi động ComfyUI + Ngrok

```bash
bash scripts/start.sh
```

Kết quả: Mở URL dạng `https://xxxx.ngrok-free.app` trên máy tính chính.
Từ ComfyUI web, bạn có thể load workflow từ `config/workflows/flux_ipadapter_batch.json`.

### Batch Gen 200 ảnh

**Bước 1:** Đặt 20 ảnh style vào `input/styles/`
- Hỗ trợ: `.png`, `.jpg`, `.jpeg`, `.webp`
- Tên ảnh = tên style (ví dụ: `anime_style.png`, `oil_painting.jpg`)

**Bước 2:** Chạy gen

```bash
# Gen full 200 ảnh (20 style × 10 seeds)
python scripts/batch_gen.py

# Gen 5 ảnh mỗi style (tổng 100 ảnh)
python scripts/batch_gen.py --num-per-style 5

# Custom seed
python scripts/batch_gen.py --seed-start 1000

# Custom prompts
python scripts/batch_gen.py --prompts \
    "A beautiful portrait, oil painting style" \
    "A futuristic cityscape, neon lights" \
    "A serene landscape, watercolor"

# Dry run (xem kế hoạch trước khi gen)
python scripts/batch_gen.py --dry-run
```

Kết quả: 200 ảnh trong `output/` với tên `{style_name}_seed{seed}.png`

### Workflow

File `config/workflows/flux_ipadapter_batch.json` là workflow template:

```
LoadImage → IPAdapterApply → KSampler → VAEDecode → SaveImage
              ↓                   ↑
         IPAdapterModel      DualCLIPLoader
              ↓                   ↓
         UNETLoader         CLIPTextEncode (prompt)
```

Thông số kỹ thuật:
- **Model**: FLUX.1-schnell-fp8
- **Steps**: 4 (schnell)
- **CFG**: 1.0
- **Sampler**: euler
- **Resolution**: 1024×1024
- **IPAdapter weight**: 0.7
- **IPAdapter noise**: 0.4

> 💡 **Tip:** Bạn có thể export workflow từ ComfyUI web và thay thế file JSON này.

## 📂 Cấu trúc output

```
output/
├── anime_style_seed42.png
├── anime_style_seed43.png
├── anime_style_seed44.png
├── ...
├── oil_painting_seed42.png
├── ...
└── sketch_style_seed142.png   (tổng 200 files)
```

## 🛑 Dừng dịch vụ

```bash
pkill -f "ComfyUI/main.py"
pkill -f "ngrok"
```

## ⚙️ Tùy chỉnh

### Thông số gen (trong `config/settings.env`)

| Biến | Mô tả | Default |
|------|-------|---------|
| `NGROK_TOKEN` | Ngrok auth token | - |
| `COMFYUI_PORT` | ComfyUI port | 8188 |
| `COMFYUI_EXTRA_ARGS` | VRAM mode | `--highvram` |
| `NUM_IMAGES_PER_STYLE` | Số ảnh mỗi style | 10 |
| `SEED_START` | Seed bắt đầu | 42 |
| `DEFAULT_PROMPT_TEMPLATE` | Prompt template | (tự động) |

### Prompt

Mỗi ảnh style được gen với 1 prompt khác nhau. Mặc định có 20 prompts mẫu.
Bạn có thể chỉnh sửa trong `scripts/batch_gen.py` (biến `DEFAULT_PROMPTS`) hoặc truyền qua CLI.

### Workflow

Sau khi ComfyUI chạy, bạn có thể:
1. Mở ComfyUI web qua URL ngrok
2. Load workflow template hoặc kéo thả nodes
3. Export workflow JSON (Settings → Save API Format)
4. Copy vào `config/workflows/` và đổi tên

## 📝 Ghi chú

- FLUX.1-schnell chỉ cần **4 steps** → gen rất nhanh (~2-3s/ảnh trên RTX 3090)
- Tổng 200 ảnh: ~10-15 phút
- VRAM sử dụng: ~20-22 GB (an toàn trên RTX 3090)
- Nếu gặp lỗi VRAM: sửa `COMFYUI_EXTRA_ARGS="--normalvram"` trong settings.env
- Ảnh được upload qua API → lưu trong `input/ComfyUI/` tự động, không cần lo

## 🔗 Liên kết

- [ComfyUI](https://github.com/comfyanonymous/ComfyUI)
- [IPAdapter-Plus](https://github.com/cubiq/ComfyUI_IPAdapter_plus)
- [FLUX.1](https://huggingface.co/black-forest-labs/FLUX.1-schnell)
- [Ngrok](https://ngrok.com)