#!/usr/bin/env bash
# 在 AutoDL 规划机上运行：编译 llama.cpp（CUDA 版）+ 下载解禁模型权重（一次性）
#
# 用法：
#   bash setup-planner.sh
#
# 关于「要不要在无卡模式下跑」：
#   - 下载权重（约 17.7GB）不需要 GPU，无卡模式（¥0.1/时）很划算
#   - 编译 llama.cpp 需要知道目标显卡架构。无卡模式下拿不到型号，会退回 sm_86
#     （RTX 3090 用的架构）。如果你租的是 4090 / 5090，必须用 CUDA_ARCH 显式指定，
#     否则编出来的二进制在这张卡上跑不起来。
#   - 开机状态下编译只要约 10 分钟，按 ¥1.48/时算不到 3 毛钱，其实没必要省
#
# 环境变量：
#   LLAMA_DIR    llama.cpp 目录      默认 /root/llama.cpp
#   MODEL_DIR    权重目录            默认 /root/autodl-tmp/models/qwen38-27b-heretic
#   QUANT        量化档位            默认 Q4_K_M
#   MTP          1=取 MTP 内联的融合版（推荐）  0=取 noMTP 版   默认 1
#   CUDA_ARCH    目标架构，如 86/89/120               默认自动探测
#   SKIP_BUILD   1=跳过编译，只下载权重                默认 0

set -euo pipefail

# AutoDL 的非交互 SSH 会话不会加载 conda / CUDA 的 PATH，直接跑会报
# 「找不到 nvcc」和「python: command not found」。这两个目录其实都在，
# 只是没进 PATH。这里显式补上；已经在 PATH 里就不重复添加。
for _d in /usr/local/cuda/bin /root/miniconda3/bin; do
  if [ -d "$_d" ]; then
    case ":$PATH:" in
      *":$_d:"*) ;;
      *) PATH="$_d:$PATH" ;;
    esac
  fi
done
export PATH
unset _d

LLAMA_DIR="${LLAMA_DIR:-/root/llama.cpp}"
MODEL_DIR="${MODEL_DIR:-/root/autodl-tmp/models/qwen38-27b-heretic}"
QUANT="${QUANT:-Q4_K_M}"
MTP="${MTP:-1}"
SKIP_BUILD="${SKIP_BUILD:-0}"

# 主选：JonathanColetti 的纯 Heretic 消融版（零微调，格式能力与基座等价）。
# 选型论证见 docs/05-解禁模型与主机调整.md 第二节。
REPO="JonathanColetti/Qwen3.8-27B-Uncensored-GGUF"
MMPROJ="mmproj-Qwen3.8-27B-Uncensored-F16.gguf"
REPO_URL="https://github.com/ggml-org/llama.cpp"

echo "=========================================================="
echo " llama.cpp 目录 : $LLAMA_DIR"
echo " 权重目录       : $MODEL_DIR"
echo " 仓库           : $REPO"
echo " 量化           : $QUANT  (MTP=$MTP)"
echo "=========================================================="

# ---------------------------------------------------------------- 1. 装依赖
echo
echo "[1/5] 检查并安装编译依赖 ..."
if ! command -v nvcc >/dev/null 2>&1; then
  echo "[错误] 找不到 nvcc，说明这个镜像里没有 CUDA toolkit。"
  echo "       请换一个带 CUDA 的基础镜像（PyTorch 2.x + CUDA 12.x/13.x），重开实例。"
  exit 1
fi
echo "  nvcc : $(nvcc --version | grep -o 'release [0-9.]*' | head -1)"

MISSING=()
for c in cmake gcc g++ make git; do
  command -v "$c" >/dev/null 2>&1 || MISSING+=("$c")
done
if [ ${#MISSING[@]} -gt 0 ]; then
  echo "  缺少: ${MISSING[*]}，开始安装 ..."
  apt-get update -qq
  apt-get install -y -qq build-essential cmake git libcurl4-openssl-dev
else
  echo "  编译工具齐备"
  # libcurl 头文件不一定有，llama-server 下载模型要用
  dpkg -s libcurl4-openssl-dev >/dev/null 2>&1 || {
    echo "  补装 libcurl4-openssl-dev ..."
    apt-get update -qq && apt-get install -y -qq libcurl4-openssl-dev
  }
fi

# ---------------------------------------------------------------- 2. 拉源码
if [ "$SKIP_BUILD" != "1" ]; then
  echo
  echo "[2/5] 获取 llama.cpp 源码 ..."
  if [ -d "$LLAMA_DIR/.git" ]; then
    echo "  已存在，执行 git pull ..."
    git -C "$LLAMA_DIR" pull --ff-only || echo "  [警告] pull 失败，用现有版本继续"
  else
    # GitHub 在国内很慢，走学术加速
    if [ -f /etc/network_turbo ]; then
      # shellcheck disable=SC1091
      source /etc/network_turbo
      echo "  已开启学术加速"
    fi
    git clone --depth 1 "$REPO_URL" "$LLAMA_DIR"
  fi

  # ------------------------------------------------------------ 3. 编译
  echo
  echo "[3/5] 编译（CUDA）..."

  ARCH="${CUDA_ARCH:-}"
  if [ -z "$ARCH" ]; then
    if nvidia-smi -L >/dev/null 2>&1; then
      ARCH="$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 | tr -d '.')"
      echo "  探测到 GPU: $(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)  ->  sm_$ARCH"
    else
      ARCH="86"
      echo "  [警告] 没有检测到 GPU（无卡模式？），按 sm_$ARCH 编译。"
      echo "         如果你租的不是 RTX 3090，请中断并用 CUDA_ARCH 重跑："
      echo "           RTX 4090/4090D -> CUDA_ARCH=89"
      echo "           RTX 5090       -> CUDA_ARCH=120"
      echo "         继续编译中 ..."
    fi
  fi

  cmake -S "$LLAMA_DIR" -B "$LLAMA_DIR/build" \
    -DGGML_CUDA=ON \
    -DCMAKE_CUDA_ARCHITECTURES="$ARCH" \
    -DLLAMA_CURL=ON \
    -DCMAKE_BUILD_TYPE=Release

  cmake --build "$LLAMA_DIR/build" --config Release -j "$(nproc)"

  if [ ! -x "$LLAMA_DIR/build/bin/llama-server" ]; then
    echo "[错误] 编译结束但找不到 llama-server，请检查上面的编译输出。"
    exit 1
  fi
  echo "  [成功] $LLAMA_DIR/build/bin/llama-server"
else
  echo
  echo "[2/5] [3/5] 已按 SKIP_BUILD=1 跳过编译"
fi

# ---------------------------------------------------------------- 4. 下载权重
echo
echo "[4/5] 下载权重 ..."
if ! command -v hf >/dev/null 2>&1; then
  echo "  安装 huggingface_hub[cli] ..."
  pip install -U -q "huggingface_hub[cli]"
fi

# 国内直连 HF 很慢，走镜像站
#
# 这里**故意不开**学术加速（/etc/network_turbo），实测数据：
#   走 hf-mirror.com 直连  —— 16 MB/s，17GB 约 17 分钟
#   开学术加速走 huggingface.co —— 不稳定，且 /etc/network_turbo 的
#     no_proxy 里没有 hf-mirror.com，开了反而会把镜像站的流量也塞进代理
# 学术加速只在上面 git clone 那一步用（GitHub 直连确实需要）。
export HF_ENDPOINT="${HF_ENDPOINT:-https://hf-mirror.com}"
echo "  HF_ENDPOINT=$HF_ENDPOINT"

# 关掉 Xet 存储后端。新版 huggingface_hub 默认走 Xet，它会绕开 HF_ENDPOINT
# 直连 us.aws.cdn.hf.co，在国内必然超时，报错长这样：
#   RuntimeError: File reconstruction error: CAS Client Error:
#   error sending request for url (https://us.aws.cdn.hf.co/xorbs/...)
# 关掉之后退化成普通 HTTP 下载，才能正常走镜像站。
export HF_HUB_DISABLE_XET="${HF_HUB_DISABLE_XET:-1}"
echo "  HF_HUB_DISABLE_XET=$HF_HUB_DISABLE_XET"

mkdir -p "$MODEL_DIR"

# 文件名精确匹配，不用通配符。
# 这个仓库同时有 Q4_K_M / noMTP-Q4_K_M / draft-Q4_0 / draft-Q8_0 等十几个文件，
# 写 "*Q4_K_M*" 会把 noMTP 变体也拖下来（白多下 16.5GB）。
#   MTP=1 -> 融合版，MTP 头内联在同一个文件里（推荐，部署最简单）
#   MTP=0 -> noMTP 版，想用 --model-draft 显式加载草稿头时才需要
if [ "$MTP" = "1" ]; then
  MODEL_FILE="Qwen3.8-27B-Uncensored-${QUANT}.gguf"
else
  MODEL_FILE="Qwen3.8-27B-Uncensored-noMTP-${QUANT}.gguf"
fi
echo "  模型文件    : $MODEL_FILE"
echo "  视觉模块    : $MMPROJ"

# 支持断点续传，中断后重跑同一条命令即可
hf download "$REPO" \
  --include "$MODEL_FILE" \
  --include "$MMPROJ" \
  --local-dir "$MODEL_DIR"

# ---------------------------------------------------------------- 5. 校验
echo
echo "[5/5] 校验下载结果 ..."
shopt -s nullglob
GGUF=("$MODEL_DIR"/*.gguf)
shopt -u nullglob

if [ ${#GGUF[@]} -eq 0 ]; then
  echo "[错误] $MODEL_DIR 下没有任何 .gguf 文件。"
  echo "       可能是文件名不对。到仓库文件页确认实际文件名后，用 QUANT= 重跑。"
  echo "       仓库: https://huggingface.co/$REPO/tree/main"
  exit 1
fi

TOTAL=0
for f in "${GGUF[@]}"; do
  SIZE=$(stat -c%s "$f")
  TOTAL=$((TOTAL + SIZE))
  printf "  %6.2f GB  %s\n" "$(awk -v b="$SIZE" 'BEGIN{printf "%.2f", b/1073741824}')" "$(basename "$f")"
done
printf "  ------ 合计 %.2f GB\n" "$(awk -v b="$TOTAL" 'BEGIN{printf "%.2f", b/1073741824}')"

if [ ! -f "$MODEL_DIR/$MMPROJ" ]; then
  echo "  [警告] 没下到 $MMPROJ，视觉能力不可用（不影响纯文字写提示词）"
fi

echo
echo "=========================================================="
echo " 完成。接着执行: bash start-planner.sh"
echo
echo " 提醒：这次下载是权重唯一副本，实例释放就没了。"
echo "       数据盘不要缩容；下次换实例要重新下载。"
echo "=========================================================="
