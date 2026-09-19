#!/usr/bin/env bash
# 在 AutoDL 实例上运行：检查跑 H3 所需的环境是否达标
# 用法：bash check-env.sh

set -u

echo "==================== MiniMax H3 环境体检 ===================="

echo
echo "---- 1. GPU ----"
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi --query-gpu=name,memory.total,memory.used,driver_version --format=csv
else
  echo "[警告] 找不到 nvidia-smi，可能处于无卡模式"
fi

echo
echo "---- 2. 内存（必须 >= 32GB） ----"
free -g | awk 'NR==1{print} NR==2{printf "总内存: %s GB   可用: %s GB\n", $2, $7}'
MEM_TOTAL=$(free -g | awk 'NR==2{print $2}')
if [ "${MEM_TOTAL:-0}" -lt 30 ]; then
  echo "[不合格] 内存只有 ${MEM_TOTAL}GB，H3 量化版需要 >= 32GB，否则会退化成反复读磁盘，慢 3-4 倍。请更换主机。"
else
  echo "[合格] 内存充足"
fi

echo
echo "---- 3. 磁盘 ----"
df -h / /root/autodl-tmp 2>/dev/null | awk 'NR==1{print} {print}'
echo "模型文件合计约 44GB，数据盘请预留 >= 50GB 可用空间。"

echo
echo "---- 4. Python / PyTorch / CUDA ----"
python -c "
import torch, sys
print('python :', sys.version.split()[0])
print('torch  :', torch.__version__)
print('cuda   :', torch.version.cuda)
print('gpu可用:', torch.cuda.is_available())
if torch.version.cuda and torch.version.cuda.startswith('12.8'):
    print('[注意] 检测到 cu128。社区报告称该版本下 int8 推理内核可能静默失效，速度慢约 3 倍。先跑通，再对照排查。')
" 2>&1 | sed 's/^/  /'

echo
echo "---- 5. ComfyUI 位置与版本 ----"
for d in /root/autodl-tmp/ComfyUI /root/ComfyUI /root/comfyui; do
  if [ -f "$d/main.py" ]; then
    echo "找到 ComfyUI: $d"
    if [ -f "$d/comfyui_version.py" ]; then
      grep -o '"[0-9.]*"' "$d/comfyui_version.py" | head -1 | sed 's/^/  版本: /'
    fi
    if [ -d "$d/.git" ]; then
      echo "  git: $(git -C "$d" log -1 --format='%h %cd' --date=short 2>/dev/null)"
    fi
  fi
done
echo "ComfyUI 版本必须 >= 0.30.0，否则没有 MiniMax H3 原生节点。"

echo
echo "---- 6. HuggingFace CLI ----"
if command -v hf >/dev/null 2>&1; then
  echo "hf 已安装: $(hf version 2>/dev/null || echo ok)"
else
  echo "[待办] 未安装，请执行: pip install -U \"huggingface_hub[cli]\""
fi

echo
echo "==================== 体检结束 ===================="
echo "网络慢的话先执行: source /etc/network_turbo"
