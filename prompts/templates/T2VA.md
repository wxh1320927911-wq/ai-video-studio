# T2VA 模板（纯文生视频）

复制下面整块，把 `<>` 里的内容替换掉。**注意：T2VA 不要对齐指令那一行。**

```
integrated_multimodal_description: [Shot 1] <风格词: Live-action, cinematic / 2D-animated / 3D CG>, <初始构图: a medium-wide shot frames ...>, <主体外观与所在位置>. <镜头运动句: The camera pushes in with small amplitude at slow speed toward ...> <主体动作>, <说话人身份与音色> (S1) says: <d>[Chinese] <逐字原文，不翻译>.</d> <后续动作>. [Shot 2] At 00:0X.XXX, the camera cuts to <新构图与新信息>, <动作或反应>, <画面可见文字写成英文双引号: a sign reading "营业中">.

overall_soundscape: <环境声，1-4 句，只写环境声、物理动作声、非语言人声；不重复对白>.

non_diegetic_music: <乐器> at a <slow / moderate / fast> tempo, <音量变化>. 没有就写 N/A
```

## 填空提醒

| 位置 | 要点 |
| --- | --- |
| `[Shot 1]` 开头 | 必须先写风格词再写构图，风格从这几种里选：`Live-action` `Cinematic` `2D-animated` `3D CG` `claymation` `watercolor` `vintage film` |
| 第二个镜头 | 用 `[Shot 2] At 00:03.500, the camera cuts to` 开头，时间严格递增，且不能超过总时长 |
| 说话人 | `(S1)` 跨镜头保持同一个编号；首次出现要交代音色和语速；不发声的角色不给编号 |
| `<d>` 标签 | 里面**只放** `[语言]` + 原文，逐字逐标点保留。识别短语和动作写在 `<d>` 外面 |
| 画外音 | 用 `says in an off-screen voiceover`，且 `<d>` 后立刻加 `while his/her lips remain completely closed` |
| 画面文字 | 用英文双引号包起来，保留原文，每一处都单独列出。不写清楚会糊成乱码 |
| 配乐 | 只写乐器、速度、节奏、音量变化。**不写"悲伤的""宏大的"这类抽象情绪词** |

## 参数配套

| 参数 | 建议 |
| --- | --- |
| 画幅 | 16:9 满画布 = 1344×768，对应 Resolution Selector 的 `Megapixels 0.98` |
| 试跑 | `Megapixels 0.4` + `turbo_mode` 开 + `turbo_steps 8` |
| 时长 | 对齐 24fps 的 17k+5 帧网格（5、22、39、56… 帧） |
| 分辨率取整 | `Multiple` 保持 `32`，不要改 |

完整示例见 `../docs/03-H3提示词写法.md` 第八节。
