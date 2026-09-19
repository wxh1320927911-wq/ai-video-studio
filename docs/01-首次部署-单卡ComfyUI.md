# 01 · 首次部署：单卡 ComfyUI 跑通第一个片段

> 目标：从零开始，在 AutoDL 上跑出**一个 5 秒、带立体声、768p 的 mp4**，并下载回本地。
> 预计耗时：首次约 1.5–2.5 小时（其中 1–2 小时是下载模型和装环境）。
> 预计花费：约 ¥4–6（4090 按量计费）+ 数据盘扩容费。
> 全程只需要一台电脑 + 一个浏览器，不需要本地显卡。

这一份是「首次部署」，做一次就够。以后每次创作看 `02-每次创作流程.md`。

---

## 第 0 步 · 先想清楚要生成什么

**这一步在本地做，不花钱。** 在 `prompts/` 里先把第一条测试提示词写好，再去租卡。

原因很简单：AutoDL 从开机就开始计费，你对着界面想提示词的时候，卡也在烧钱。把创作和算力分开，是这个流程里最省钱的一条纪律。

第一条测试建议就用 `prompts/第一条测试提示词.md` 里的内容，先别追求好看，先确认整条链路通。

---

## 第 1 步 · 注册与充值

1. 打开 <https://www.autodl.com> 注册账号。
2. 做实名认证。**如果是学生，一定做学生认证**，认证后自动升级为「炼丹会员」，所有卡打 95 折。
3. 充值。第一次建议先充 **20–30 元**，够跑通两三次，不用一次充多。

> 只有官网是充值入口，任何第三方代充都不要用。

---

## 第 2 步 · 创建实例

进入「控制台」→「容器实例」→「租用新实例」。按下面的顺序选：

### 2.1 地区

选离你近的机房（如内蒙 A、北京 B、西北 B）。影响上传下载速度，不影响生成速度。

### 2.2 卡型

选 **RTX 4090 / 24GB**，数量 **1 张**。

- 3090（¥1.32/时）更便宜，但算力只有 4090 的一半左右，5 秒片段可能从 8 分钟变成 15 分钟以上。第一次跑通建议用 4090 换时间。
- 5090（¥2.78/时）显存 32GB，原生 NVFP4，等第二阶段确认要长期做再换。

> **4090 经常缺货。** 列表里如果 RTX 4090 显示无空闲卡，按这个顺序退让：
> 1. 换地区（内蒙 A / 北京 B / 西北 B 轮流看）
> 2. 换 **5090**（¥2.78/时）——贵 48%，但显存更大、原生 NVFP4，跑得更快
> 3. 换 **3090**（¥1.32/时）——最便宜，但第一次跑通会明显慢，容易误判成"配置有问题"
>
> 不要为了省几块钱在 3090 上排查性能问题。第一次跑通，时间比钱值钱。

### 2.3 主机（最关键的一步）

同一卡型下会列出多台主机。**点开看每台主机的 CPU/内存配置**。

AutoDL 的内存是**按 GPU 数量成倍分配**的（例如主机规则写 `32GB/GPU、8核/GPU`，租 1 张卡就是 `8 核 + 32GB 内存`）。

**必须选内存 ≥32GB/GPU 的主机。** H3 的量化版靠动态 offload 把组件在显存和内存之间搬运，内存不够会退化成从磁盘反复读 21GB 权重，速度能差 3–4 倍。这是第一阶段最容易忽略、也最影响体验的一个参数。

### 2.4 镜像

两条路，任选：

- **省事**：选「社区镜像」，搜 `ComfyUI`。社区镜像通常已经装好 ComfyUI 和常用节点，开机即用。
- **可控**：选「基础镜像」→ PyTorch，然后自己 `git clone` ComfyUI。版本自己掌握，排错更清楚。

无论哪条，注意两点：

1. **ComfyUI 版本必须 ≥ 0.30.0**，低版本没有 MiniMax H3 的原生节点。
2. 社区有报告称 **cu128 的 PyTorch 会让 int8 推理内核静默失效，速度慢 3 倍**，换 cu13x 后恢复正常。能选 cu13x 的镜像就优先选；只有 cu128 的话也先跑通，之后再对照排查。

### 2.5 数据盘

默认 50GB。**建议扩容到 100GB。**

模型文件合计约 42GB（见第 4 步），加上 ComfyUI、依赖和生成结果，50GB 会非常紧张。

> ⚠️ 付费扩容的数据盘**无论实例是否开机，每天都会计费**。用完记得缩容或释放实例，否则会一直扣。

### 2.6 创建

确认配置后点「立即创建」，实例开始运行。

---

## 第 3 步 · 进入实例，先做体检

在实例卡片上点「JupyterLab」，打开后新建一个终端（Terminal）。

先跑一遍体检脚本（把 `scripts/check-env.sh` 的内容粘进去，或直接把文件传上去）：

```bash
source /root/.bashrc
nvidia-smi
echo "---- 内存 ----"
free -g
echo "---- 磁盘 ----"
df -h / /root/autodl-tmp
echo "---- Python / CUDA ----"
python -c "import torch;print('torch',torch.__version__,'cuda',torch.version.cuda)"
```

**检查三件事：**

| 看什么 | 合格线 | 不合格怎么办 |
| --- | --- | --- |
| 显存 | 24GB 可用 | 换卡型 |
| 内存（free 的 total） | **≥32GB** | 换主机，别硬跑 |
| 数据盘可用空间 | ≥50GB | 扩容数据盘 |

顺带把 Python 依赖拉齐：

```bash
pip install -U "huggingface_hub[cli]"
```

---

## 第 4 步 · 下载模型（约 42GB）

H3 的模型在 Hugging Face 的 `Comfy-Org/MiniMax-H3` 仓库。国内直连很慢，**先开 AutoDL 的学术加速**：

```bash
source /etc/network_turbo
```

然后跑 `scripts/download-models.sh`（内容见下，也可以直接照抄命令）。

### 4.1 确定 ComfyUI 的路径

不同镜像里 ComfyUI 位置不一样，先找一下：

```bash
ls -d /root/autodl-tmp/ComfyUI /root/ComfyUI /root/comfyui 2>/dev/null
```

假设结果是 `/root/autodl-tmp/ComfyUI`，把它记下来，后面都用这个路径（脚本里叫 `COMFY_DIR`）。

> **如果 ComfyUI 装在系统盘（`/root/ComfyUI`）**：系统盘只有 30GB，装不下 42GB 模型。把 models 目录软链到数据盘：
> ```bash
> mkdir -p /root/autodl-tmp/ComfyUI-models
> rm -rf /root/ComfyUI/models && ln -s /root/autodl-tmp/ComfyUI-models /root/ComfyUI/models
> ```
> 之后所有模型都往 `/root/autodl-tmp/ComfyUI-models` 里放。

### 4.2 要下的文件（第一阶段最小集合）

| 用途 | 文件 | 大小 |
| --- | --- | --- |
| 扩散模型（文生 / 首帧尾帧） | `diffusion_models/minimax_h3_fl2va_pruned_int8_convrot.safetensors` | 20.97 GB |
| 文本编码器 | `text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors` | 15.69 GB |
| 视频 VAE | `vae/minimax_h3_video_vae_fp16.safetensors` | 5.21 GB |
| 音频 VAE | `vae/minimax_h3_audio_vae_fp32.safetensors` | 0.61 GB |
| Turbo LoRA（8 步，提速用） | `loras/minimax_h3_fl2v_turbo_8step_v1.0_comfyui_bf16.safetensors` | 1.96 GB |
| **合计** | | **约 44.4 GB** |

省空间的做法：视频 VAE 可以用 int8 版（`minimax_h3_video_vae_int8_convrot.safetensors`，2.81GB）替掉 fp16 版，省 2.4GB。

**第一阶段先不要下的：**

- `ref2va` 系列（参考生视频），以后再下，避免数据盘翻倍。
- `bf16` 原版（66GB）和 `int8` 未剪枝版（34GB），消费级卡跑不动，别浪费下载时间。

### 4.3 下载命令

```bash
source /etc/network_turbo
cd /root/autodl-tmp

COMFY_DIR=/root/autodl-tmp/ComfyUI          # 换成你自己的路径
mkdir -p "$COMFY_DIR/models/diffusion_models" \
         "$COMFY_DIR/models/text_encoders" \
         "$COMFY_DIR/models/vae" \
         "$COMFY_DIR/models/loras"

hf download Comfy-Org/MiniMax-H3 \
  --include "diffusion_models/minimax_h3_fl2va_pruned_int8_convrot.safetensors" \
            "text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors" \
            "vae/minimax_h3_video_vae_fp16.safetensors" \
            "vae/minimax_h3_audio_vae_fp32.safetensors" \
            "loras/minimax_h3_fl2v_turbo_8step_v1.0_comfyui_bf16.safetensors" \
  --local-dir /root/autodl-tmp/h3-dl

# 把文件搬到 ComfyUI 对应目录
cp /root/autodl-tmp/h3-dl/diffusion_models/*.safetensors "$COMFY_DIR/models/diffusion_models/"
cp /root/autodl-tmp/h3-dl/text_encoders/*.safetensors   "$COMFY_DIR/models/text_encoders/"
cp /root/autodl-tmp/h3-dl/vae/*.safetensors             "$COMFY_DIR/models/vae/"
cp /root/autodl-tmp/h3-dl/loras/*.safetensors           "$COMFY_DIR/models/loras/"
rm -rf /root/autodl-tmp/h3-dl
```

`hf download` 支持断点续传，网络断了重跑同一条命令即可，不会从头再来。

**下载过程中可以随时另开一个终端看进度：**

```bash
du -sh /root/autodl-tmp/h3-dl
```

### 4.4 关于无卡模式（可选省钱手段）

下载 42GB 不需要 GPU。AutoDL 提供**无卡模式开机**：配置为 0.5 核 / 2GB 内存 / 无 GPU，统一 **¥0.1/小时**。

流程是：正常开机建好实例 → 关机 → 无卡模式开机 → 下载模型 → 关机 → 正常开机。

省下的是 ¥1.78/小时（4090），下载两小时省 ¥3.5 左右。

**代价是：无卡模式会释放 GPU，等你正常开机时，这张卡可能已经被别人租走了。** 时间紧、或者不想赌，就直接用正常模式一次做完。这笔账差别不大，别为了省几块钱卡住一整天。

---

## 第 5 步 · 启动 ComfyUI，用浏览器打开

ComfyUI 要一直运行，SSH 一断就停，所以用 `nohup` 挂后台：

```bash
cd "$COMFY_DIR"
nohup python main.py --listen 0.0.0.0 --port 6006 > /root/autodl-tmp/comfyui.log 2>&1 &
```

**为什么是 6006 端口？** AutoDL 的实例没有独立公网 IP，但平台为每个实例的 **6006 和 6008 端口**默认做了公网映射，不需要企业认证。其它端口要开放得做企业认证，所以 ComfyUI 就放 6006。

然后回到 AutoDL 控制台，在实例的快捷工具里点「**自定义服务**」，复制那个地址（形如 `https://u39-b3fb-39a640fd.nmb2.seetacloud.com:8443`），在本地浏览器打开，就是 ComfyUI 界面。

**排错：**

```bash
tail -n 50 /root/autodl-tmp/comfyui.log     # 看启动日志
ss -tlnp | grep 6006                        # 确认端口在监听
```

如果启动报缺依赖，一般是 `pip install -r requirements.txt` 没跑完，补上再重启。

---

## 第 6 步 · 跑出第一个片段

### 6.1 加载模板

界面顶部菜单「**工作流**」→「**浏览模板**」→ **视频** 分类 → 选 **MiniMax H3 T2V** → 加载。

加载后如果弹出「缺少模型」的提示，**不用点自动下载**——我们已经手动下好了。确认文件名和节点里要求的完全一致即可（模板要求的就是第 4.2 节那几个文件名）。

### 6.2 参数设置（第一次先求快）

| 节点 | 参数 | 第一次建议值 |
| --- | --- | --- |
| Resolution Selector | Aspect ratio | `16:9 (Widescreen)` |
| Resolution Selector | Megapixels | **`0.4`**（先小后大，0.98 才是 1344×768 满画布） |
| Resolution Selector | Multiple | `32`（不要改，这是 H3 的分辨率网格） |
| MiniMax H3 | 时长 / length | **5 秒**（会自动对齐到 17k+5 帧网格） |
| MiniMax H3 | steps | 默认 20 |
| MiniMax H3 | **turbo_mode** | **打开**，`turbo_steps` = 8 |
| Prompt | 提示词 | 粘 `prompts/第一条测试提示词.md` 的内容 |

turbo 模式用 8 步代替 20 步，速度大约快一倍多，代价是音频和动作质量略降。第一次跑通就开它。

### 6.3 排队生成

点「Queue Prompt」。控制台会显示进度条和每一步的耗时。

**第一次生成会比后面慢**，因为模型要从磁盘加载进内存和显存。看到进度条开始走就说明没问题。

5 秒片段在 4090 + turbo 下，参考耗时 **5–10 分钟**。如果超过 20 分钟，按下面的顺序查：

1. 内存是不是只有 16GB（`free -g`）→ 这是最常见的原因
2. turbo_mode 有没有真的打开
3. `nvidia-smi` 看显存占用，如果只有几 GB，说明 offload 在疯狂搬数据
4. CUDA 是不是 cu128

### 6.4 可选提速：Sage Attention

生成速度能再快大约一倍，质量损失很小。想装的话：

1. 到 <https://github.com/woct0rdho/SageAttention/releases> 下载与你 PyTorch / CUDA / Python 版本匹配的 wheel，`pip install <wheel>`。
2. 装 KJNodes 自定义节点（ComfyUI Manager 里搜 `KJNodes`）。
3. 在工作流里加一个 `Patch Sage Attention KJ` 节点，串在 `UNETLoader` 和 `BasicGuider` 之间，`sage_attention` 设 `auto`。

控制台会刷 `Input tensors must be in dtype of torch.float16 or torch.bfloat16` 之类的提示，这是正常的——H3 部分层是别的精度，会回退到标准注意力，不影响结果。

---

## 第 7 步 · 把结果拿回本地

生成完的视频在 ComfyUI 的 `output/` 目录下，是一个 mp4（画面 + 立体声在同一条轨道里，不用另外合成音频）。

一个 5 秒 768p 的 mp4 大约 5–15MB，**最简单的办法是 JupyterLab**：左侧文件树进到 `output/`，右键文件 → Download。

文件大的话用公网网盘（AutoDL 快捷工具里的 **AutoPanel**），授权阿里云盘或夸克网盘后，实例 → 网盘 → 本地两跳。或者用 FileZilla / `scp`。

把下载下来的片段放进本地的 `records/` 或你自己的工作目录。

---

## 第 8 步 · 收尾（这一步直接决定你花多少钱）

1. **关机。** 控制台点关机，计费才停。关浏览器不算。
2. **记账。** 在 `records/` 里新建一行，写下：日期、卡型、开机时长、生成条数、花费。这张表是判断「自建到底值不值」的唯一依据。
3. **决定数据盘。** 如果短期内不继续做，考虑「缩容数据盘」或「释放实例」。付费扩容部分每天都会计费，不管开不开机。

> 数据盘里的 42GB 模型关机后不会丢，下次开机可以直接用。**但保存镜像不会备份数据盘**，所以别指望靠镜像保住模型。

---

## 常见问题

**生成的视频没有声音**
检查 `models/vae/minimax_h3_audio_vae_fp32.safetensors` 是否下好了，以及提示词里有没有描述音频内容（对白、音效、音乐）。H3 是画面和声音同一次前向生成的，音频描述为空就真的没声音。

**提示缺少模型 / 文件名不匹配**
模板节点里写死的文件名必须完全一致。对照第 4.2 节的表格逐个核对，注意 `fl2va` 和 `ref2va` 是两套权重，别放错。

**显存不够（OOM）**
按这个顺序试：先把时长从 5 秒缩到最短 → 再降 Megapixels → 装 Kijai 的 KJNodes，用 `MiniMax H3 Low VRAM Attention` 和 `MiniMax H3 Chunk FeedForward` 两个节点降峰值显存。降量化是最后手段，那会掉画质。

**能出 2K 吗？**
不能。本地 H3-Base 在任何显卡上都只输出短边 768px。2K 依赖未开源的 H3-Regenerate-2K，只能走 MiniMax 官方 API。

**商用**
MiniMax H3 采用社区许可协议，本地生成结果用于商用需要购买商用许可（Comfy 是官方转售渠道）。自己看、内部测试不受影响，对外交付前先确认。
