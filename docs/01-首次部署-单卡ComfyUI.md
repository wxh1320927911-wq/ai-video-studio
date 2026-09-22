# 01 · 首次部署：单卡 ComfyUI 跑通第一个片段

> 目标：从零开始，在 AutoDL 上跑出**一个 5 秒、带立体声、768p 的 mp4**，并下载回本地。
> 预计耗时：首次约 1.5–2.5 小时（其中 1–2 小时是下载模型和装环境）。
> 预计花费：约 ¥4–6（4090 按量计费）+ 数据盘扩容费。
> 全程只需要一台电脑 + 一个浏览器，不需要本地显卡。

**本机需要装的：一个浏览器。别的没了。**

不用装 ComfyUI、不用装 Python、不用装 CUDA、不需要显卡。所有计算都发生在租来的那台实例上，本机只负责「打开一个网址、点几下、把生成的 mp4 下载回来」。

（ComfyUI 本身是跨平台软件，装本机也完全可以跑——只是本机没有 24GB 显存的卡，所以这条路选了服务器。）

这一份是「首次部署」，做一次就够。以后每次创作看 `02-每次创作流程.md`。

> **2026-09-22 核对记录（本文写完之后做的）**
> 本文最初是照官方文档写的，**从未真正执行过**。09-22 逐条对官方原件核对了一遍，改了四处：
> ① 扩散模型量化版本改为**按 CUDA 版本自动选**（官方明确 int8 需要 cu130），原写法会让人在 cu128 上误用 int8、慢 3 倍还不报错；
> ② 下载模型改为**走 hf-mirror 镜像站 + 关 Xet**，原写法让人开学术加速，而代理白名单里没有镜像站，实测会变慢甚至失败；
> ③ 补上 **10 个风格 embeddings**（合计 10.7 MB，原文档完全没提）；
> ④ 参数表按**实际工作流 JSON** 逐个核对，删掉了并不存在的 `steps` 控件。
> 核对来源：`Comfy-Org/MiniMax-H3` 仓库 README 与文件树、`Comfy-Org/workflow_templates` 的模板索引与三份工作流 JSON（原件已存进 `workflows/`）。
> **仍未验证的是「真的能跑出片子」**——那要等实例开机。核对过文档不等于跑通，这条别混。

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

三条路，我们**选第一条**：

| | 做法 | 谁维护 | 适合 |
| --- | --- | --- | --- |
| **① 基础镜像 + 自己装（本项目选这个）** | 选「基础镜像」→ PyTorch，然后自己 `git clone` ComfyUI | 官方 | 要可复现、要排错清楚 |
| ② 社区镜像 | 选「社区镜像」搜 `ComfyUI` | 第三方个人 | 想省事、不在乎环境来源 |
| ③ 应用广场（autodl.art） | 在应用市场一键部署一个装好的应用 | 第三方个人 | 想跳过所有配置，直接出图 |

**为什么选 ①：** 这个项目要验证的是「官方工作流 + 官方权重能不能跑通」。用别人打包好的镜像会把「环境问题」和「我们的用法问题」绑在一起——跑不通时不知道是谁的错。而且首次部署的大头（装环境 + 下模型）是**一次性成本**，数据盘留着，下次开机 10 秒就能用。

另外两条路值得了解，见下面的补充说明。

无论选哪条，注意两点：

1. **ComfyUI 版本必须 ≥ 0.30.0**，低版本没有 MiniMax H3 的原生节点。这个数字来自官方模板索引里的 `minComfyUIVersion` 字段（T2V / I2V / R2V 三个模板都是 0.30.0），不是我推测的。
2. **CUDA 版本决定下哪个量化版本，必须先确认。** 官方模型仓库 README 原文：

   > For diffusion models prefer `int8_convrot` if you are able to use pytorch with **cu130**. `fp8_scaled` should only be used if you cannot use `int8_convrot`.

   即 **int8 量化需要 cu130**。社区另有报告称 cu128 下 int8 推理内核会**静默失效、慢约 3 倍**——不报错，只是慢，最容易被误判成「H3 就是慢」。

   两个文件体积几乎一样（20.97 GB vs 20.96 GB），换掉零成本。开机后先跑一句确认：

   ```bash
   python -c "import torch;print(torch.version.cuda)"
   ```

   输出 `13.x` → 用 `int8_convrot`；否则 → 用 `fp8_scaled`。第 4 步的下载脚本会**自动判断**，不用手选。

#### 补充：AutoDL 应用广场（autodl.art）是什么

截图里那些「MINIMAX-H3提速500%高画质」「ComfyUI云绘通用版」之类的卡片，是 **AutoDL 应用广场**上的社区应用，和「容器实例」是并列的两种产品形态。

**已核实的事实：**

- **归属**：`autodl.art` 与 `autodl.com` **同属视拓云研发运营，两者账户通用**（出处：官方文档站 codewithgpu.com/docs）。
- **计费**：开机计费、关机停，精确到秒，最低 0.01 元。**系统盘单独计费**——基础容量 30GB 收 **0.10 元/日**，扩容另计，且**无论实例是否开机，每天照收**（出处：autodl.art/docs/app）。
- **数据保留**：按量计费应用实例**连续关机 60 天**才自动释放（容器实例是 15 天）。宽限期更长，反过来说**更容易忘了释放**。
- **内容**：截图里「全部(230)」，H3 相关的至少有 6–7 个。其中做得最全的是 zealman 那套——ComfyUI v0.37、Python 3.12、PyTorch 2.12.1 + **cu130 / CUDA 13.0**，自带 30 多个 H3 工作流（编号 U00–U31，涵盖文生视频、图生视频、多图参考、换装、数字人带货、二采放大、导演台等）。

**为什么第一阶段不用它：**

1. 它自带的工作流是**社区改过的**，不是 `workflows/` 里那三份官方原件。节点版本、模型文件名、参数名都可能对不上——我们核对过的那套东西在这里不成立。
2. 镜像更新很勤（zealman 从 v9.36 到 v9.40），环境会漂移，**不可复现**。
3. 我们要验证的是官方链路。混进一个黑盒环境，跑通了也不知道该归功于谁。

**但第二阶段值得认真看**，理由也是实的：

- 官方模板库里 H3 只有 **8 个**工作流，社区镜像里有 **30 多个**，覆盖换装、数字人、宫格图反推、动作迁移这些官方没有的场景。
- 那些「二采放大 / latent 放大 / sigma 强化」的工作流解决的是**画质**问题——在 768p 这个硬天花板下，这是真实需求。
- 正确用法：**先用官方路线跑通拿到基线**（耗时、画质、花费），**再**用社区镜像对照。有基线才知道它到底提升了多少。

**关于「提速 500% / 5 倍速」这类宣传：**

我们的基线是官方 20 步；已经开着的 turbo 8 步实测提速 **1.44 倍**。社区的加速手段是 lightX2V + 二采 + latent 放大，有些确实有效（4 步 LoRA 我们自己就验证过）。但**「500%」通常是对比「20 步无加速」算出来的，不是对比我们已经在用的 8 步**。别指望在现有基线上再快 5 倍。

另外注意「提速 500% **高画质**」这种组合名——速度和质量通常是交换关系，两个都要往往只在某个特定设置下成立。

**没能核实的三条（要用之前先在应用页面确认）：**

1. **模型是否预置在镜像里。** 有第三方聚合站称「模型直接读平台库，不用下载」，但那是 AI 生成的聚合页，不能当依据；应用页面自己的说明里也没写清。注意系统盘基础容量只有 30GB，装不下 44GB 的 H3 权重，所以「模型全预置」这件事值得怀疑。
2. **应用实例能不能 SSH 进去**、能不能跑我们自己的脚本。
3. **应用实例的 GPU 单价**（官方文档只写「以网页显示为准」）。

### 2.5 数据盘

默认 50GB。**建议扩容到 100GB。**

模型文件合计约 44.4GB（见第 4 步），加上 ComfyUI、依赖和生成结果，50GB 会非常紧张。

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
| 数据盘可用空间 | ≥55GB | 扩容数据盘 |

顺带把 Python 依赖拉齐：

```bash
pip install -U "huggingface_hub[cli]"
```

---

## 第 4 步 · 下载模型（约 44 GB）

H3 的模型在 Hugging Face 的 `Comfy-Org/MiniMax-H3` 仓库，共 33 个文件，我们只要其中 6–7 个。

**不要开学术加速**，改成设两个环境变量走镜像站——理由见 4.3：

```bash
export HF_ENDPOINT=https://hf-mirror.com
export HF_HUB_DISABLE_XET=1
```

然后跑 `scripts/download-models.sh`。

### 4.1 确定 ComfyUI 的路径

不同镜像里 ComfyUI 位置不一样，先找一下：

```bash
ls -d /root/autodl-tmp/ComfyUI /root/ComfyUI /root/comfyui 2>/dev/null
```

假设结果是 `/root/autodl-tmp/ComfyUI`，把它记下来，后面都用这个路径（脚本里叫 `COMFY_DIR`）。

> **如果 ComfyUI 装在系统盘（`/root/ComfyUI`）**：系统盘只有 30GB，装不下 44GB 模型。把 models 目录软链到数据盘：
> ```bash
> mkdir -p /root/autodl-tmp/ComfyUI-models
> rm -rf /root/ComfyUI/models && ln -s /root/autodl-tmp/ComfyUI-models /root/ComfyUI/models
> ```
> 之后所有模型都往 `/root/autodl-tmp/ComfyUI-models` 里放。

### 4.2 要下的文件（第一阶段最小集合）

尺寸按官方仓库实测（十进制 GB），**已逐个核对文件确实存在**。

| 用途 | 文件 | 大小 |
| --- | --- | --- |
| 扩散模型（文生 / 首帧尾帧） | `diffusion_models/minimax_h3_fl2va_pruned_int8_convrot.safetensors`<br>或 `…_pruned_fp8_scaled.safetensors`（**按 CUDA 版本二选一**，见 2.4） | 20.97 / 20.96 GB |
| 文本编码器 | `text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors` | 15.69 GB |
| 视频 VAE | `vae/minimax_h3_video_vae_fp16.safetensors` | 5.21 GB |
| 音频 VAE | `vae/minimax_h3_audio_vae_fp32.safetensors` | 0.61 GB |
| Turbo LoRA（8 步，提速用） | `loras/minimax_h3_fl2v_turbo_8step_v1.0_comfyui_bf16.safetensors` | 1.96 GB |
| 风格 embeddings（10 个，**白给**） | `embeddings/minimaxh3_*.safetensors` | 0.01 GB |
| **合计** | | **约 44.4 GB** |

**可选增补：**

- **4 步 Turbo LoRA**：`loras/minimax_h3_fl2v_turbo_4step_v1.0_768p_comfyui_bf16.safetensors`（1.96 GB）。比 8 步版更快，768p 专用。想试就下，不想试跳过。
- **省空间**：视频 VAE 可用 int8 版（`minimax_h3_video_vae_int8_convrot.safetensors`，2.81 GB）替掉 fp16 版，省 2.4 GB。

> **关于那 10 个 embeddings**：合计只有 **10.7 MB**，是 10 个风格/运镜预设（子弹时间、暗黑魔法、四季变换等），在提示词里写 `embedding:minimaxh3_bullet_time` 就能调用。体积可以忽略，没有不下的理由。
> 需要 ComfyUI 支持 PR #15697，比 H3 本体（#15224）更晚，版本太老会不生效——但不生效也只是被当成普通文本忽略，不会报错。

**第一阶段先不要下的：**

- `ref2va` 系列（参考生视频），以后再下，避免数据盘翻倍。
- `bf16` 原版（66 GB）和 `int8` 未剪枝版（34 GB），消费级卡跑不动，别浪费下载时间。
- `model_patches/`（ControlNet Union），第一阶段用不上。


### 4.3 下载命令

**用仓库里的脚本，不要手敲命令**——它会自动判断该下 int8 还是 fp8、并把 10 个 embeddings 一起带上：

```bash
cd /root/planner          # 或者你把 scripts/ 传上来的目录
COMFY_DIR=/root/autodl-tmp/ComfyUI bash scripts/download-models.sh
```

可选开关：`EXTRA_LORA=1` 加下 4 步 LoRA；`DIFF_MODEL=int8|fp8` 强制指定量化版本。

#### 两个必须先设的环境变量（都是踩过的坑）

```bash
export HF_ENDPOINT=https://hf-mirror.com   # 走镜像站，国内直连 huggingface.co 会超时
export HF_HUB_DISABLE_XET=1                # 关掉 Xet 传输
```

- **`HF_HUB_DISABLE_XET=1` 是必须的。** `hf download` 新版默认走 Xet 协议，会**绕开镜像站直连 `us.aws.cdn.hf.co`**，国内必报 `CAS Client Error`。关掉后才会老老实实走 `HF_ENDPOINT`。
- **不要为了下载模型去 `source /etc/network_turbo`。** AutoDL 的学术加速代理白名单里**没有 hf-mirror.com**，开了反而会把镜像站流量也塞进代理，更慢甚至失败。实测直连镜像站有 **16 MB/s**，41 GB 约 40 分钟。
  - 学术加速只在 `git clone` GitHub 仓库时开。

`hf download` 支持断点续传，网络断了重跑同一条命令即可，不会从头再来。

**下载过程中随时另开一个终端看进度：**

```bash
du -sh /root/autodl-tmp/h3-dl
```

### 4.4 关于无卡模式（可选省钱手段）

下载 44GB 不需要 GPU。AutoDL 提供**无卡模式开机**：配置为 0.5 核 / 2GB 内存 / 无 GPU，统一 **¥0.1/小时**。

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

两个参数都不能省：

- **`--listen 0.0.0.0`** —— ComfyUI 的默认值是 `127.0.0.1`（只监听本机回环），不加这个参数外面永远连不上。这是最常见的「服务起来了但打不开」的原因。
- **`--port 6006`** —— 默认是 8188，而 AutoDL 只映射 6006/6008。

`nohup … &` 是让进程脱离 SSH 会话继续活着；`> … 2>&1` 把日志写进文件，SSH 断了也能回头看。

**为什么是 6006 端口？** AutoDL 的实例没有独立公网 IP，但平台为每个实例的 **6006 和 6008 端口**默认做了公网映射，不需要企业认证。其它端口要开放得做企业认证，所以 ComfyUI 就放 6006。

然后回到 AutoDL 控制台，在实例的快捷工具里点「**自定义服务**」，复制那个地址（形如 `https://u39-b3fb-39a640fd.nmb2.seetacloud.com:8443`），在本地浏览器打开，就是 ComfyUI 界面。

> ⚠️ **这个地址是公网可达的，而 ComfyUI 没有登录功能。**
> 查过主仓库的 `comfy/cli_args.py`，认证相关的参数只有 `--tls-keyfile` / `--tls-certfile`（只加密，不认证）和 `--enable-cors-header`，**没有 `--auth` / `--password` / `--token` 这类选项**。
> 意思是：**拿到这个地址的人就能用你的显卡、看你生成的东西、往你的数据盘写文件。**
> 地址虽然不好猜（带一串随机字符），但这不构成安全边界。
> 三条应对，按推荐顺序：
> 1. **用 SSH 隧道代替（见下），完全不暴露公网** —— 代价是每次要开一个终端
> 2. **用完立刻关机** —— 实例关机后端口就没有映射了，这是最省事的办法
> 3. 别在这个实例上放任何敏感文件

#### 备选：SSH 隧道（不暴露公网）

```bash
ssh -CNg -L 6006:127.0.0.1:6006 -p <SSH端口> root@<SSH地址>
```

然后本地浏览器开 `http://127.0.0.1:6006`。

- **没有任何输出是正常的**，不要以为卡住了。`-C` 压缩、`-N` 不执行远端命令、`-g` 允许其它主机连、`-L` 本地转发。
- 这个终端**必须一直开着**，关掉隧道就断。
- 好处是 ComfyUI 只需要监听 `127.0.0.1`，公网上完全看不到。

**排错：**

```bash
tail -n 50 /root/autodl-tmp/comfyui.log     # 看启动日志
ss -tlnp | grep 6006                        # 确认端口在监听
```

如果启动报缺依赖，一般是 `pip install -r requirements.txt` 没跑完，补上再重启。

---

## 第 6 步 · 跑出第一个片段

### 6.1 加载工作流

**推荐：直接把仓库里的 JSON 拖到 ComfyUI 画布上。** 文件在 `workflows/`：

| 文件 | 官方标题 | 用途 |
| --- | --- | --- |
| `workflows/video_minimax_h3_t2v.json` | MiniMax H3: Text to Video | **第一次跑通就用这个**，不需要任何输入文件 |
| `workflows/video_minimax_h3_i2v.json` | MiniMax H3: Image to Video | 给一张首帧图 |
| `workflows/video_minimax_h3_r2v.json` | MiniMax H3: Reference to Video | 参考图/视频/音频（要 ref2va 权重，第一阶段没下） |

这三个文件是从官方模板库原样下载的，加载效果和界面里「浏览模板」找出来的一样，但不用翻菜单，而且配置可复现。

**也可以走界面**：菜单「工作流」→「浏览模板」→ 视频 分类 → 找 `MiniMax H3: Text to Video`。

> ⚠️ **T2V / I2V 用了 Subgraph（子图）功能**，加载后看到的是一个打包好的节点，双击可以展开。子图是较新的界面特性，**加载报错或节点显示空白 = ComfyUI 版本太老**，先升级再说。

加载后如果弹出「缺少模型」的提示，**不用点自动下载**——我们已经手动下好了。节点里写死的文件名和第 4.2 节那张表**逐个核对过，完全一致**。

### 6.2 参数设置（第一次先求快）

参数都在那个子图节点上（双击展开能看到内部，但不用展开）。**参数名以这里为准**——网上教程里的名字和实际工作流对不上：

| 位置 | 参数名 | 第一次建议值 |
| --- | --- | --- |
| 顶层 `Resolution Selector` | Aspect ratio | `16:9 (Widescreen)`（默认值） |
| 顶层 `Resolution Selector` | Megapixels | **`0.4`**（默认值，输出 864×480；0.98 才是 1344×768 满画布） |
| 顶层 `Resolution Selector` | Multiple | `32`（不要改，这是 H3 的分辨率网格） |
| 子图节点 | `prompt` | 粘 `prompts/第一条测试提示词.md` 的内容 |
| 子图节点 | `duration` | **`5`**（**单位是秒**，不是帧数。内部会自动对齐到 17k+5 帧网格） |
| 子图节点 | **`turbo_mode`** | **改成 `true`**（默认 `false`） |
| 子图节点 | `turbo_steps` | `8`（默认值，只在 turbo_mode 打开时生效） |
| 子图节点 | `turbo_model_strength` | `1`（默认值） |
| 子图节点 | `noise_seed` | 不用改。默认是固定种子，方便复现 |

**没有 `steps` 这个控件，别找。** 步数由 `turbo_mode` 内部切换：关 → 内部固定 20 步；开 → 用 `turbo_steps`（8 步）。官方工作流就是这么设计的。

turbo 模式用 8 步代替 20 步，速度大约快一倍多，代价是音频和动作质量略降。第一次跑通就开它。

### 6.3 可选：用风格 embeddings

那 10 个 10.7 MB 的 embeddings 是**写进提示词**里用的，不是加节点。在 `prompt` 正文里写：

```
embedding:minimaxh3_bullet_time
```

可用的名字：`art_is_explosion` / `blooming_flowers` / `bullet_time` / `dark_magic` / `fire_breath` / `four_seasons` / `kiss_camera` / `spiral_ascent` / `storm_magic` / `truman_show`。

第一次跑通**先别加**，多一个变量就多一个出错源。跑通之后再加。


### 6.4 排队生成

点「Queue Prompt」。控制台会显示进度条和每一步的耗时。

**第一次生成会比后面慢**，因为模型要从磁盘加载进内存和显存。看到进度条开始走就说明没问题。

5 秒片段在 4090 + turbo 下，参考耗时 **5–10 分钟**。如果超过 20 分钟，按下面的顺序查：

1. 内存是不是只有 16GB（`free -g`）→ 这是最常见的原因
2. `turbo_mode` 有没有真的打开（子图节点上，默认是 `false`）
3. **CUDA 是不是 cu128 却下了 `int8_convrot` 权重** → int8 内核在 cu128 下会静默失效、慢约 3 倍，不报错。见 2.4，换成 `fp8_scaled` 版本
4. `nvidia-smi` 看显存占用，如果只有几 GB，说明 offload 在疯狂搬数据

### 6.5 可选提速：Sage Attention

生成速度能再快大约一倍，质量损失很小。想装的话：

1. 到 <https://github.com/woct0rdho/SageAttention/releases> 下载与你 PyTorch / CUDA / Python 版本匹配的 wheel，`pip install <wheel>`。
2. 装 KJNodes 自定义节点（ComfyUI Manager 里搜 `KJNodes`）。
3. 在工作流里加一个 `Patch Sage Attention KJ` 节点，串在 `UNETLoader` 和 `BasicGuider` 之间，`sage_attention` 设 `auto`。

控制台会刷 `Input tensors must be in dtype of torch.float16 or torch.bfloat16` 之类的提示，这是正常的——H3 部分层是别的精度，会回退到标准注意力，不影响结果。

---

## 第 7 步 · 把结果拿回本地

生成完的视频在 ComfyUI 的 `output/` 目录下（T2V 默认存到 `output/video/MiniMax_H3/`），是一个 mp4（画面 + 立体声在同一条轨道里，不用另外合成音频）。

一个 5 秒 768p 的 mp4 大约 5–15MB，**最简单的办法是 JupyterLab**：左侧文件树进到 `output/`，右键文件 → Download。

> ⚠️ **JupyterLab 不一定打得开。** 上一轮租的规划机实例就是 `jupyter_port=0`、8443 端口 `ERR_CONNECTION_CLOSED`，完全用不了。别把它当唯一出路，先点一下试试，不行立刻换下面的办法。

文件大的话用公网网盘（AutoDL 快捷工具里的 **AutoPanel**），授权阿里云盘或夸克网盘后，实例 → 网盘 → 本地两跳。或者用 FileZilla / `scp`：

```bash
scp -P <端口> root@<SSH地址>:/root/autodl-tmp/ComfyUI/output/video/MiniMax_H3/*.mp4 ./
```

把下载下来的片段放进本地的 `records/` 或你自己的工作目录。

---

## 第 8 步 · 收尾（这一步直接决定你花多少钱）

1. **关机。** 控制台点关机，计费才停。关浏览器不算。
2. **记账。** 在 `records/` 里新建一行，写下：日期、卡型、开机时长、生成条数、花费。这张表是判断「自建到底值不值」的唯一依据。
3. **决定数据盘。** 如果短期内不继续做，考虑「缩容数据盘」或「释放实例」。付费扩容部分每天都会计费，不管开不开机。

> 数据盘里的 44GB 模型关机后不会丢，下次开机可以直接用。**但保存镜像不会备份数据盘**，所以别指望靠镜像保住模型。

---

## 附 · 还有哪些 H3 工作流（现在不用，知道有就行）

官方模板库里的 H3 系工作流共 8 个。上面只用了 T2V，其余留作以后按需取。最低版本号取自官方模板索引的 `minComfyUIVersion` 字段。

| 模板名 | 标题 | 最低 ComfyUI | 用途 |
| --- | --- | --- | --- |
| `video_minimax_h3_t2v` | Text to Video | 0.30.0 | **本教程用这个** |
| `video_minimax_h3_i2v` | Image to Video | 0.30.0 | 给一张首帧图 |
| `video_minimax_h3_r2v` | Reference to Video | 0.30.0 | 参考图/视频/音频（需 ref2va 权重） |
| `video_minimax_h3_i2v_continuation` | Image to Video | 0.30.0 | 首帧 + 空提示词续写 |
| `video_minimax_h3_multiframe_reference` | Multiframe Reference | 0.34.0 | **最多 4 张参考帧锚定在时间轴任意位置**，做续接、卡叙事节点 |
| `video_minimax_h3_fun_controlnet_union` | Fun ControlNet Union | 0.35.0 | 用参考视频做姿态控制（需下 `model_patches/`） |
| `video_fastvideo_fasth3_t2v` / `_i2v` | FastVideo FastH3 | **0.36.0** | 独立的 8 步蒸馏检查点，**不是 LoRA**，专为速度另做的权重，2026-09-15 发布 |

两个值得记的点：

- **FastH3 是另一套权重，不在 `Comfy-Org/MiniMax-H3` 仓库里。** 想要得去 FastVideo 那边找。它比「标准模型 + turbo LoRA」更彻底，但换权重意味着重新下载几十 GB，第一阶段不做。
- **`multiframe_reference` 是这堆里对「做片子」最有用的一个**——能把 4 张关键帧钉在时间轴指定位置，等于把分镜控制权拿回来一部分。等第一阶段跑通、确定要继续做长片，这个优先试。

本地已有 T2V / I2V / R2V 三份原件（`workflows/`），其余需要时从模板库取，取法见 `workflows/README.md`。

---

## 常见问题

**生成的视频没有声音**
检查 `models/vae/minimax_h3_audio_vae_fp32.safetensors` 是否下好了，以及提示词里有没有描述音频内容（对白、音效、音乐）。H3 是画面和声音同一次前向生成的，音频描述为空就真的没声音。

**提示缺少模型 / 文件名不匹配**
节点里写死的文件名必须完全一致。对照第 4.2 节的表格逐个核对，注意 `fl2va` 和 `ref2va` 是两套权重，别放错。

**工作流加载后节点是空白 / 报错说看不懂节点类型**
T2V 和 I2V 用了 Subgraph 功能，ComfyUI 版本太老会加载不出来。升级 ComfyUI 到 0.30.0 以上（embeddings 还要更晚的版本才支持）。

**生成慢得离谱（比参考值慢 3 倍）**
最常见的原因是 **cu128 + `int8_convrot` 权重**。int8 推理内核在 cu128 下会静默失效——不报错，只是慢。见 2.4，改成 `fp8_scaled` 版本。次常见原因是内存不足 32GB。

**显存不够（OOM）**
按这个顺序试：先把时长从 5 秒缩到最短 → 再降 Megapixels → 装 Kijai 的 KJNodes，用 `MiniMax H3 Low VRAM Attention` 和 `MiniMax H3 Chunk FeedForward` 两个节点降峰值显存。降量化是最后手段，那会掉画质。

**能出 2K 吗？**
不能。本地 H3-Base 在任何显卡上都只输出短边 768px。2K 依赖未开源的 H3-Regenerate-2K，只能走 MiniMax 官方 API。

**商用**
MiniMax H3 采用社区许可协议，本地生成结果用于商用需要购买商用许可（Comfy 是官方转售渠道）。自己看、内部测试不受影响，对外交付前先确认。
