#!/usr/bin/env bash
# 在 AutoDL 实例上运行：一次性下载 MiniMax H3 第一阶段所需的全部模型
#
# 用法：
#   COMFY_DIR=/root/autodl-tmp/ComfyUI bash download-models.sh
#
# 可选环境变量：
#   DIFF_MODEL=int8|fp8   强制指定扩散模型量化版本（默认按 torch 的 CUDA 版本自动选）
#   EXTRA_LORA=1          额外下载 4 步加速 LoRA（多 1.96GB，可选）
#   SKIP_EMBEDDINGS=1     不下载 10 个风格 embeddings（默认下，只有 10.7MB）
#   STAGE_DIR=...         中转目录，默认 /root/autodl-tmp/h3-dl
#
# 说明：
#   - hf download 支持断点续传，网络中断后重跑同一条命令即可
#   - 建议先执行 source /etc/network_turbo 开启学术加速
#   - 数据盘请预留 >= 55GB 可用空间

set -euo pipefail

COMFY_DIR="${COMFY_DIR:-/root/autodl-tmp/ComfyUI}"
STAGE_DIR="${STAGE_DIR:-/root/autodl-tmp/h3-dl}"
REPO="Comfy-Org/MiniMax-H3"
EXTRA_LORA="${EXTRA_LORA:-0}"
SKIP_EMBEDDINGS="${SKIP_EMBEDDINGS:-0}"

# ---------------------------------------------------------------------------
# 第一步：先定扩散模型用哪个量化版本
#
# 官方 Comfy-Org/MiniMax-H3 仓库 README 原文：
#   "For diffusion models prefer int8_convrot if you are able to use pytorch
#    with cu130. fp8_scaled should only be used if you cannot use int8_convrot."
#
# 也就是说 int8_convrot 需要 cu130。社区有报告称 cu128 下 int8 推理内核会
# 静默失效、速度慢约 3 倍——不报错，只是慢。所以这里必须按实际 CUDA 版本选，
# 不能无脑下 int8。两个文件体积几乎相同（20.97 vs 20.96 GB），换掉零成本。
# ---------------------------------------------------------------------------
DIFF_MODEL="${DIFF_MODEL:-}"
if [ -z "$DIFF_MODEL" ]; then
  CUDA_VER="$(python -c 'import torch;print(torch.version.cuda or "")' 2>/dev/null || echo "")"
  case "$CUDA_VER" in
    13*) DIFF_MODEL=int8 ;;
    "")  DIFF_MODEL=fp8;  CUDA_VER="检测不到" ;;
    *)   DIFF_MODEL=fp8 ;;
  esac
  echo "[信息] 检测到 torch 的 CUDA 版本: ${CUDA_VER}  →  扩散模型选 ${DIFF_MODEL}"
  if [ "$DIFF_MODEL" = "fp8" ]; then
    echo "       官方指引：cu130 才用 int8_convrot，否则用 fp8_scaled。"
    echo "       若你的环境其实是 cu13x 但没被识别到，用 DIFF_MODEL=int8 强制指定。"
  fi
fi

case "$DIFF_MODEL" in
  int8) DIFF_FILE="minimax_h3_fl2va_pruned_int8_convrot.safetensors" ;;
  fp8)  DIFF_FILE="minimax_h3_fl2va_pruned_fp8_scaled.safetensors" ;;
  *)    echo "[错误] DIFF_MODEL 只能是 int8 或 fp8，收到: $DIFF_MODEL"; exit 1 ;;
esac

# ---------------------------------------------------------------------------
# 第二步：拼文件清单
# ---------------------------------------------------------------------------
FILES=(
  "diffusion_models/$DIFF_FILE"
  "text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors"
  "vae/minimax_h3_video_vae_fp16.safetensors"
  "vae/minimax_h3_audio_vae_fp32.safetensors"
  "loras/minimax_h3_fl2v_turbo_8step_v1.0_comfyui_bf16.safetensors"
)

# 10 个风格 embeddings，合计只有 10.7MB，属于白给的能力，默认下
if [ "$SKIP_EMBEDDINGS" != "1" ]; then
  FILES+=("embeddings/*")
fi

# 4 步加速 LoRA（768p 专用），比 8 步更快，可选
if [ "$EXTRA_LORA" = "1" ]; then
  FILES+=("loras/minimax_h3_fl2v_turbo_4step_v1.0_768p_comfyui_bf16.safetensors")
fi

# 以后要做参考生视频（Ref2VA）时，再加下面这两个：
#   "diffusion_models/minimax_h3_ref2va_pruned_int8_convrot.safetensors"
#   "loras/minimax_h3_ref2v_turbo_4step_v0.1_comfyui_bf16.safetensors"

echo "=========================================================="
echo " ComfyUI 目录 : $COMFY_DIR"
echo " 中转目录     : $STAGE_DIR"
echo " 仓库         : $REPO"
echo " 扩散模型     : $DIFF_FILE"
echo " embeddings   : $([ "$SKIP_EMBEDDINGS" = "1" ] && echo 跳过 || echo 下（10 个，约 10.7MB）)"
echo " 4 步 LoRA    : $([ "$EXTRA_LORA" = "1" ] && echo 下 || echo 跳过)"
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
for sub in diffusion_models text_encoders vae loras embeddings; do
  mkdir -p "$COMFY_DIR/models/$sub"
done

echo
echo "[2/4] 开始下载（支持断点续传）..."
ARGS=()
for f in "${FILES[@]}"; do ARGS+=(--include "$f"); done
hf download "$REPO" "${ARGS[@]}" --local-dir "$STAGE_DIR"

echo
echo "[3/4] 搬运到 ComfyUI models 目录 ..."
for sub in diffusion_models text_encoders vae loras embeddings; do
  if compgen -G "$STAGE_DIR/$sub/*.safetensors" > /dev/null; then
    cp -v "$STAGE_DIR/$sub/"*.safetensors "$COMFY_DIR/models/$sub/"
  fi
done

echo
echo "[4/4] 校验文件大小 ..."
TOTAL_BYTES=0
for sub in diffusion_models text_encoders vae loras embeddings; do
  for f in "$COMFY_DIR/models/$sub"/*.safetensors; do
    [ -e "$f" ] || continue
    BYTES="$(stat -c%s "$f")"
    TOTAL_BYTES=$((TOTAL_BYTES + BYTES))
    # 用 GB（十进制）而不是 GiB，和官方文档里的数字口径一致
    printf "  %8.3f GB  %s\n" "$(awk -v b="$BYTES" 'BEGIN{printf "%.3f", b/1e9}')" "$(basename "$f")"
  done
done
echo "  ------------------------------------------------------------"
printf "  合计      %8.3f GB\n" "$(awk -v b="$TOTAL_BYTES" 'BEGIN{printf "%.3f", b/1e9}')"

echo
echo "清理中转目录 ..."
rm -rf "$STAGE_DIR"

echo
echo "完成。接着执行: bash start-comfyui.sh"
echo
echo "提示：embeddings 的用法是在提示词里写 embedding:minimaxh3_<名字>，"
echo "      例如 embedding:minimaxh3_bullet_time。可用名字："
echo "      art_is_explosion / blooming_flowers / bullet_time / dark_magic /"
echo "      fire_breath / four_seasons / kiss_camera / spiral_ascent /"
echo "      storm_magic / truman_show"
