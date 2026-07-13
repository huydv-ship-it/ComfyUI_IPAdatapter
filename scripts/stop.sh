#!/usr/bin/env bash
set -euo pipefail

echo "Dừng ComfyUI và Ngrok..."
pkill -f "ComfyUI/main.py" 2>/dev/null && echo "✓ ComfyUI stopped" || echo "  (ComfyUI not running)"
pkill -f "ngrok" 2>/dev/null && echo "✓ Ngrok stopped" || echo "  (Ngrok not running)"
echo "Done."