# 第三方组件与模型声明

本仓库自身代码以 [MIT + Commons Clause](LICENSE) 发布（源码公开，禁止倒卖）。构建产物（未签名 IPA）中还会包含以下
第三方内容，它们各自遵循原始许可，此处保留其声明。

## 随 App 分发

| 组件 | 用途 | 许可证 | 来源 |
|---|---|---|---|
| MCP Swift SDK | MCP 客户端（HTTP/SSE 传输、工具调用） | MIT / Apache-2.0（项目正在由 MIT 迁移至 Apache-2.0，以仓库 LICENSE 为准） | [modelcontextprotocol/swift-sdk](https://github.com/modelcontextprotocol/swift-sdk) |

这些组件均为 Apache-2.0 兼容许可，可随 MIT 项目一并分发；分发时保留原始版权与许可声明即可
（本文件即该声明）。

> 语音合成已于 2026-09-25 改为完全使用系统框架（AVSpeechSynthesizer），
> 原先随包分发的 Kokoro-82M CoreML 模型（约 78MB）已从仓库与构建流程中移除。

## 仅构建阶段使用

| 工具 | 许可证 |
|---|---|
| [XcodeGen](https://github.com/yonaskolb/XcodeGen) | MIT |

## 系统框架

SwiftUI、SwiftData、Speech、AVFoundation、Vision、VisionKit、NaturalLanguage、
FoundationModels、AppIntents、BackgroundTasks、ActivityKit、CoreML、Accelerate
等均为 Apple 系统框架，随 iOS 系统提供，不随本仓库分发。
