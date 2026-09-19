#!/usr/bin/env bash
# 在 AutoDL 规划机上运行：启动 llama-server，提供 OpenAI 兼容接口
#
# 用法：
#   bash start-planner.sh
#
# 为什么监听 0.0.0.0:6006：
#   llama-server 自带一个完整的网页聊天界面（在 `/`，SvelteKit 打包的静态站点），
#   但默认只在 127.0.0.1 上监听，外面访问不到。而 AutoDL **只把 6006 / 6008
#   两个端口做公网映射**，所以绑 11434 等于没有网页入口。
#   改绑 0.0.0.0:6006 之后：网页界面和 OpenAI 兼容接口在同一个端口上都有了，
#   回 AutoDL 控制台点「自定义服务」即可用浏览器打开。
#   （原先是 127.0.0.1:11434，为了对齐 04 文档里 Ollama 的端口、做到"客户端零改动"。
#    现在端口变了，batch-prompts.py / ab-test.py / probe-model.py 的默认地址已同步改为 6006。）
#
# 为什么不用 Ollama：这个模型是线性注意力 + 全注意力的混合架构，还带 MTP，
# Ollama 对这类新架构的支持通常滞后于 llama.cpp。
#
# ⚠ 安全：模型是解禁版，绑到 0.0.0.0 就等于放到公网。强烈建议设 API_KEY。
#   内置网页界面支持填 key（设置里那栏 "Set the API Key if you are using --api-key"）。
#
# 环境变量：
#   LLAMA_DIR    llama.cpp 目录   默认 /root/llama.cpp
#   MODEL_DIR    权重目录         默认 /root/autodl-tmp/models/qwen38-27b-heretic
#   MODEL        主权重文件路径   默认自动挑选（排除 mmproj / draft / noMTP）
#   HOST         监听地址         默认 0.0.0.0（要只给本机用就设 127.0.0.1）
#   PORT         监听端口         默认 6006（AutoDL 只映射 6006/6008，别乱改）
#   API_KEY      访问口令         默认空（**公网暴露时请务必设置**）
#   CTX          上下文长度       默认 16384
#   MMPROJ       1=启用视觉       默认 1（实测能正确读图，见 docs/05 第 9.10 节）
#   MTP          1=开投机解码     默认 1（实测提速 1.44 倍且质量不变；
#                                 老版本 llama.cpp 不认参数时会自动回退，见文件末尾）
#   NOTHINK      1=关掉思维链     默认 0（Qwen3.8 基座默认 xhigh，写提示词纯烧时间）
#   FA           闪存注意力 on/off/auto，默认不传（用 llama.cpp 自己的默认值）
#   ALIAS        接口里显示的模型名  默认 qwen38-27b-heretic

set -euo pipefail

# AutoDL 的非交互 SSH 会话不会加载 conda 的 PATH，下面的自检用的是 python。
# 目录存在才补，已经在 PATH 里就不重复添加。
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
HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-6006}"
API_KEY="${API_KEY:-}"
CTX="${CTX:-16384}"
MMPROJ="${MMPROJ:-1}"
MTP="${MTP:-1}"
NOTHINK="${NOTHINK:-0}"
FA="${FA:-}"
ALIAS="${ALIAS:-qwen38-27b-heretic}"

LOG="${LOG:-/root/autodl-tmp/llama-server.log}"
PIDFILE="/root/autodl-tmp/llama-server.pid"
SERVER="$LLAMA_DIR/build/bin/llama-server"

# 设了口令之后，所有请求（含 /health 探活和自检）都要带 Authorization 头。
# 这里就定义好，别放到文件后半段——try_start 会用到它。
AUTH=()
[ -n "$API_KEY" ] && AUTH=(-H "Authorization: Bearer $API_KEY")

# ---------------------------------------------------------------- 前置检查
[ -x "$SERVER" ] || {
  echo "[错误] 找不到 $SERVER"
  echo "       先跑: bash setup-planner.sh"
  exit 1
}

# 自动挑主权重文件。要排除两类干扰文件：
#   - mmproj*.gguf  视觉投影器，不是主模型
#   - *draft*.gguf  单独的 MTP 草稿头，不能独立回答提示
#   - *noMTP*.gguf  同一量化的无 MTP 版，和融合版只差 MTP 头
# 想指定就用 MODEL=/path/to/x.gguf bash start-planner.sh
MODEL="${MODEL:-}"
if [ -z "$MODEL" ]; then
  shopt -s nullglob
  for f in "$MODEL_DIR"/*.gguf; do
    BASE="$(basename "$f")"
    case "$BASE" in
      mmproj*) continue ;;
      *draft*) continue ;;
      *noMTP*) continue ;;
    esac
    MODEL="$f"
    break
  done
  shopt -u nullglob
fi

[ -n "$MODEL" ] || {
  echo "[错误] $MODEL_DIR 下找不到主模型 .gguf 文件"
  echo "       先跑: bash setup-planner.sh"
  exit 1
}

MMPROJ_FILE=""
if [ "$MMPROJ" = "1" ]; then
  # 用通配符找 mmproj，不要写死文件名——不同仓库的 mmproj 命名不一样
  shopt -s nullglob
  for f in "$MODEL_DIR"/mmproj*.gguf; do
    MMPROJ_FILE="$f"
    break
  done
  shopt -u nullglob
  [ -n "$MMPROJ_FILE" ] || echo "[警告] $MODEL_DIR 下找不到 mmproj*.gguf，这次不带视觉能力启动"
fi

# ---------------------------------------------------------------- 停旧进程
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  echo "[信息] 检测到已在运行的 llama-server (PID $(cat "$PIDFILE"))，先停止 ..."
  kill "$(cat "$PIDFILE")" 2>/dev/null || true
  sleep 3
fi

# ---------------------------------------------------------------- 组装参数
# 抽成函数是为了让 MTP 启动失败时能去掉 --spec-type 重试一次。
build_args() {
  local mtp="$1"
  ARGS=(
    -m "$MODEL"
    --host "$HOST" --port "$PORT"
    -ngl 99
    -c "$CTX"
    --alias "$ALIAS"
    --jinja
    --temp 0.7
    --top-p 0.95
    --min-p 0.05
    --repeat-penalty 1.0
  )
  # 口令。绑公网时应当设置，否则任何人拿到 AutoDL 那个自定义服务地址
  # 都能白用这台 3090（烧的是你的余额）。
  if [ -n "$API_KEY" ]; then
    ARGS+=(--api-key "$API_KEY")
  fi
  if [ -n "$MMPROJ_FILE" ]; then
    ARGS+=(--mmproj "$MMPROJ_FILE")
  fi
  if [ -n "$FA" ]; then
    ARGS+=(-fa "$FA")
  fi

  # 投机解码（MTP）。2026-09-20 在 RTX 3090 / Q4_K_M 上实测（见 docs/05 第 9.9 节）：
  #   关闭 39.6 tok/s  →  开启 59.4 tok/s
  #   整批 10 条墙钟 100.3 秒 → 69.7 秒（1.44 倍）
  #   拒答率 0/10、一次通过率 10/10 完全不变
  #   draft 接受率稳定在 62%–73%，作者担心的「消融后接受率下降」没有发生
  # 需要较新的 llama.cpp（b10440+ / PR #22673）。老版本不认 --spec-type 会直接
  # 启动失败，下面有自动回退，所以默认开着。
  if [ "$mtp" = "1" ]; then
    ARGS+=(--spec-type draft-mtp --spec-draft-n-max 2)
  fi

  # 关思维链。Qwen3.8 基座的对话模板默认 reasoning_effort=xhigh，
  # 写提示词用不上，只是白烧 token。模板本身支持 enable_thinking=false
  # （传 false 时渲染出的是空 <think></think> 块），用 --chat-template-kwargs
  # 透传即可，不用改模板文件。细节见 docs/05 第 9.2 节。
  # 注意：--chat-template-kwargs 需要较新的 llama.cpp，老版本不认这个参数。
  if [ "$NOTHINK" = "1" ]; then
    ARGS+=(--chat-template-kwargs '{"enable_thinking":false}')
  fi
}

# 启动并等就绪。成功返回 0，失败返回 1。
try_start() {
  local mtp="$1"
  build_args "$mtp"

  echo "=========================================================="
  echo " 模型    : $(basename "$MODEL")"
  echo " 视觉    : ${MMPROJ_FILE:-未启用}"
  echo " 监听    : $HOST:$PORT"
  echo " 口令    : $([ -n "$API_KEY" ] && echo "已设置" || echo "**未设置**")"
  echo " 上下文  : $CTX"
  echo " MTP     : $([ "$mtp" = "1" ] && echo "开" || echo "关")"
  echo " 思维链  : $([ "$NOTHINK" = "1" ] && echo "关" || echo "开（基座默认 xhigh）")"
  echo " 日志    : $LOG"
  echo "=========================================================="

  nohup "$SERVER" "${ARGS[@]}" > "$LOG" 2>&1 &
  echo $! > "$PIDFILE"

  echo
  echo "[等待] 加载权重 ..."
  local i
  for i in $(seq 1 30); do
    sleep 5
    if curl -sf "${AUTH[@]}" "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
      echo
      echo "[成功] 服务就绪，用时约 $((i * 5)) 秒"
      return 0
    fi
    # 进程已经死了就不用等了
    kill -0 "$(cat "$PIDFILE")" 2>/dev/null || break
    printf "  ... 已等 %d 秒\n" $((i * 5))
  done
  return 1
}

# ---------------------------------------------------------------- 启动
if try_start "$MTP"; then
  :
elif [ "$MTP" = "1" ]; then
  echo
  echo "[警告] 带 MTP 启动失败。多半是这个 llama.cpp 版本不认 --spec-type。"
  echo "       去掉投机解码，重试一次 ..."
  echo
  if ! try_start "0"; then
    echo
    echo "[失败] 去掉 MTP 也起不来。日志末尾："
    tail -n 40 "$LOG"
    exit 1
  fi
  echo
  echo "[提示] 本次已用无 MTP 模式跑起来（慢约 1.4 倍）。想用上 MTP 就升级 llama.cpp："
  echo "         cd /root/llama.cpp && git pull"
  echo "         cmake --build build --config Release -j \$(nproc)"
else
  echo
  echo "[失败] 服务没起来。日志末尾："
  tail -n 40 "$LOG"
  exit 1
fi

# ---------------------------------------------------------------- 自检
echo
echo "---- 自检 ----"
curl -sf "${AUTH[@]}" "http://127.0.0.1:$PORT/v1/models" \
  | python -c "import sys,json; d=json.load(sys.stdin); print('  接口模型名:', [m['id'] for m in d.get('data',[])])" \
  2>/dev/null || echo "  [警告] /v1/models 返回异常（设了口令的话确认一下口令是否一致）"

echo "  发一条测试请求 ..."
# max_tokens 给 512 而不是 16：开着思维链时，思考会先吃掉预算，
# 给太小会导致 content 为空，看起来像"服务坏了"，其实只是被思考吃光了。
curl -sf "${AUTH[@]}" "http://127.0.0.1:$PORT/v1/chat/completions" \
  -H 'Content-Type: application/json' \
  -d "{\"model\":\"$ALIAS\",\"messages\":[{\"role\":\"user\",\"content\":\"只回答两个字：就绪\"}],\"max_tokens\":512}" \
  | python -c "import sys,json; d=json.load(sys.stdin); c=d['choices'][0]['message'].get('content','').strip(); print('  模型回答:', c if c else '(空——多半是思维链吃光了 max_tokens，加 NOTHINK=1 重试)')" \
  2>/dev/null || echo "  [警告] 测试请求失败，看日志: tail -f $LOG"

echo
echo "=========================================================="
echo " 网页入口（人用的界面）——llama-server 自带，不用装任何东西："
echo "   回 AutoDL 控制台 → 实例卡片 → 点「自定义服务」→ 浏览器里就是聊天界面"
echo "   （端口 $PORT 是 AutoDL 固定映射的那两个之一，所以这一步是必须的）"
if [ -z "$API_KEY" ]; then
  echo
  echo "   ⚠ 现在没有设访问口令，而这个地址在公网可达。"
  echo "     模型是解禁版，且别人用了烧的是你的余额。建议这样起："
  echo "       API_KEY=你的口令 bash start-planner.sh"
  echo "     （网页界面在设置里填同一个口令即可；脚本走 HTTP 头 Authorization: Bearer 你的口令）"
fi
echo
echo " 批量跑提示词（命令行）："
echo "    python batch-prompts.py --briefs briefs --out prompts --model $ALIAS"
echo "  （脚本默认就打 http://127.0.0.1:$PORT，不用改）"
echo
echo " 常用命令："
echo "   看日志 : tail -f $LOG"
echo "   停止   : kill \$(cat $PIDFILE)"
echo "   探活   : curl -s http://127.0.0.1:$PORT/health"
echo "=========================================================="
echo
if [ "$NOTHINK" != "1" ]; then
  echo "⚠ 思维链：Qwen3.8 基座默认走 xhigh 推理模式，写提示词纯属浪费时间和电费。"
  echo "   关掉（不用改模板文件）："
  echo "       NOTHINK=1 bash start-planner.sh"
  echo "   也可以只缩短不关：请求体里传 chat_template_kwargs 的 reasoning_effort=low。"
  echo "   细节见 docs/05-解禁模型与主机调整.md 第六节。建议先用默认值跑通，再动它。"
  echo
fi
if [ "$MTP" != "1" ]; then
  echo "ℹ MTP 投机解码当前是关的（用 MTP=0 显式关掉的）。"
  echo "   实测开着快 1.44 倍且质量不变，去掉 MTP=0 即可恢复默认开启。"
  echo "   数据见 docs/05-解禁模型与主机调整.md 第 9.9 节。"
  echo
fi
