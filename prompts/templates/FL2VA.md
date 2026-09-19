# FL2VA 模板（首尾帧生视频）

复制下面整块。`S.SS` 换成**实际总时长**，保留两位小数。

```
How the reference pictures align with the target video — Picture 1 (from Shot 1) aligns with the 0.00-second mark of the target video; Picture 2 (from [Shot N]) aligns with the S.SS-second mark of the target video.

integrated_multimodal_description: [Shot 1] <风格词, 与参考图一致>, <复述首帧的主体姿态、构图与场景>. <镜头运动句> as <主体开始动作>, <中间可观察的变化>, <逐步收窄差异>, and settles into the pose, spacing, and composition established by Picture 2 at the end of the shot.

overall_soundscape: <环境声与动作声，1-4 句>.

non_diegetic_music: <配乐描述>. 没有就写 N/A
```

> ⚠ **`[Shot N]` 里的 `N` 是实际最后一个镜头的序号，不是写死的 1。**
> 单镜时 `N=1`，正好和 `Shot 1` 一样，所以容易抄错还以为对了。多镜时必须改成真实序号。

## 与另外几种的区别

| | T2VA | I2VA | FL2VA | L2VA |
| --- | --- | --- | --- | --- |
| 对齐指令 | 无 | `<Picture 1>` 对齐 0.00 秒 | `Picture 1` + `Picture 2` 对齐首尾 | `<Picture 1>` 对齐末帧 |
| 图片引用写法 | — | 带尖括号 `<Picture 1>` | **不带尖括号** `Picture 1` | 带尖括号 `<Picture 1>` |
| 结构 | 自由 | 首帧锚定 → 发展 → 结果 | 首帧状态 → 中间变化 → 差异收窄 → 尾帧状态 | 倒推合理开场 → 向尾帧收敛 |

## 填空提醒

- **FL2VA 一般不倾向多镜头。** 首尾帧模式的重点是让模型连续插值，加 `[Shot 2]` 反而容易跳变。要切镜就拆成两个片段。
- 中间变化要写**可观察的**：姿态变化、物体操作、构图演变、光线过渡。不要写"然后她想到了什么"这种看不见的东西。
- 时长以**尾帧时间点**为准，写 `8.00-second mark` 就意味着总时长 8 秒。

## 为什么这个模式最有用

**它是维持跨片段一致性的主力工具。** 上一段的末帧直接作为下一段的首帧，画面和动作天然接得上，比用文字描述"接着上一段"可靠得多。

做连续动作或长镜头时，优先用它，而不是靠提示词描述衔接。

## 参数配套

- ComfyUI 里把两张图分别接进 `MiniMaxH3ImageToVideo` 节点的 `first_frame` 和 `last_frame`
- 时长按首尾帧之间的实际秒数填，并确认落在 17k+5 帧网格上
