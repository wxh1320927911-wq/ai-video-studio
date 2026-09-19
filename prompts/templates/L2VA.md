# L2VA 模板（尾帧生视频）

复制下面整块。`S.SS` 换成**实际总时长**，保留两位小数。

```
How the reference pictures align with the target video — <Picture 1> (from [Shot N]) aligns with the S.SS-second mark of the target video.

integrated_multimodal_description: [Shot 1] <风格词, 与参考图一致>, <推演出的合理开场：主体姿态、构图、场景>. <镜头运动句> as <主体开始动作>, <中间可观察的变化>, <差异逐步收窄>, and settles into the pose, spacing, and composition of <Picture 1> at the end of the shot.

overall_soundscape: <环境声与动作声，1-4 句>.

non_diegetic_music: <配乐描述>. 没有就写 N/A
```

## 和 FL2VA 的区别

两个都是「终点锚定」，但方向不同：

| | FL2VA | L2VA |
| --- | --- | --- |
| 给了什么 | 首帧 + 尾帧 | **只有尾帧** |
| 对齐指令 | `Picture 1` + `Picture 2` | 只有 `<Picture 1>`，对齐末帧 |
| 尖括号 | **不带** | **带** |
| 要推演什么 | 首尾之间的连续路径 | **一个合理的开场**（模型自己倒推） |

## 填空提醒

- **`<Picture 1>` 属于最后一个镜头，不属于 Shot 1。** 这点和 I2VA 正好相反——I2VA 的 `<Picture 1>` 是 Shot 1 的首帧。
  写对齐指令时别顺手写成 `(from [Shot 1])`。
- **开场要"合理"，不是"随便"。** 尾帧是硬约束，开场必须能自然发展到尾帧。推演时先想清楚"什么动作会导致尾帧这个状态"，再倒着写开场。
- **中间变化要可观察**：姿态、物体操作、构图演变、光线过渡。不要写心理活动。
- 单镜为主。要切镜就拆成两个片段，别在一个 L2VA 里塞多镜。

## 什么时候用它

比 FL2VA 少一张图时的替代方案。典型场景：

- 手头只有一张想要的**结束画面**，没有合适的第一帧
- 做「结果 → 回溯过程」的镜头
- 手绘/生成了一张满意的构图，想让它成为落点

**代价是控制力更弱**：首帧完全由模型推演，可能推出你不想要的开始。如果对开场也有明确要求，**用 FL2VA 补一张首帧**，别指望文字描述能完全约束住。

## 参数配套

- ComfyUI 里把图接进 `MiniMaxH3ImageToVideo` 节点的 `last_frame`
- 时长按尾帧时间点填，并确认落在 17k+5 帧网格上
