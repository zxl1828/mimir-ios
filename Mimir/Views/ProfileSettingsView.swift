import PhotosUI
import SwiftUI
import UIKit

struct ProfileSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @State private var photoItem: PhotosPickerItem?
    @State private var cropSource: UIImage?
    @State private var showCropper = false
    @State private var errorMessage: String?

    var body: some View {
        @Bindable var settings = settings

        List {
            Section {
                HStack(spacing: 16) {
                    ProfileAvatarBadge(size: 76)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(settings.profileName.isEmpty ? "Mimir 用户" : settings.profileName)
                            .font(.system(size: 19, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppUI.label)
                            .lineLimit(1)
                        Text("资料仅保存在这台设备")
                            .font(AppUI.caption)
                            .foregroundStyle(AppUI.label2)
                    }
                    Spacer(minLength: 0)
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(settings.accent.color, in: Circle())
                    }
                    .buttonStyle(StaticButtonFeedbackStyle())
                    .accessibilityLabel("选择头像")
                }
                .padding(.vertical, 8)

                TextField("显示名称", text: $settings.profileName)
                    .textContentType(.nickname)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit {
                        settings.profileName = settings.profileName.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
            } header: {
                Text("个人资料")
            } footer: {
                Text("名称会即时显示在 Assistant 问候语与个人资料入口中。")
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(AppUI.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("个人资料")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: photoItem) { _, item in loadPhoto(item) }
        .sheet(isPresented: $showCropper) {
            if let cropSource {
                ProfileAvatarCropView(image: cropSource) { cropped in
                    do {
                        let filename = try UserProfileStore.save(cropped, replacing: settings.profileAvatarFilename)
                        settings.profileAvatarFilename = filename
                        errorMessage = nil
                    } catch {
                        errorMessage = "头像保存失败，请重试。"
                    }
                    self.cropSource = nil
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
            }
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                errorMessage = "无法读取这张照片。"
                photoItem = nil
                return
            }
            cropSource = image
            showCropper = true
            photoItem = nil
        }
    }
}

struct ProfileAvatarBadge: View {
    @Environment(AppSettings.self) private var settings
    @State private var image: UIImage?

    var size: CGFloat = 40

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.94), Color(hex: "F0E9FF").opacity(0.90)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    Circle().fill(.ultraThinMaterial).opacity(0.26)
                }

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.34, weight: .medium))
                    .foregroundStyle(settings.accent.color.gradient)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle().strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.92), settings.accent.color.opacity(0.42), .white.opacity(0.55)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
        }
        .shadow(color: settings.accent.color.opacity(0.16), radius: 8, y: 3)
        .task(id: settings.profileAvatarFilename) {
            image = UserProfileStore.image(named: settings.profileAvatarFilename)
        }
        .accessibilityHidden(true)
    }
}

private enum UserProfileStore {
    private static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Mimir/Profile", directoryHint: .isDirectory)
    }

    static func image(named filename: String?) -> UIImage? {
        guard let filename,
              URL(fileURLWithPath: filename).lastPathComponent == filename else { return nil }
        return UIImage(contentsOfFile: directory.appending(path: filename).path)
    }

    static func save(_ image: UIImage, replacing oldFilename: String?) throws -> String {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        let filename = "avatar-\(UUID().uuidString).jpg"
        let destination = directory.appending(path: filename)
        guard let data = image.jpegData(compressionQuality: 0.88) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])

        if let oldFilename,
           URL(fileURLWithPath: oldFilename).lastPathComponent == oldFilename {
            try? FileManager.default.removeItem(at: directory.appending(path: oldFilename))
        }
        return filename
    }
}

private struct ProfileAvatarCropView: View {
    let image: UIImage
    let onSave: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appAccent) private var accent
    @Environment(\.colorScheme) private var colorScheme
    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            let diameter = min(280, max(220, geometry.size.width - 56))

            VStack(spacing: 0) {
                HStack {
                    Button("取消") { dismiss() }
                        .foregroundStyle(AppUI.label2)
                    Spacer()
                    Text("调整头像")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppUI.label)
                    Spacer()
                    Button("使用头像") {
                        if let cropped = croppedImage(viewport: diameter) {
                            onSave(cropped)
                            dismiss()
                        }
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)

                Spacer(minLength: 18)

                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: image.size.width * displayScale(viewport: diameter) * zoom,
                        height: image.size.height * displayScale(viewport: diameter) * zoom
                    )
                    .offset(offset)
                    .frame(width: diameter, height: diameter)
                    .clipped()
                    .clipShape(Circle())
                    .overlay {
                        Circle().strokeBorder(.white.opacity(0.92), lineWidth: 2)
                    }
                    .shadow(color: accent.opacity(0.20), radius: 24, y: 10)
                    .gesture(cropGesture(viewport: diameter))
                    .accessibilityLabel("头像裁剪预览")

                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "minus.magnifyingglass")
                        Slider(value: Binding(
                            get: { zoom },
                            set: { value in
                                zoom = value
                                committedZoom = value
                                offset = clampedOffset(offset, zoom: value, viewport: diameter)
                                committedOffset = offset
                            }
                        ), in: 1...4)
                        .tint(accent)
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppUI.label2)
                    .padding(.horizontal, 30)

                    Button("重置") {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                            zoom = 1
                            committedZoom = 1
                            offset = .zero
                            committedOffset = .zero
                        }
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(accent)
                }
                .padding(.top, 30)
                .padding(.bottom, 34)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppUI.ambientBackground(scheme: colorScheme).ignoresSafeArea())
        }
    }

    private func displayScale(viewport: CGFloat) -> CGFloat {
        viewport / max(min(image.size.width, image.size.height), 1)
    }

    private func cropGesture(viewport: CGFloat) -> some Gesture {
        SimultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    zoom = min(4, max(1, committedZoom * value))
                    offset = clampedOffset(offset, zoom: zoom, viewport: viewport)
                }
                .onEnded { _ in committedZoom = zoom },
            DragGesture()
                .onChanged { value in
                    offset = clampedOffset(
                        CGSize(width: committedOffset.width + value.translation.width,
                               height: committedOffset.height + value.translation.height),
                        zoom: zoom,
                        viewport: viewport
                    )
                }
                .onEnded { _ in committedOffset = offset }
        )
    }

    private func clampedOffset(_ value: CGSize, zoom: CGFloat, viewport: CGFloat) -> CGSize {
        let scale = displayScale(viewport: viewport) * zoom
        let maxX = max(0, (image.size.width * scale - viewport) / 2)
        let maxY = max(0, (image.size.height * scale - viewport) / 2)
        return CGSize(
            width: min(max(value.width, -maxX), maxX),
            height: min(max(value.height, -maxY), maxY)
        )
    }

    private func croppedImage(viewport: CGFloat) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: image.size)
        let upright = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
        guard let source = upright.cgImage else { return nil }

        let width = CGFloat(source.width)
        let height = CGFloat(source.height)
        let scale = viewport / min(width, height) * zoom
        let side = min(width, height, viewport / scale)
        let centerX = width / 2 - offset.width / scale
        let centerY = height / 2 - offset.height / scale
        let originX = min(max(centerX - side / 2, 0), width - side)
        let originY = min(max(centerY - side / 2, 0), height - side)
        guard let cropped = source.cropping(to: CGRect(x: originX, y: originY, width: side, height: side)) else {
            return nil
        }
        return UIImage(cgImage: cropped, scale: 1, orientation: .up)
    }
}
