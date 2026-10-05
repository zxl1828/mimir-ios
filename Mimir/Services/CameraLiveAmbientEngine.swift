import AVFoundation
import CoreImage
import SwiftUI
import Observation
import UIKit

// MARK: - 内部后台采集协调器 (Swift 6 Concurrency Safe)

/// 在专有串行后台队列运行的低功耗相机采集委托。
/// 严格限定分辨率 (CIF/360p) 与帧率 (15 fps)，并通过大半径高斯模糊彻底清除所有几何特征以杜绝隐私风险。
private final class AmbientCaptureSessionCoordinator: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {

    private let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.zxl.mimir.cameraAmbientQueue", qos: .utility)
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false, .priorityRequestLow: true])

    private var isConfigured = false
    private var isSessionRunning = false

    // 时间平滑滤波缓存 (Exponential Moving Average)
    private var smoothedTopR: Double = 0.58
    private var smoothedTopG: Double = 0.35
    private var smoothedTopB: Double = 0.95

    private var smoothedBottomR: Double = 0.48
    private var smoothedBottomG: Double = 0.28
    private var smoothedBottomB: Double = 0.92

    private var smoothedLum: Double = 0.50

    var temporalSmoothing: Double = 0.85
    var onColorsSampled: (@Sendable (Double, Double, Double, Double, Double, Double, Double) -> Void)?

    func configureSessionIfNeeded() {
        sessionQueue.async { [weak self] in
            guard let self = self, !self.isConfigured else { return }
            self.setupCapturePipeline()
        }
    }

    func start() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if !self.isConfigured {
                self.setupCapturePipeline()
            }
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
                self.isSessionRunning = true
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
                self.isSessionRunning = false
            }
        }
    }

    private func setupCapturePipeline() {
        captureSession.beginConfiguration()

        // 1. 强制设定为极低采样规格 (CIF 352x288 或 VGA 640x480)
        if captureSession.canSetSessionPreset(.cif352x288) {
            captureSession.sessionPreset = .cif352x288
        } else if captureSession.canSetSessionPreset(.vga640x480) {
            captureSession.sessionPreset = .vga640x480
        }

        // 2. 寻找后置广角摄像头
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              captureSession.canAddInput(input) else {
            captureSession.commitConfiguration()
            return
        }
        captureSession.addInput(input)

        // 3. 严格硬锁帧率为 15 fps（杜绝 30/60 fps 造成的发热与功耗）
        do {
            try device.lockForConfiguration()
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 15)
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 15)
            device.unlockForConfiguration()
        } catch {
            // 设备不支持帧率限制时继续
        }

        // 4. 视频数据输出
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)

        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

        captureSession.commitConfiguration()
        isConfigured = true
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let extent = ciImage.extent
        guard extent.width > 0, extent.height > 0 else { return }

        // 极限高斯模糊 (半径 > 100)，完全粉碎物象/轮廓/人脸，只保留宏观光照与色温
        let blurFilter = CIFilter(name: "CIGaussianBlur")
        blurFilter?.setValue(ciImage, forKey: kCIInputImageKey)
        blurFilter?.setValue(110.0, forKey: kCIInputRadiusKey)
        guard let blurred = blurFilter?.outputImage?.cropped(to: extent) else { return }

        // 提取上下半区宏观色温与亮度
        let topRect = CGRect(x: extent.minX, y: extent.midY, width: extent.width, height: extent.height / 2)
        let bottomRect = CGRect(x: extent.minX, y: extent.minY, width: extent.width, height: extent.height / 2)

        let topSample = sampleColor(from: blurred, rect: topRect)
        let bottomSample = sampleColor(from: blurred, rect: bottomRect)

        // 时间平滑指数衰减滤波 (EMA Smoothing)
        let alpha = max(0.01, min(1.0 - temporalSmoothing, 0.99))
        smoothedTopR = smoothedTopR * (1.0 - alpha) + topSample.0 * alpha
        smoothedTopG = smoothedTopG * (1.0 - alpha) + topSample.1 * alpha
        smoothedTopB = smoothedTopB * (1.0 - alpha) + topSample.2 * alpha

        smoothedBottomR = smoothedBottomR * (1.0 - alpha) + bottomSample.0 * alpha
        smoothedBottomG = smoothedBottomG * (1.0 - alpha) + bottomSample.1 * alpha
        smoothedBottomB = smoothedBottomB * (1.0 - alpha) + bottomSample.2 * alpha

        let lum = 0.2126 * ((smoothedTopR + smoothedBottomR) / 2)
            + 0.7152 * ((smoothedTopG + smoothedBottomG) / 2)
            + 0.0722 * ((smoothedTopB + smoothedBottomB) / 2)
        smoothedLum = smoothedLum * (1.0 - alpha) + lum * alpha

        onColorsSampled?(
            smoothedTopR, smoothedTopG, smoothedTopB,
            smoothedBottomR, smoothedBottomG, smoothedBottomB,
            smoothedLum
        )
    }

    private func sampleColor(from image: CIImage, rect: CGRect) -> (Double, Double, Double) {
        let avgFilter = CIFilter(name: "CIAreaAverage")
        avgFilter?.setValue(image, forKey: kCIInputImageKey)
        avgFilter?.setValue(CIVector(cgRect: rect), forKey: kCIInputExtentKey)
        guard let avgOutput = avgFilter?.outputImage else {
            return (0.55, 0.35, 0.95)
        }

        var bitmap = [UInt8](repeating: 0, count: 4)
        ciContext.render(
            avgOutput,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: CIFormat.RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        return (
            Double(bitmap[0]) / 255.0,
            Double(bitmap[1]) / 255.0,
            Double(bitmap[2]) / 255.0
        )
    }
}

// MARK: - 全局环境光动态背景引擎 (MainActor @Observable)

/// 低功耗 Camera Live Ambient Blur 动态背景引擎。
///
/// 核心规格与特性：
/// 1. 采用超低采样 (CIF 352x288 / 360p) 并严格硬锁定 15 fps 采集，杜绝发热；
/// 2. 高斯模糊半径 > 100 彻底抹平人脸、文本与物象细节，仅提取物理空间宏观色温与 Lux 明暗；
/// 3. 时间平滑指数滤波 (默认 0.85)，过滤手机移动与手抖高频噪点；
/// 4. 增益系数 (默认 0.05，0.0~1.0 调节)，极轻量融入紫雾基底，保障 WCAG AAA 文本清晰度；
/// 5. 绑定应用前后台生命周期，进入后台或切到模拟渐变模式立即休眠释放摄像头。
@MainActor
@Observable
public final class CameraLiveAmbientEngine {

    public static let shared = CameraLiveAmbientEngine()

    public private(set) var isRunning: Bool = false
    public private(set) var isAuthorized: Bool = false

    /// 提取的主环境光色彩（居中或平均）。
    public private(set) var ambientColor: Color = Color(red: 0.58, green: 0.35, blue: 0.95)
    /// 顶部环境光。
    public private(set) var ambientTopColor: Color = Color(red: 0.58, green: 0.35, blue: 0.95)
    /// 底部环境光。
    public private(set) var ambientBottomColor: Color = Color(red: 0.48, green: 0.28, blue: 0.92)
    /// 宏观环境亮度 (0.0 ~ 1.0)。
    public private(set) var ambientLuminance: Double = 0.50

    /// 环境微光增益乘数 (0.0 ~ 1.0, 默认 0.05)。
    public var gain: Double = 0.05
    /// 时间平滑滤波因子 (0.50 ~ 0.98, 默认 0.85)。
    public var temporalSmoothing: Double = 0.85 {
        didSet {
            coordinator.temporalSmoothing = temporalSmoothing
        }
    }

    private let coordinator = AmbientCaptureSessionCoordinator()
    private nonisolated(unsafe) var lifecycleObservers: [NSObjectProtocol] = []

    private init() {
        coordinator.temporalSmoothing = temporalSmoothing
        coordinator.onColorsSampled = { [weak self] topR, topG, topB, botR, botG, botB, lum in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.ambientTopColor = Color(red: topR, green: topG, blue: topB)
                self.ambientBottomColor = Color(red: botR, green: botG, blue: botB)
                self.ambientColor = Color(
                    red: (topR + botR) / 2,
                    green: (topG + botG) / 2,
                    blue: (topB + botB) / 2
                )
                self.ambientLuminance = lum
            }
        }

        setupLifecycleHooks()
    }

    deinit {
        lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - 控制接口

    /// 启动低功耗采集。
    public func start() {
        checkPermissionAndStart()
    }

    /// 停止采集并释放硬件。
    public func stop() {
        guard isRunning else { return }
        coordinator.stop()
        isRunning = false
    }

    private func checkPermissionAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
            coordinator.start()
            isRunning = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.isAuthorized = granted
                    if granted {
                        self.coordinator.start()
                        self.isRunning = true
                    }
                }
            }
        default:
            isAuthorized = false
            isRunning = false
        }
    }

    private func setupLifecycleHooks() {
        let hideObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.coordinator.stop()
            }
        }

        let showObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isRunning else { return }
                self.coordinator.start()
            }
        }

        lifecycleObservers = [hideObserver, showObserver]
    }
}
