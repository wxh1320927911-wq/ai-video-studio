#!/usr/bin/env bash
# 在 AutoDL 实例上运行：后台启动 ComfyUI，监听 6006 端口
#
# 用法：
#   COMFY_DIR=/root/autodl-tmp/ComfyUI bash start-comfyui.sh
#
# 为什么是 6006：AutoDL 为每个实例的 6006 / 6008 端口默认做了公网映射，
# 不需要企业认证。启动后在控制台点「自定义服务」复制地址，用本地浏览器打开。

set -euo pipefail

COMFY_DIR="${COMFY_DIR:-/root/autodl-tmp/ComfyUI}"
PORT="${PORT:-6006}"
LOG="${LOG:-/root/autodl-tmp/comfyui.log}"
PIDFILE="/root/autodl-tmp/comfyui.pid"

if [ ! -f "$COMFY_DIR/main.py" ]; then
  echo "[错误] $COMFY_DIR 下找不到 main.py，请用 COMFY_DIR=<路径> 重跑。"
  exit 1
fi

# 已经在跑就先停掉，避免端口冲突
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  echo "[信息] 检测到已在运行的 ComfyUI (PID $(cat "$PIDFILE"))，先停止 ..."
  kill "$(cat "$PIDFILE")" 2>/dev/null || true
  sleep 3
fi

cd "$COMFY_DIR"

echo "[启动] 目录: $COMFY_DIR"
echo "[启动] 端口: $PORT"
echo "[启动] 日志: $LOG"

nohup python main.py --listen 0.0.0.0 --port "$PORT" > "$LOG" 2>&1 &
echo $! > "$PIDFILE"

echo "[等待] 给 15 秒让服务起来 ..."
sleep 15

echo
if ss -tlnp 2>/dev/null | grep -q ":${PORT} "; then
  echo "[成功] 端口 $PORT 正在监听。"
else
  echo "[警告] 端口 $PORT 还没监听，看日志末尾："
  tail -n 30 "$LOG"
  exit 1
fi

echo
echo "接下来："
echo "  1. 回 AutoDL 控制台，实例快捷工具里点「自定义服务」，复制地址"
echo "  2. 在本地浏览器打开该地址，就是 ComfyUI 界面"
echo "  3. 加载工作流：顶部「工作流」→「浏览模板」→ 视频 → MiniMax H3 T2V"
echo
echo "常用命令："
echo "  看日志 : tail -f $LOG"
echo "  停止   : kill \$(cat $PIDFILE)"
