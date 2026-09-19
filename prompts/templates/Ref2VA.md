# Ref2VA 模板（全参考模式）

复制下面整块。**这是六个部分，不是三个字段**，和 T2VA/I2VA/FL2VA/L2VA 完全不是一个结构。

配套系统指令用 `../system-prompt-ref2va.txt`（不是 `system-prompt.txt`）。

```
subject_definitions:
<Subject 1> is <可复用的可见内容>, <需要保持的主要特征>.
<Subject 2> is <另一个可见内容>, <特征>.
<Audio 1> is the voice-timbre reference for <Subject 1> (S1), containing <音频内容>.

summary:
[<任务类型> + <任务类型>] <一段英文，概述目标视频与主要引用关系>.

retention_analysis:
<Subject 1> (appears in [Shot 1], [Shot 2]): fully_preserved - <保留了哪些特征>.
<Subject 2> (appears in [Shot 1]): partially_preserved - <哪些变了、哪些没变>.
<Audio 1>: reference - <怎么被参考的>.

detailed_description:
<一两句英文交代整体风格，写在 [Shot 1] 之前>.
[Shot 1] <构图与主体，首次出现处插入 <Subject N>>. <镜头运动句> as <动作>, <主体> (S1) says, <d>[English] <逐字原文></d>. <反应>.
[Shot 2] At 00:03.000, the shot cuts to <新构图，插入引用标签>. <主体> (S2) says in <音色描述>, <d>[English] <逐字原文></d>.

overall_soundscape:
<一段英文，全片环境音与物理声>.

non_diegetic_music:
<一段英文；复用参考音频时写明，如 <Audio 2> is directly reused as the complete audience-only score.> 没有就写 N/A
```

## 六段各自最容易写错的地方

| 段 | 最容易错的 |
| --- | --- |
| `subject_definitions` | 参考图只用来定义角色/服装/风格时**不要单独建 `<Picture N>` 条目**，写进对应 `<Subject N>` 里 |
| `summary` | 必须带方括号任务类型前缀；多个关系用 ` + ` 连接且**不重复同一类型** |
| `retention_analysis` | **绝不能写 `(Sx)`**；标记只能在已定义的角色范围内选 |
| `detailed_description` | 风格句写在 `[Shot 1]` **之前**（和基础模式相反）；听不清的写 `[unclear]`，不要猜 |
| `overall_soundscape` | 不要重复 `<d>` 里的对白 |
| `non_diegetic_music` | 同上 |

## 四种标签怎么选

| 标签 | 什么时候用 |
| --- | --- |
| `<Subject N>` | 内容是**可复用的可见元素**——人物、场景、服装、道具、风格、动作、姿态 |
| `<Picture N>` | 这张图**本身充当某一帧**（首帧/关键帧/末帧/构图锚点） |
| `<Video N>` | 提供剪辑源、续接起点、或整段时间结构 |
| `<Audio N>` | 被复制或被参考的音频信号 |

**两个高频错误：**

1. **`<Video N>` 和 `<Audio N>` 独立编号，不配对。** 同一个参考视频可能是 `<Video 1>` 配 `<Audio 2>`。
   而且**普通参考视频不会仅因为带声音就自动产生 `<Audio N>`**——只有它的音轨真的被复制或参考了才建条目。
2. **人物/物体/场景哪怕来自参考视频，也归 `<Subject N>`**，不要因为它来自视频就写成 `<Video N>`。
   `<Video N>` 只管「整段视频层面」的关系。

## 任务类型前缀怎么选

| 类型 | 什么时候用 |
| --- | --- |
| `keyframe completion` | 图片作为目标视频的首帧/关键帧/末帧/编辑后关键帧等**具体帧锚点** |
| `reference generation` | 素材只提供生成指导（人物/场景/风格/动作/运镜/分镜），**不充当具体帧** |
| `video editing` | 直接修改已有源视频 |
| `video continuation` | 从已有源视频继续/延伸/衔接 |
| `audio reuse` | 同一音频信号被整体或部分复用 |
| `audio reference` | 不复制信号，只参考风格/音色/内容/质感/节拍/连续性 |

> **素材里有视频或音频，不等于自动产生对应任务类型。** 参考视频只提供运镜、剪辑或节奏时，算 `reference generation`。

## 关系标记怎么选

**可见内容**：`fully_preserved` / `partially_preserved` / `attribute_transfer` / `weak_reference`

**音频**：`fully_copy` / `partially_copy` / `reference` / `weak_reference`

> 目标视频里**新增**的动作、背景、情节**不算**引用保真度的损失，不要写进 `retention_analysis`。

## 长度与语言

- 六个部分**全部用英文写**，只有两处保留原文：`<d>` 内的对白与歌词，以及画面里真实可见的文字（用英文双引号）
- `detailed_description` 生成类任务通常 **350-500 英文词**；对白密集时优先写全口播时间线，不要凑字数
- **单镜不构成写短的理由**，按信息量分配细节

---

> ⚠️ **当前检查器还不支持 Ref2VA。** `scripts/ab-test.py` 的 12 条判据只覆盖基础三字段格式，
> 拿它跑 Ref2VA 产出会一律判"格式不符"，而且**不会告诉你真正原因**。
> 要跑 Ref2VA 得先给检查器补一套六段结构的判据。
