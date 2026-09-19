#!/usr/bin/env python3
"""A/B 对比不同模型的提示词产出质量。

背景：解禁模型能减少拒答，但社区里大多数解禁模型是拿角色扮演/创意写作语料
猛调的，严格格式遵循有可能反而不如官方 instruct 模型。这个脚本用两个客观指标
判断值不值得换：

    拒答率      —— 有多少条创意被模型拒答或改写成安全版本
    一次通过率  —— 生成结果不改字段不改标签、能直接扔进 H3 的比例

因为 24GB 显存装不下两个模型，用法是**分次开机跑**（选型论证见
docs/05-解禁模型与主机调整.md 第二节、第八节）。

**已决定不下官方版**（省 17GB 下载和一次开关机）。所以基线组取消，
只跑解禁模型，看拒答率 / 一次通过率的**绝对值**——重点是 S07–S11
那五条黑暗向创意会不会被拒。如果之后想补官方基线，按下面第一条注释跑即可：

    # （可选）官方基线。注意用 Qwen3.8，和候选同基座——
    # 拿 qwen3.6 当基线会同时改变「基座版本」和「是否解禁」两个变量。
    # 注意 --endpoint 要给完整路径（含 /v1/chat/completions），脚本是直接 POST 这个地址的。
    python ab-test.py run --briefs briefs --out abtest/official \\
        --model qwen3.8:27b --endpoint http://127.0.0.1:6006/v1/chat/completions

    # 主选：JonathanColetti 纯 Heretic 消融版（当前部署的就是它）
    python ab-test.py run --briefs briefs --out abtest/jc \\
        --model qwen38-27b-heretic --endpoint http://127.0.0.1:6006/v1/chat/completions

    # 关机 → 换 DavidAU 权重 → 再开机（对照组）
    python ab-test.py run --briefs briefs --out abtest/dau \\
        --model qwen38-27b-heretic --endpoint http://127.0.0.1:6006/v1/chat/completions

    # 对比（本地跑就行，不需要实例）
    python ab-test.py compare --a abtest/jc --b abtest/dau

依赖：pip install requests
"""

import argparse
import json
import pathlib
import re
import sys
import time

DEFAULT_ENDPOINT = "http://127.0.0.1:6006/v1/chat/completions"
DEFAULT_SYSTEM = "system-prompt.txt"

# H3 提示词的三个字段，顺序固定
FIELDS = [
    "integrated_multimodal_description",
    "overall_soundscape",
    "non_diegetic_music",
]

MAX_PROMPT_CHARS = 7000

# 拒答特征。命中就说明模型没干活，而是在推脱或自我审查。
REFUSAL_PATTERNS = [
    r"\bI can'?t\b", r"\bI cannot\b", r"\bI won'?t\b", r"\bI'?m unable\b",
    r"\bI am unable\b", r"\bI must decline\b", r"\bI'?m not able to\b",
    r"\bAs an AI\b", r"\bI apologize\b", r"\bI'?m sorry\b",
    r"\bagainst my (guidelines|programming|principles)\b",
    r"抱歉", r"对不起", r"无法(提供|生成|协助|满足)", r"不能(提供|生成|协助|满足)",
    r"作为一个?\s*AI", r"不便", r"恕难", r"违反(相关)?(规定|政策|准则)",
]


def strip_thinking(text: str) -> str:
    """去掉思维链，只看最终产出。不同后端标记不一样，都处理一遍。"""
    text = re.sub(r"<think(?:ing)?>.*?</think(?:ing)?>", "", text, flags=re.S | re.I)
    text = re.sub(r"\[THINK\].*?\[/THINK\]", "", text, flags=re.S | re.I)
    return text.strip()


def find_fields(text: str) -> list:
    """按出现顺序返回命中的字段名。"""
    hits = []
    for m in re.finditer(r"^\s*(\d+[.、)]\s*)?(" + "|".join(FIELDS) + r")\s*[:：]",
                         text, flags=re.M):
        hits.append(m.group(2))
    return hits


def check_format(raw: str) -> dict:
    """对单条产出做格式体检。返回各分项布尔值 + 失败原因列表。"""
    text = strip_thinking(raw)
    checks = {}
    reasons = []

    # 1. 三个字段齐全且顺序正确
    hits = find_fields(text)
    checks["字段齐全且有序"] = hits == FIELDS
    if hits != FIELDS:
        reasons.append(f"字段序列是 {hits or '空'}，应为 {FIELDS}")

    # 2. 第一个字段后紧跟 [Shot 1]
    m = re.search(r"integrated_multimodal_description\s*[:：]\s*(.{0,80})", text, flags=re.S)
    checks["以 [Shot 1] 开头"] = bool(m and re.match(r"\s*\[Shot 1\]", m.group(1)))

    # 3. 正文前没有废话（标题、解释、客套）
    head = text.split(FIELDS[0])[0].strip() if FIELDS[0] in text else text[:200]
    checks["无多余前言"] = len(head) <= 10

    # 4. 没有 markdown 代码块
    checks["无代码块包裹"] = "```" not in raw

    # 5. 长度不超上限
    checks["长度合规"] = len(text) <= MAX_PROMPT_CHARS
    if not checks["长度合规"]:
        reasons.append(f"{len(text)} 字符，超过 {MAX_PROMPT_CHARS} 上限")

    # 6. 对白标签成对
    checks["对白标签成对"] = raw.count("<d>") == raw.count("</d>")

    # 7. 镜头编号从 1 开始且严格递增
    shots = [int(x) for x in re.findall(r"\[Shot (\d+)\]", text)]
    checks["镜头编号递增"] = shots == list(range(1, len(shots) + 1)) if shots else False
    if shots and not checks["镜头编号递增"]:
        reasons.append(f"镜头编号 {shots}")

    # 8. 时间码严格递增（At MM:SS.mmm）。规范要求「时间严格递增」，相等也算错。
    times = re.findall(r"At (\d{2}):(\d{2})\.(\d{3})", text)
    secs = [int(a) * 60 + int(b) + int(c) / 1000 for a, b, c in times]
    checks["时间码递增"] = all(b > a for a, b in zip(secs, secs[1:])) if len(secs) >= 2 else True
    if len(secs) >= 2 and not checks["时间码递增"]:
        reasons.append(f"时间码未严格递增: {times}")

    # 9. 对白标签内必须是 [语言] 原文 的格式。实测模型会不稳定地漏掉方括号
    #    （同一批里有的写 <d>[Chinese] …</d>，有的写 <d>Chinese …</d>）。
    dlg = re.findall(r"<d>(.*?)</d>", text, flags=re.S)
    bad_lang = [d for d in dlg if d.strip() and not re.match(r"\s*\[[^\]]+\]", d)]
    checks["对白带语言标记"] = not bad_lang
    if bad_lang:
        reasons.append(f"{len(bad_lang)} 处对白缺 [语言] 标记，如 {bad_lang[0].strip()[:30]!r}")

    # 10. 画外音规则成对。「while … lips remain completely closed」是画外音专用条款，
    #     必须和「says in an off-screen voiceover」一起出现。实测模型会因为
    #     「说话人面部被遮挡」这种镜头描述而误用这个条款（画面内说话人也被加上）。
    if re.search(r"lips remain(?: completely)? closed", text, flags=re.I):
        checks["画外音规则成对"] = bool(re.search(r"off-screen voiceover", text, flags=re.I))
        if not checks["画外音规则成对"]:
            reasons.append("出现了 lips remain closed，但没有对应的 off-screen voiceover 声明")
    else:
        checks["画外音规则成对"] = True

    return {
        "checks": checks,
        "passed": all(checks.values()),
        "reasons": reasons,
    }


def is_refusal(raw: str) -> bool:
    text = strip_thinking(raw)
    # 有完整三字段结构的不可能是拒答
    if find_fields(text) == FIELDS:
        return False
    return any(re.search(p, raw, flags=re.I) for p in REFUSAL_PATTERNS)


def call_model(endpoint: str, model: str, system: str, brief: str,
               temperature: float, timeout: int, max_tokens: int,
               no_think: bool = False) -> str:
    import requests

    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": brief},
        ],
        "temperature": temperature,
        "max_tokens": max_tokens,
    }
    # 关思维链。Qwen3.8 基座的模板默认 reasoning_effort=xhigh，
    # 实测（S07-雨夜巷斗，RTX 3090 / Q4_K_M）：
    #   开着：196.2 秒，7900 completion tokens，其中思考 22108 字符，正文只有 1337 字符
    #   关掉： 11.4 秒， 407 completion tokens，正文 1531 字符，拒答行为一致
    # 也就是说思考吃掉了 95% 的 token，还挤占 max_tokens 预算。
    if no_think:
        payload["chat_template_kwargs"] = {"enable_thinking": False}

    resp = requests.post(endpoint, json=payload, timeout=timeout)
    resp.raise_for_status()
    msg = resp.json()["choices"][0]["message"]
    # 有的后端把思维链放在 reasoning_content 里
    content = msg.get("content") or ""
    reasoning = msg.get("reasoning_content") or ""
    return strip_thinking(content + ("\n" + reasoning if reasoning else ""))


def cmd_run(args) -> None:
    out_dir = pathlib.Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    system_path = pathlib.Path(args.system)
    if not system_path.exists():
        sys.exit(f"[错误] 找不到系统指令文件: {system_path}")
    system = system_path.read_text(encoding="utf-8").strip()

    briefs = sorted(pathlib.Path(args.briefs).glob("*.txt"))
    if not briefs:
        sys.exit(f"[错误] {args.briefs} 下没有 .txt 文件")

    print(f"模型     : {args.model}")
    print(f"接口     : {args.endpoint}")
    print(f"创意数   : {len(briefs)}")
    print(f"思维链   : {'开（基座默认 xhigh，很慢）' if args.think else '关'}")
    print(f"输出到   : {out_dir}")
    print("-" * 60)

    records = []
    for i, f in enumerate(briefs, 1):
        brief = f.read_text(encoding="utf-8").strip()
        t0 = time.time()
        try:
            raw = call_model(args.endpoint, args.model, system, brief,
                             args.temperature, args.timeout, args.max_tokens,
                             no_think=not args.think)
        except Exception as e:
            print(f"[{i}/{len(briefs)}] 请求失败 {f.name}: {e}")
            records.append({"brief": f.stem, "error": str(e)})
            continue

        (out_dir / f"{f.stem}.md").write_text(raw + "\n", encoding="utf-8")

        refused = is_refusal(raw)
        fmt = check_format(raw)
        records.append({
            "brief": f.stem,
            "refused": refused,
            "passed": (not refused) and fmt["passed"],
            "failed_checks": [k for k, v in fmt["checks"].items() if not v],
            "reasons": fmt["reasons"],
            "chars": len(strip_thinking(raw)),
            "seconds": round(time.time() - t0, 1),
        })

        flag = "拒答" if refused else ("通过" if records[-1]["passed"] else "格式不符")
        print(f"[{i}/{len(briefs)}] {f.stem:8s} {flag:6s} "
              f"{records[-1]['chars']:5d} 字符  {records[-1]['seconds']:5.1f} 秒")

    summary = summarize(records)
    (out_dir / "report.json").write_text(
        json.dumps({"model": args.model, "endpoint": args.endpoint,
                    "think": args.think, "max_tokens": args.max_tokens,
                    "temperature": args.temperature,
                    "records": records, "summary": summary},
                   ensure_ascii=False, indent=2), encoding="utf-8")

    print("-" * 60)
    print_summary(args.model, summary)
    print(f"\n明细已写入 {out_dir / 'report.json'}")
    print("换模型跑第二轮，然后执行:")
    print(f"  python ab-test.py compare --a <第一轮目录> --b {out_dir}")


def summarize(records: list) -> dict:
    ok = [r for r in records if "error" not in r]
    n = len(ok) or 1
    refused = [r["brief"] for r in ok if r["refused"]]
    passed = [r["brief"] for r in ok if r["passed"]]

    counter = {}
    for r in ok:
        for c in r.get("failed_checks", []):
            counter[c] = counter.get(c, 0) + 1

    return {
        "总数": len(records),
        "请求失败": len(records) - len(ok),
        "拒答数": len(refused),
        "拒答率": round(len(refused) / n * 100, 1),
        "一次通过数": len(passed),
        "一次通过率": round(len(passed) / n * 100, 1),
        "平均字符数": round(sum(r["chars"] for r in ok) / n),
        "拒答清单": refused,
        "格式失败项统计": dict(sorted(counter.items(), key=lambda x: -x[1])),
    }


def print_summary(model: str, s: dict) -> None:
    print(f"【{model}】")
    print(f"  拒答率      : {s['拒答率']}%  ({s['拒答数']}/{s['总数']})")
    print(f"  一次通过率  : {s['一次通过率']}%  ({s['一次通过数']}/{s['总数']})")
    print(f"  平均长度    : {s['平均字符数']} 字符")
    if s["格式失败项统计"]:
        print("  格式失败项  : " + ", ".join(
            f"{k}×{v}" for k, v in s["格式失败项统计"].items()))
    if s["拒答清单"]:
        print("  被拒答的    : " + ", ".join(s["拒答清单"]))


def cmd_compare(args) -> None:
    a_dir, b_dir = pathlib.Path(args.a), pathlib.Path(args.b)
    for d in (a_dir, b_dir):
        if not (d / "report.json").exists():
            sys.exit(f"[错误] {d} 下没有 report.json，先用 run 跑一轮")

    ra = json.loads((a_dir / "report.json").read_text(encoding="utf-8"))
    rb = json.loads((b_dir / "report.json").read_text(encoding="utf-8"))
    sa, sb = ra["summary"], rb["summary"]

    print("=" * 60)
    print(" A/B 对比结果")
    print("=" * 60)
    print(f"  A = {ra['model']}")
    print(f"  B = {rb['model']}")
    print()
    print(f"{'指标':<14}{'A':>12}{'B':>12}{'变化':>12}")
    print("-" * 60)

    def row(label, va, vb, unit="%", lower_better=True):
        diff = vb - va
        arrow = ""
        if abs(diff) >= 0.05:
            better = (diff < 0) if lower_better else (diff > 0)
            arrow = "  ✓更好" if better else "  ✗更差"
        print(f"{label:<14}{va:>11}{unit}{vb:>11}{unit}{diff:>+11.1f}{arrow}")

    row("拒答率", sa["拒答率"], sb["拒答率"], lower_better=True)
    row("一次通过率", sa["一次通过率"], sb["一次通过率"], lower_better=False)
    print(f"{'平均字符数':<14}{sa['平均字符数']:>12}{sb['平均字符数']:>12}")

    # 逐条对照
    amap = {r["brief"]: r for r in ra["records"] if "error" not in r}
    bmap = {r["brief"]: r for r in rb["records"] if "error" not in r}
    both = sorted(set(amap) & set(bmap))
    if both:
        print()
        print("逐条对照（A / B）:")
        for k in both:
            fa = "拒答" if amap[k]["refused"] else ("通过" if amap[k]["passed"] else "格式")
            fb = "拒答" if bmap[k]["refused"] else ("通过" if bmap[k]["passed"] else "格式")
            mark = "" if fa == fb else "   ← 不同"
            print(f"  {k:10s} {fa:4s} / {fb:4s}{mark}")

    print()
    print("=" * 60)
    print(" 怎么读这个结果")
    print("=" * 60)
    print("  值得换：拒答率明显下降，且一次通过率没有明显下降")
    print("  不值得：拒答率本来就低（<10%），或一次通过率掉得多")
    print()
    print("  注意样本量：低于 10 条的结论不可靠，")
    print("  且 briefs 里必须包含 3-5 条会触发拒答的擦边/黑暗向内容，")
    print("  否则两边的拒答率都是 0，测不出差别。")
    print()
    print(f"  人工复核：{a_dir}/*.md  与  {b_dir}/*.md")


def main() -> None:
    ap = argparse.ArgumentParser(description="不同模型的提示词产出 A/B 对比（拒答率 / 一次通过率）")
    sub = ap.add_subparsers(dest="cmd", required=True)

    r = sub.add_parser("run", help="用当前加载的模型跑一轮")
    r.add_argument("--briefs", default="briefs")
    r.add_argument("--out", required=True, help="本轮输出目录")
    r.add_argument("--system", default=DEFAULT_SYSTEM)
    r.add_argument("--model", required=True)
    r.add_argument("--endpoint", default=DEFAULT_ENDPOINT)
    r.add_argument("--temperature", type=float, default=0.7)
    r.add_argument("--timeout", type=int, default=900)
    r.add_argument("--max-tokens", type=int, default=8192,
                   help="默认 8192。别调小——开着思维链时思考会吃掉大部分预算，"
                        "4096 会导致正文还没开始写就被截断，测出假的低通过率")
    r.add_argument("--think", action="store_true",
                   help="打开思维链。默认关闭——实测开着慢 17 倍、正文更短，"
                        "还会挤爆 max_tokens 预算。只在专门对比时才用")
    r.set_defaults(func=cmd_run)

    c = sub.add_parser("compare", help="对比两轮结果")
    c.add_argument("--a", required=True)
    c.add_argument("--b", required=True)
    c.set_defaults(func=cmd_compare)

    args = ap.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
