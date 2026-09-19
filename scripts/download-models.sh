#!/usr/bin/env bash
# 在 AutoDL 实例上运行：一次性下载 MiniMax H3 第一阶段所需的全部模型（约 44GB）
#
# 用法：
#   COMFY_DIR=/root/autodl-tmp/ComfyUI bash download-models.sh
#
# 说明：
#   - hf download 支持断点续传，网络中断后重跑同一条命令即可
#   - 建议先执行 source /etc/network_turbo 开启学术加速
#   - 数据盘请预留 >= 50GB 可用空间

set -euo pipefail

COMFY_DIR="${COMFY_DIR:-/root/autodl-tmp/ComfyUI}"
STAGE_DIR="${STAGE_DIR:-/root/autodl-tmp/h3-dl}"
REPO="Comfy-Org/MiniMax-H3"

# 第一阶段最小集合：fl2va 文生 / 首帧尾帧路线
FILES=(
  "diffusion_models/minimax_h3_fl2va_pruned_int8_convrot.safetensors"
  "text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors"
  "vae/minimax_h3_video_vae_fp16.safetensors"
  "vae/minimax_h3_audio_vae_fp32.safetensors"
  "loras/minimax_h3_fl2v_turbo_8step_v1.0_comfyui_bf16.safetensors"
)

# 可选：省 2.4GB 空间时，把上面 vae/minimax_h3_video_vae_fp16.safetensors
# 换成 vae/minimax_h3_video_vae_int8_convrot.safetensors
# 以后要做参考生视频时，再加下面这两个：
#   "diffusion_models/minimax_h3_ref2va_pruned_int8_convrot.safetensors"
#   "loras/minimax_h3_ref2v_turbo_4step_v0.1_comfyui_bf16.safetensors"

echo "=========================================================="
echo " ComfyUI 目录 : $COMFY_DIR"
echo " 中转目录     : $STAGE_DIR"
echo " 仓库         : $REPO"
echo "=========================================================="

if [ ! -f "$COMFY_DIR/main.py" ]; then
  echo "[错误] $COMFY_DIR 下找不到 main.py。"
  echo "       请先用 COMFY_DIR=<你的 ComfyUI 路径> 重跑本脚本。"
  echo "       查找命令: ls -d /root/autodl-tmp/ComfyUI /root/ComfyUI /root/comfyui 2>/dev/null"
  exit 1
fi

if ! command -v hf >/dev/null 2>&1; then
  echo "[信息] 未检测到 hf 命令，正在安装 huggingface_hub[cli] ..."
  pip install -U "huggingface_hub[cli]"
fi

echo
echo "[1/4] 创建目录 ..."
mkdir -p "$STAGE_DIR"
for sub in diffusion_models text_encoders vae loras; do
  mkdir -p "$COMFY_DIR/models/$sub"
done

echo
echo "[2/4] 开始下载（约 44GB，支持断点续传）..."
ARGS=()
for f in "${FILES[@]}"; do ARGS+=(--include "$f"); done
hf download "$REPO" "${ARGS[@]}" --local-dir "$STAGE_DIR"

echo
echo "[3/4] 搬运到 ComfyUI models 目录 ..."
for sub in diffusion_models text_encoders vae loras; do
  if compgen -G "$STAGE_DIR/$sub/*.safetensors" > /dev/null; then
    cp -v "$STAGE_DIR/$sub/"*.safetensors "$COMFY_DIR/models/$sub/"
  fi
done

echo
echo "[4/4] 校验文件大小（单位 GB）..."
for sub in diffusion_models text_encoders vae loras; do
  for f in "$COMFY_DIR/models/$sub"/*.safetensors; do
    [ -e "$f" ] || continue
    printf "  %6.2f GB  %s\n" "$(awk -v b="$(stat -c%s "$f")" 'BEGIN{printf "%.2f", b/1073741824}')" "$(basename "$f")"
  done
done

echo
echo "清理中转目录 ..."
rm -rf "$STAGE_DIR"

echo
echo "完成。以下文件应已就位："
echo "  diffusion_models/minimax_h3_fl2va_pruned_int8_convrot.safetensors   约 20.97 GB"
echo "  text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors         约 15.69 GB"
echo "  vae/minimax_h3_video_vae_fp16.safetensors                          约  5.21 GB"
echo "  vae/minimax_h3_audio_vae_fp32.safetensors                          约  0.61 GB"
echo "  loras/minimax_h3_fl2v_turbo_8step_v1.0_comfyui_bf16.safetensors    约  1.96 GB"
echo
echo "接着执行: bash start-comfyui.sh"
