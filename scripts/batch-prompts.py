#!/usr/bin/env python3
"""在规划机（AutoDL 实例）上批量生成 H3 提示词。

用法：
    python batch-prompts.py --briefs briefs --out prompts --model qwen38-27b-heretic

说明：
    - briefs/ 下每条创意一个 .txt 文件，文件名会成为输出文件名
    - 输出写到 prompts/<同名>.md
    - 默认跳过已存在的输出，方便中断后续跑；加 --force 覆盖重跑
    - 默认关闭思维链（见下方「为什么默认关思维链」）
    - 依赖：pip install requests

为什么默认关思维链：
    Qwen3.8 基座的对话模板默认 reasoning_effort=xhigh。实测（S07-雨夜巷斗，
    RTX 3090 / Q4_K_M）开着要 196 秒、7900 tokens，其中思考 22108 字符而正文
    只有 1337 字符；关掉只要 11.4 秒、407 tokens，正文反而更长。思考吃掉了
    95% 的预算，写提示词这件事用不上。想开回来加 --think。

    实测数据见 docs/05-解禁模型与主机调整.md 第 9.2 节。
"""

import argparse
import pathlib
import re
import sys
import time

DEFAULT_ENDPOINT = "http://127.0.0.1:6006/v1/chat/completions"


def strip_thinking(text: str) -> str:
    """去掉思维链，只保留最终产出。

    不同后端的标记不一样，都处理一遍。不清的话开着思维链时会把几万字的
    推理过程一起写进产出文件。
    """
    text = re.sub(r"<think(?:ing)?>.*?</think(?:ing)?>", "", text, flags=re.S | re.I)
    text = re.sub(r"\[THINK\].*?\[/THINK\]", "", text, flags=re.S | re.I)
    return text.strip()


def load_system_prompt(path: pathlib.Path) -> str:
    if not path.exists():
        sys.exit(f"[错误] 找不到系统指令文件: {path}\n"
                 f"       从项目里把 prompts/system-prompt.txt 传上来。")
    text = path.read_text(encoding="utf-8").strip()
    if not text:
        sys.exit(f"[错误] 系统指令文件是空的: {path}")
    return text


def call_model(endpoint: str, model: str, system: str, brief: str,
               temperature: float, timeout: int, max_tokens: int,
               think: bool) -> str:
    try:
        import requests
    except ImportError:
        sys.exit("[错误] 缺少 requests 依赖，请先执行: pip install requests")

    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": brief},
        ],
        "temperature": temperature,
        "max_tokens": max_tokens,
    }
    # 关思维链：基座模板里 enable_thinking 是可覆盖的，传 false 会渲染出
    # 空的 <think></think>，不用改模板文件。
    if not think:
        payload["chat_template_kwargs"] = {"enable_thinking": False}

    resp = requests.post(endpoint, json=payload, timeout=timeout)
    resp.raise_for_status()
    msg = resp.json()["choices"][0]["message"]
    content = msg.get("content") or ""
    reasoning = msg.get("reasoning_content") or ""
    return strip_thinking(content + ("\n" + reasoning if reasoning else ""))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--briefs", default="briefs", help="创意清单目录")
    ap.add_argument("--out", default="prompts", help="输出目录")
    ap.add_argument("--system", default="system-prompt.txt", help="系统指令文件")
    ap.add_argument("--model", default="qwen38-27b-heretic")
    ap.add_argument("--endpoint", default=DEFAULT_ENDPOINT)
    ap.add_argument("--temperature", type=float, default=0.7)
    ap.add_argument("--timeout", type=int, default=900, help="单条超时（秒）")
    ap.add_argument("--max-tokens", type=int, default=8192,
                    help="默认 8192。别调太小——开着思维链时思考会先吃掉预算，"
                         "给不够会导致正文还没写就截断")
    ap.add_argument("--think", action="store_true",
                    help="打开思维链。默认关闭（实测快 17 倍且正文更长）")
    ap.add_argument("--force", action="store_true", help="已存在的输出也重跑")
    args = ap.parse_args()

    briefs_dir = pathlib.Path(args.briefs)
    out_dir = pathlib.Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    system = load_system_prompt(pathlib.Path(args.system))
    files = sorted(briefs_dir.glob("*.txt"))
    if not files:
        sys.exit(f"[错误] {briefs_dir} 下没有 .txt 文件")

    print(f"模型     : {args.model}")
    print(f"接口     : {args.endpoint}")
    print(f"待处理   : {len(files)} 条")
    print(f"思维链   : {'开（很慢，非必要不用）' if args.think else '关'}")
    print("-" * 52)

    done = failed = skipped = 0
    for i, f in enumerate(files, 1):
        target = out_dir / f"{f.stem}.md"
        if target.exists() and not args.force:
            print(f"[{i}/{len(files)}] 跳过（已存在） {target.name}")
            skipped += 1
            continue

        brief = f.read_text(encoding="utf-8").strip()
        t0 = time.time()
        try:
            result = call_model(args.endpoint, args.model, system, brief,
                                args.temperature, args.timeout, args.max_tokens,
                                args.think)
        except Exception as e:
            print(f"[{i}/{len(files)}] 失败 {f.name}: {e}")
            failed += 1
            continue

        if not result:
            print(f"[{i}/{len(files)}] 警告 {f.name}: 返回内容为空，未写入")
            failed += 1
            continue

        target.write_text(result + "\n", encoding="utf-8")
        dt = time.time() - t0
        print(f"[{i}/{len(files)}] 完成 {target.name}  "
              f"({len(result)} 字符, {dt:.0f} 秒)")
        done += 1

    print("-" * 52)
    print(f"完成 {done} 条，跳过 {skipped} 条，失败 {failed} 条")
    print(f"输出目录: {out_dir.resolve()}")
    print("接着把整个输出目录下载回本地，然后立刻关机。")


if __name__ == "__main__":
    main()
