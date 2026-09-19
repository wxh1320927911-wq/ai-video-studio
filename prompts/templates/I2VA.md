# I2VA 模板（首帧图生视频）

复制下面整块。**第一行是对齐指令，不能省，后面必须跟一个空行。**

```
For the target video, at 0.00 seconds into the target video, <Picture 1> (from [Shot 1]) is fully referenced.

integrated_multimodal_description: [Shot 1] <风格词, 与参考图保持一致>, <复述参考图里的主体与构图>, preserving her/his appearance, clothing, position, and <场景要素>. <镜头运动句> as <主体动作>. <说话人身份与音色> (S1) says: <d>[Chinese] <逐字原文>.</d> <收尾动作>.

overall_soundscape: <环境声与动作声，1-4 句>.

non_diegetic_music: <配乐描述>. 没有就写 N/A
```

## 与 T2VA 的区别

| | T2VA | I2VA |
| --- | --- | --- |
| 首行对齐指令 | **不要** | 必须有，固定写法 |
| `<Picture 1>` | 不出现 | 是 0.00 秒的首帧，属于 `[Shot 1]` |
| 风格 | 从提示词里选 | **从参考图推导** |
| 结构 | 自由 | 首帧锚定 → 动作起始 → 连续发展 → 结果或反应 |

## 填空提醒

- **第一行原样照抄**，`<Picture 1>` 就是 0.00 秒那一帧，不要改成别的编号
- 正文开头要**复述参考图里的关键信息**（主体外观、服装、位置、场景布局），让模型知道哪些要保留
- 参考图里没有的东西不要凭空加，模型会跟着画面走

## 参数配套

- ComfyUI 里把首帧图接进 `MiniMaxH3ImageToVideo` 节点的 `first_frame` 输入
- 画幅跟随输入图，不用手动设 ratio
- 同样可以先 `Megapixels 0.4` + turbo 试跑
