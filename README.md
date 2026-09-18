# Mimir

[![Build iOS IPA](https://github.com/zxl1828/mimir-ios/actions/workflows/build-ipa.yml/badge.svg)](https://github.com/zxl1828/mimir-ios/actions/workflows/build-ipa.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/Platform-iOS%2026%2B-lightgrey)
![Swift](https://img.shields.io/badge/Swift-6-orange)

本地优先的私人 AI 客户端，SwiftUI + MVVM，最低支持 iOS 26，
界面完全自定义并使用液态玻璃（Liquid Glass）原生材质。

> 非官方项目，与 DeepSeek 官方无隶属或背书关系；「DeepSeek」为相应权利人的商标。

## 主要能力

### 对话
- 流式输出（逐字渲染），支持随时停止、重新生成、引用、编辑重发、删除
- Markdown 渲染：标题、列表、引用、代码块（可复制）、表格、`$$LaTeX$$` 公式、Mermaid 图表
- 多模型接入：DeepSeek 原生 / 任何 OpenAI 兼容网关 / Anthropic 协议，
  根据 API Key 前缀自动识别格式与端点
- 长对话滚动摘要，超出上下文窗口时自动压缩而不是粗暴截断
- Token 用量统计（消息级与本机累计）

### 交互
- **Agent Dock**：输入框上方的智能体胶囊，切换当前对话的智能体上下文
- **技能系统**：输入 `/` 即时唤起技能选择浮层，支持键盘 ↑↓ / 回车 / Esc、
  关键词与端侧语义双层意图推荐、JSON 导入导出
- **思考模式滑块**：快速 / 思考 / 专家 / Ultra 四档，冷 → 暖渐变轨道，
  Ultra 档带光晕扩散、呼吸脉冲、流光、粒子与标签扫光
- 侧边栏抽屉：会话记录（搜索 / 重命名 / 置顶 / 复制 / 删除）、智能体、技能、
  设置、记忆浏览器、MCP 服务器、数据流向

### 语音（全部端侧）
- 能量 VAD 自动断句（可调阈值），静音 1.5 秒自动提交
- 端侧语音识别（系统 Speech 框架，强制离线）
- 内置 Kokoro-82M CoreML 语音模型随 App 打包，中文朗读自动切换到系统语音
- 流式逐句合成播放，支持 Barge-in 打断
- `AVAudioSession` 同时录制与播放，处理中断与路由切换

### 记忆与隐私
- 端侧向量记忆：NLEmbedding + Accelerate 余弦相似度，索引常驻内存
- 记忆浏览器：查看、搜索、编辑、删除、时间线、来源溯源、命中标签跳转、JSON 导入导出
- 对话结束后后台自动提炼长期事实
- 数据流向面板：逐项说明哪些数据只在本机、哪些会发送到云端
- 记忆条目可标记「仅本地使用」，标记后不会随对话发送

### 扩展
- **MCP**：官方 `modelcontextprotocol/swift-sdk`，支持 HTTP/SSE 多服务器并行连接、
  工具目录、调用实时进度、按服务器授权「数据可上传」
- **系统工具**：OCR 文字识别、条码/二维码识别、Spotlight 检索，全部本机执行
- **多模态**：相册、拍照、文档扫描（VisionKit），本地先做 OCR/条码预处理再提问
- **App Intents**：总结、翻译、润色、解释代码、写邮件，已暴露给 Siri 与 Shortcuts
- **Live Activity**：锁屏与灵动岛显示生成状态、预览与 token 数
- **后台任务**：BGTaskScheduler 注册的后台刷新与每日简报

## 技术栈

| 项目 | 说明 |
|---|---|
| 语言 | Swift 6（严格并发检查） |
| UI | SwiftUI，Liquid Glass（`glassEffect` / `GlassEffectContainer`） |
| 持久化 | SwiftData |
| 凭据 | Keychain（API Key 与 MCP Token 均不入 UserDefaults） |
| 网络 | 自建统一网络层（SSE 流式解析，OpenAI 兼容 + Anthropic 双协议） |
| 依赖 | `Jud/kokoro-coreml`（内置语音模型）、`modelcontextprotocol/swift-sdk`（MCP） |
| 工程生成 | XcodeGen（`Project.yml`） |

## 构建

推送到 `main` 分支即触发 GitHub Actions 构建，产出**未签名** IPA：

```
https://github.com/zxl1828/mimir-ios/actions
```

构建流程：选择 Xcode 26 → 下载语音模型（约 99MB，打包进 App）→
`xcodegen generate` → `xcodebuild`（关闭代码签名）→ 打包 `Payload` 为 IPA。

本地构建（需要 macOS + Xcode 26）：

```bash
bash scripts/fetch-voice-models.sh
xcodegen generate
xcodebuild -project Mimir.xcodeproj -scheme Mimir \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

## 安装

产物是未签名 IPA，需要用自签工具安装（AltStore、Sideloadly、TrollStore 等），
或使用自己的开发者证书重签后安装。

## 数据边界

**只在本机完成**：语音识别与合成、向量嵌入与检索、记忆存储与导出、
意图识别与技能推荐、OCR / 条码 / Spotlight、端侧回复建议。

**会发送到云端**：对话文本、你附加的图片、非「仅本地」的记忆片段、
以及你为该服务器显式授权「数据可上传」后的 MCP 工具返回值。

## 已知限制

- MCP 的 `ui://` 交互式表单（MCP Apps）尚未渲染为原生表单
- MCP OAuth 授权流程尚未接入，目前使用手动填写访问令牌
- 「任务模式」（先在对话中列任务清单再逐步执行）尚未实现
- 自定义模型目录的数据结构已就绪，但还没有对应的管理界面
- Mermaid 与 KaTeX 渲染依赖 WebView 加载 CDN，离线时回退显示源码
- stdio 传输的 MCP 服务器在 iOS 上不可用（系统不允许派生子进程），仅支持 HTTP/SSE

## 开源许可

本项目以 [MIT 许可证](LICENSE) 开源：可自由使用、修改、分发，包括商业用途，
只需保留版权与许可声明。

随 App 打包的第三方组件与模型见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
（MCP Swift SDK、Kokoro-82M CoreML 语音模型，均为 Apache-2.0 兼容许可）。

参与贡献请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)；安全问题请按
[SECURITY.md](SECURITY.md) 私下报告。

## English

An unofficial, local-first AI client for iOS 26 - works with DeepSeek, any OpenAI-compatible gateway and Anthropic endpoints - built with SwiftUI and
Liquid Glass: streaming chat, on-device voice (VAD + speech recognition +
bundled Kokoro-82M CoreML TTS), local vector memory, skills, MCP tools,
App Intents, and a fully custom UI.

Build with Xcode 26 + [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
bash scripts/fetch-voice-models.sh
xcodegen generate
xcodebuild -project Mimir.xcodeproj -scheme Mimir \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

CI produces an unsigned IPA on every push to `main`. Licensed under MIT —
see [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).
