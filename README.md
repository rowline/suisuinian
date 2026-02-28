# Suisuinian (碎碎念) - AI 语音笔记与转录助手

本项目是一个 macOS/iOS 配套应用套件，旨在作为一个智能的语音笔记和内容转录助手。

它主要由两部分组成：
1. **iOS 应用端 (`suisuinian`)**：一个语音录制界面，允许用户记录他们的想法和语音笔记。
2. **Node.js/Python 后端代理 (`suisuinian-brain-proxy.js` & `transcribe_and_diarize.py`)**：在 macOS 本地运行，负责处理繁重的机器学习工作负载（语音转录、声纹识别区分说话人，以及 LLM 摘要和对话）。

通过将繁重的 AI 处理卸载到 Mac 端，iOS 应用可以提供高质量的转录和 AI 交互，而不会消耗移动设备的电池或需要订阅昂贵的云端 API。

## 功能特性

- **本地机器学习**：使用 Apple Silicon（MLX 框架）进行快如闪电的、完全离线的语音转录。
- **高质量转录**：由 `mlx-community/whisper-large-v3-turbo` 大模型提供支持。
- **说话人识别（Diarization）**：使用 `pyannote.audio` 识别音频中不同的说话人（例如“说话人 1”、“说话人 2”），并以卡拉 OK 样式的文本高亮显示。
- **AI 智能摘要与对话**：内置与本地 LLM 运行器（`openclaw`）的集成，可自动提取转录内容的摘要，并允许用户针对音频内容进行对话聊天（例如：“帮我列出一个行动计划”）。

## 架构说明

1. iOS 应用录制音频并保存在本地。
2. 当用户打开某个录音时，App 会向 Mac 后端发送一个包含本地文件路径的 POST 请求（如果在模拟器中运行，或通过共享网络驱动器/同步机制，则可直接访问）。默认地址为：`http://localhost:19001/transcribe`。
3. Node.js 代理 (`suisuinian-brain-proxy.js`) 接收请求并派生执行 `transcribe_and_diarize.py` 脚本。
4. Python 脚本使用 `ffmpeg` 将音频转换为标准的 WAV 格式，使用 MLX Whisper 进行语音识别，并运行 Pyannote 来识别“谁在什么时候说了什么”。
5. 代理返回一个包含字级别和说话人级别音频片段合并后的 JSON 响应。
6. 代理还处理 `/summarize` (摘要) 和 `/chat` (对话) 接口，通过将转录文本传递给本地的 `openclaw` LLM 实例来实现。

---

## 环境配置与依赖要求

由于本项目严重依赖针对 Apple Silicon 优化的本地机器学习框架，因此**它被设计为在一台 Mac (M1/M2/M3/M4) 设备上运行**。

### 1. 系统依赖

**FFmpeg** (用于音频格式转换)：
```bash
brew install ffmpeg
```

**OpenClaw** (用于 AI 摘要和对话聊天)：
你需要安装 `openclaw`，并确保可以在 `/opt/homebrew/bin/openclaw` 路径下访问。它被用作本地的 LLM 代理助手。

### 2. Node.js 环境

代理服务器是用 Node.js 编写的。
你需要安装 Node.js（推荐 v18+ 版本）。

轻量级的代理脚本本身不需要通过 `package.json` 安装额外的 NPM 依赖，因为它只使用了内置模块 (`http`, `child_process`, `fs`, `path`)。

运行代理命令：
```bash
node suisuinian-brain-proxy.js
```

### 3. Python 环境

语音转录和说话人识别（Diarization）是在 Python 中进行的。强烈建议使用虚拟环境 (virtualenv) 或 `conda`。

需要的 Python 库：

```bash
pip install torch torchaudio pyannote.audio mlx-whisper
```

*关于 PyTorch 版本的注意事项*：脚本中包含了一个对于 PyTorch 2.6 安全检查关于 `weights_only=False` 的绕过方案，以允许 pyannote 加载其预训练的权重模型。

### 4. HuggingFace Token (关键)

**声纹识别（Speaker Diarization）需要提供 HuggingFace Token。**
Pyannote 的声纹模型在 HuggingFace 上是受限访问的。你必须：
1. 访问 [pyannote/speaker-diarization-3.1](https://huggingface.co/pyannote/speaker-diarization-3.1) 并同意用户条款。
2. 访问 [pyannote/segmentation-3.0](https://huggingface.co/pyannote/segmentation-3.0) 并同意用户条款。
3. 生成一个 HuggingFace 访问令牌 (Access Token，赋予 Read 权限)。

代理脚本会尝试从 `HF_TOKEN` 环境变量中读取该令牌。如果没有设置，它会回退到一个硬编码的默认 token（但那个 token 可能会过期或受到速率限制，所以最好提供你自己的）。

使用你自己的 token 启动代理：
```bash
export HF_TOKEN="hf_你的_token_放在这里"
node suisuinian-brain-proxy.js
```

## 运行项目

1. 启动 Mac 后端代理：
   ```bash
   node suisuinian-brain-proxy.js
   ```
   *你应该会看到终端输出，显示服务正在监听 19001 端口。*
2. 在 Xcode 中打开 `suisuinian` iOS 项目。
3. 构建并在 iOS Simulator (模拟器) 中运行应用。
   *(因为模拟器与 Mac 系统共享 localhost 网络和底层文件系统，它可以直接与 19001 端口通信并传递本地音频文件路径)。*
