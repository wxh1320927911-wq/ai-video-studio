#!/usr/bin/env python3
"""视觉能力验证：造一张有明确特征的图，让模型描述，看它是不是真的"看得见"。

测三件事：
  1. 形状与数量（两个：圆 + 三角）
  2. 颜色（红圆 + 蓝三角）
  3. 画面里的文字（S07）

只要有一项答错，就说明 mmproj 只是"加载了"但没真正接上。
"""
import base64
import io
import json
import sys
import urllib.request

from PIL import Image, ImageDraw

ENDPOINT = "http://127.0.0.1:11434/v1/chat/completions"
MODEL = "qwen38-27b-heretic"


def make_image() -> bytes:
    img = Image.new("RGB", (512, 384), "white")
    d = ImageDraw.Draw(img)
    # 红色圆（左）
    d.ellipse((40, 140, 200, 300), fill=(220, 30, 30))
    # 蓝色三角（右）
    d.polygon([(300, 300), (390, 140), (480, 300)], fill=(30, 60, 220))
    # 文字 S07（上）
    d.rectangle((190, 30, 330, 100), fill=(240, 240, 240), outline=(0, 0, 0), width=3)
    d.text((215, 45), "S07", fill=(0, 0, 0))
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


def ask(png: bytes, question: str, max_tokens: int = 512) -> str:
    b64 = base64.b64encode(png).decode()
    payload = {
        "model": MODEL,
        "messages": [{
            "role": "user",
            "content": [
                {"type": "text", "text": question},
                {"type": "image_url",
                 "image_url": {"url": f"data:image/png;base64,{b64}"}},
            ],
        }],
        "max_tokens": max_tokens,
        "temperature": 0,
    }
    req = urllib.request.Request(
        ENDPOINT,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=300) as r:
        d = json.load(r)
    return (d["choices"][0]["message"].get("content") or "").strip()


if __name__ == "__main__":
    png = make_image()
    print(f"测试图已生成：512x384 PNG，{len(png)} 字节")
    print("内容：左边一个红色圆形，右边一个蓝色三角形，上方灰底黑框内写有文字 S07")
    print("=" * 60)
    q = ("用中文回答，只答这三点，不要解释：\n"
         "1. 图里有几个几何形状？\n"
         "2. 分别是什么颜色？\n"
         "3. 图里的文字是什么？")
    print(f"[提问] {q}")
    print("-" * 60)
    try:
        ans = ask(png, q)
    except Exception as e:  # noqa: BLE001
        print(f"[失败] 请求出错：{type(e).__name__}: {e}")
        sys.exit(1)
    print("[模型回答]")
    print(ans if ans else "(空)")
    print("=" * 60)
    low = ans.lower()
    hit_shape = ("两" in ans or "2" in ans)
    hit_color = ("红" in ans) and ("蓝" in ans)
    hit_text = "s07" in low or "S07" in ans
    print(f"形状数对: {'是' if hit_shape else '否'} | "
          f"颜色对: {'是' if hit_color else '否'} | "
          f"文字对: {'是' if hit_text else '否'}")
    print("结论：" + ("视觉可用" if (hit_shape and hit_color and hit_text)
                     else "**视觉没真正接上**"))
