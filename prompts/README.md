# prompts/ 目录约定

## 一句话：本地这份是唯一真源

租来的实例只是**临时工作区**——跑完就关，可能直接释放。所以提示词相关的东西一律以本地为准，实例上不留唯一副本。

## 各类东西放哪

| 内容 | 位置 | 说明 |
| --- | --- | --- |
| 系统指令（基础模式） | `system-prompt.txt` | T2VA / I2VA / FL2VA / L2VA 用这份 |
| 系统指令（Ref2VA） | `system-prompt-ref2va.txt` | **六段结构，和上面那份不能混用** |
| 提示词模板 | `templates/` | T2VA / I2VA / FL2VA / L2VA / Ref2VA 五份空白骨架，复制后填 |
| 创意输入 | `briefs/` | 每条创意一个 `.txt`，文件名 = 片段编号 |
| 提示词产出 | `output/` | 批量脚本生成的 `.md`，与 brief 同名 |
| 参考素材 | 项目根 `assets/` | 首帧图、参考视频、参考音频 |
| 写法规范 | `../docs/03-H3提示词写法.md` | 标签语法、字段含义、常见问题改法 |

> ⚠️ **两份系统指令不是同一套结构，不能混用。** 基础模式是三个字段（`integrated_multimodal_description` / `overall_soundscape` / `non_diegetic_music`）；Ref2VA 是六个部分（`subject_definitions` / `summary` / `retention_analysis` / `detailed_description` / `overall_soundscape` / `non_diegetic_music`）。
> 用错了会产出错误结构，**而且当前检查器查不出来**——它只认三字段，会一律判"格式不符"却不告诉你原因。

## 怎么流转

```
本地 briefs/  ──上传──▶  实例 /root/work/briefs/
                              │
                     batch-prompts.py
                              │
本地 output/  ◀──下载──  实例 /root/work/prompts/
```

上传下载都走 SSH（`scp`）或实例上的网页聊天界面。**跑完把 output/ 整个下载回来，然后立刻关机。**

> **别用 JupyterLab。** 本项目的实例上 `jupyter_port=0`，8443 端口连不上，这条路是断的。传文件用 `scp -P <端口>`。

## 命名约定

- `briefs/S01.txt` → `output/S01.md`，靠同名对应，一眼能看出哪条创意生成了哪份提示词
- 片段编号按总时间线顺序：`S01`、`S02`、`S03`……方便最后和成片逐段对照
- 只想重跑某几条：把要重跑的那几条放进 `briefs/`，其余先挪走，或者直接 `--force` 全量重跑

## 网页界面里存的东西不算存储

规划机跑的是 `llama.cpp` 的 `llama-server`，**它自带聊天界面**（在 `/` 路径），起服务后回 AutoDL 控制台点「自定义服务」即可打开。详见 `../docs/05` 第 9.11 / 9.12 节。

但要知道：

> **界面里的一切都只存在于实例的内存和临时文件里，实例一释放就全没了。**

所以：

- 真源永远是本地这两份 `system-prompt*.txt`
- 界面里改完的提示词，记得同步回本地文件
- 别在界面里存任何唯一副本

> 早期方案用的是 Open WebUI，已废弃——`llama-server` 自带界面，不需要额外装东西，也就少了一层数据落盘的地方。

## 参考素材（assets/）

参考素材是给**生成机**用的，不是给规划机用的。流程是：

1. 素材原件存在本地 `assets/`
2. 生成时上传到实例（ComfyUI 的 Load Image 节点上传后，文件会落到实例的 `ComfyUI/input/`）
3. 提示词里按顺序引用：`<Picture 1>`、`<Video 1>`、`<Audio 1>`，顺序必须和上传顺序完全一致
4. 生成完把成片下载回本地，实例上的素材随实例释放一起消失——原件还在本地，不怕

**一致性靠素材不靠文字。** 角色长相、场景风格要跨片段保持一致，就得靠同一批参考素材反复引用，别指望模型记住你的故事。
