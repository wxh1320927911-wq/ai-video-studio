#!/usr/bin/env python3
"""探针：测一条真实请求的耗时、token 用量、思维链占比。

用途：换模型或换量化档位时，先跑一条看开销，别直接上批量。
      （2026-09-20 首次实测结论：思维链吃掉 95% 的 token，跑批应关掉。
        数据见 docs/05-解禁模型与主机调整.md 第 9.2 节。）

用法：
    python probe-model.py abtest-briefs/S07-雨夜巷斗.txt
    python probe-model.py abtest-briefs/S07-雨夜巷斗.txt --max-tokens=16384
    THINK=0 python probe-model.py abtest-briefs/S02-雨夜便利店.txt   # 关思维链对比
"""
import argparse
import os
import pathlib
import time

import requests

ENDPOINT = os.environ.get("ENDPOINT", "http://127.0.0.1:6006/v1/chat/completions")
MODEL = os.environ.get("MODEL", "qwen38-27b-heretic")


def main() -> None:
    ap = argparse.ArgumentParser(description="测单条请求的耗时 / token / 思维链占比")
    ap.add_argument("brief", nargs="?", default="abtest-briefs/S07-雨夜巷斗.txt",
                    help="创意 txt 路径")
    ap.add_argument("--max-tokens", type=int, default=8192)
    ap.add_argument("--system", default="system-prompt.txt")
    args = ap.parse_args()

    max_tokens = args.max_tokens
    brief_path = pathlib.Path(args.brief)
    system = pathlib.Path(args.system).read_text(encoding="utf-8").strip()
    brief = brief_path.read_text(encoding="utf-8").strip()

    payload = {
        "model": MODEL,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": brief},
        ],
        "temperature": 0.7,
        "max_tokens": max_tokens,
    }
    if os.environ.get("THINK") == "0":
        payload["chat_template_kwargs"] = {"enable_thinking": False}

    print(f"创意     : {brief_path.name}")
    print(f"max_tokens: {max_tokens}")
    print(f"思维链   : {'关 (enable_thinking=false)' if os.environ.get('THINK') == '0' else '开 (基座默认 xhigh)'}")
    print("-" * 60)

    t0 = time.time()
    r = requests.post(ENDPOINT, json=payload, timeout=1800)
    elapsed = time.time() - t0
    r.raise_for_status()
    d = r.json()

    usage = d.get("usage") or {}
    choice = d["choices"][0]
    content = choice["message"].get("content") or ""
    reasoning = choice["message"].get("reasoning_content") or ""

    ct = usage.get("completion_tokens", 0)
    print(f"耗时        : {elapsed:.1f} 秒")
    print(f"用量        : {usage}")
    print(f"finish      : {choice.get('finish_reason')}")
    print(f"content 长度: {len(content)} 字符")
    print(f"reasoning 长度: {len(reasoning)} 字符")
    if elapsed > 0 and ct:
        print(f"生成速度    : {ct / elapsed:.1f} tok/s")
    print("-" * 60)
    print("正文前 800 字符：")
    print(content[:800])


if __name__ == "__main__":
    main()
