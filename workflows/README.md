# workflows/ —— 官方 H3 工作流原件

这三个 JSON 是从 **ComfyUI 官方模板库**原样下载的，未做任何修改：

- 来源仓库：<https://github.com/Comfy-Org/workflow_templates>（`main` 分支 `templates/` 目录）
- 下载日期：2026-09-22
- 用途：直接拖进 ComfyUI 界面加载，省掉「工作流 → 浏览模板」翻找的步骤，也让配置可复现（文件在版本库里，模板库更新不影响我们）

| 文件 | 官方标题 | 节点数 | 结构 | 最低 ComfyUI |
| --- | --- | --- | --- | --- |
| `video_minimax_h3_t2v.json` | MiniMax H3: Text to Video | 6 | **含 1 个子图** | 0.30.0 |
| `video_minimax_h3_i2v.json` | MiniMax H3: Image to Video | 9 | **含 1 个子图** | 0.30.0 |
| `video_minimax_h3_r2v.json` | MiniMax H3: Reference to Video | 29 | 无子图，扁平 | 0.30.0 |

最低版本号来自官方模板索引里的 `minComfyUIVersion` 字段，不是我推测的。

## 加载方式

ComfyUI 界面里把 JSON 文件**直接拖到画布上**即可（或菜单「工作流 → 打开」选文件）。

**T2V / I2V 用了 Subgraph 功能**——加载后看到的是一个打包好的子图节点，参数在节点上直接改，双击可以展开看内部。子图是较新的界面特性，如果加载报错或节点显示异常，说明 ComfyUI 版本太老。

## T2V 子图节点对外暴露的参数（逐个核对过）

| 参数名 | 默认值 | 说明 |
| --- | --- | --- |
| `prompt` | （官方示例提示词） | 提示词正文 |
| `width` / `height` | 1344 / 768 | 由 Resolution Selector 驱动，一般不用手改 |
| `duration` | 5 | **单位是秒**，不是帧数。内部用 Math Expression 换算成帧并对齐 17k+5 网格 |
| `noise_seed` | 757358688076805 | 固定种子，可复现 |
| `unet_name` | `minimax_h3_fl2va_pruned_int8_convrot.safetensors` | 扩散模型 |
| `clip_name` | `qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors` | 文本编码器 |
| `vae_name` | `minimax_h3_video_vae_fp16.safetensors` | 视频 VAE |
| `audio_vae` | `minimax_h3_audio_vae_fp32.safetensors` | 音频 VAE |
| `turbo_mode` | `false` | 打开才走加速 LoRA 分支 |
| `lora_name` | `minimax_h3_fl2v_turbo_8step_v1.0_comfyui_bf16.safetensors` | 加速 LoRA |
| `turbo_model_strength` | 1 | LoRA 强度 |
| `turbo_steps` | 8 | **只有 `turbo_mode` 打开时才生效** |

**注意：没有 `steps` 这个控件。** 步数由内部两个分支决定——`turbo_mode` 关时用内部固定的 20 步，开时用 `turbo_steps`。网上很多教程写的「把 steps 改成 N」在这个工作流里改不到，别找。

分辨率由顶层的 `Resolution Selector` 节点控制（默认 16:9 / 0.4 MP / multiple 32）。各档位对应像素见工作流内自带的说明便签，0.4 档 = 864×480，0.98 档 = 1344×768（官方满画布）。

## 还有哪些 H3 工作流（没下到本地，需要时再去模板库取）

| 模板名 | 标题 | 最低 ComfyUI | 说明 |
| --- | --- | --- | --- |
| `video_fastvideo_fasth3_t2v` / `_i2v` | FastVideo FastH3 | **0.36.0** | 独立的 8 步蒸馏检查点（不是 LoRA），专为速度做的另一套权重，2026-09-15 发布。**权重不在 `Comfy-Org/MiniMax-H3` 里**，要另外找 |
| `video_minimax_h3_multiframe_reference` | MiniMax H3: Multiframe Reference | 0.34.0 | 最多 4 张参考帧锚定在时间轴任意位置，做续接、卡叙事节点用 |
| `video_minimax_h3_fun_controlnet_union` | MiniMax H3 Fun ControlNet Union | 0.35.0 | 用参考视频做姿态控制（对应 HF 里的 `model_patches/minimax_h3_fun_controlnet_union_*`） |
| `video_minimax_h3_i2v_continuation` | Image to Video | 0.30.0 | 首帧 + 空提示词续写 |

## 复现下载命令

```bash
base=https://raw.githubusercontent.com/Comfy-Org/workflow_templates/main/templates
curl -sL "$base/video_minimax_h3_t2v.json" -o video_minimax_h3_t2v.json
curl -sL "$base/video_minimax_h3_i2v.json" -o video_minimax_h3_i2v.json
curl -sL "$base/video_minimax_h3_r2v.json" -o video_minimax_h3_r2v.json
```

模板索引（含每个模板的最低版本号与模型清单）：
<https://raw.githubusercontent.com/Comfy-Org/workflow_templates/main/templates/index.json>
