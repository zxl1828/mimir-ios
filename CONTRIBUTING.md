# 贡献指南

欢迎提交 Issue 与 Pull Request。

## 开发环境

- macOS + Xcode 26（iOS 26 SDK）
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)：`brew install xcodegen`
- 首次构建前拉取语音模型：`bash scripts/fetch-voice-models.sh`（约 99MB；
  下载失败不阻塞构建，App 会自动回退系统语音）

```bash
xcodegen generate
open DeepSeekClient.xcodeproj
```

`.xcodeproj` 由 `Project.yml` 生成，请不要提交工程文件改动；要改构建设置请改 `Project.yml`。

## 代码约定

- Swift 6 严格并发：新增类型注意 `Sendable`，跨 actor 传递优先用值类型或显式隔离
- UI 一律 SwiftUI，视觉遵循 Liquid Glass（`glassEffect` / `GlassEffectContainer`），
  不要自绘仿制材质
- API Key、Token 只能进 Keychain，不得写入 `UserDefaults`、日志或导出文件
- 网络请求统一走 `DeepSeekClient/Services/API` 下的客户端，不在视图里直接发请求
- 端侧能力（语音、嵌入、OCR）保持零上传
- 提交前本地跑通一次无签名构建：

```bash
xcodebuild -project DeepSeekClient.xcodeproj -scheme DeepSeekClient \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

## 提交 PR

1. 从 `main` 切分支，改动尽量小而聚焦
2. 提交信息用 Conventional Commits（`feat:` / `fix:` / `docs:` / `ci:` …）
3. PR 描述里说明「改了什么、为什么、怎么验证」
4. UI 改动请附截图或录屏

## 不要提交

- 任何真实 API Key、Token、证书或描述文件
- 构建产物与 `.xcodeproj`（`outputs/`、`work/`、`Build/`、`*.ipa` 已在 `.gitignore` 中）
