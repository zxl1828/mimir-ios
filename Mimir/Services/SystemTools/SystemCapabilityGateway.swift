import Contacts
import CoreLocation
import EventKit
import Foundation
import MapKit
import UIKit

/// 系统能力工具网关。
///
/// 与 `SystemToolRegistry`（OCR / 条码 / Spotlight / 搜索）并列，专门承载**需要系统权限**
/// 的能力：时间、日历、提醒、通讯录、拨号、分享、定位、POI、文件导出。
/// 两者都产出 `LLMToolDefinition` 并实现同名 `invoke`，由 registry 统一分发。
///
/// 设计原则：任何权限被拒都返回**可读的中文说明**，让模型能向用户解释，而不是抛错。
@MainActor
enum SystemCapabilityGateway {

    // MARK: - 工具名

    nonisolated static let timeTool = "system_current_time"
    nonisolated static let calendarReadTool = "system_calendar_read"
    nonisolated static let calendarCreateTool = "system_calendar_create"
    nonisolated static let reminderCreateTool = "system_reminder_create"
    nonisolated static let contactsSearchTool = "system_contacts_search"
    nonisolated static let dialTool = "system_phone_dial"
    nonisolated static let shareTool = "system_share"
    nonisolated static let locationTool = "system_location_once"
    nonisolated static let poiTool = "system_poi_search"
    nonisolated static let exportTool = "system_file_export"

    nonisolated static let allNames: Set<String> = [
        timeTool, calendarReadTool, calendarCreateTool, reminderCreateTool,
        contactsSearchTool, dialTool, shareTool, locationTool, poiTool, exportTool
    ]

    nonisolated static func handles(_ name: String) -> Bool { allNames.contains(name) }

    // MARK: - 工具定义

    nonisolated static var definitions: [LLMToolDefinition] {
        [
            LLMToolDefinition(
                name: timeTool,
                description: "读取设备当前时间、时区与 UTC 偏移。",
                parametersJSON: #"{"type":"object","properties":{},"required":[]}"#
            ),
            LLMToolDefinition(
                name: calendarReadTool,
                description: "读取系统日历中的日程，默认今天。",
                parametersJSON: #"{"type":"object","properties":{"days":{"type":"integer","description":"向后读取天数，默认 1，最多 14"}},"required":[]}"#
            ),
            LLMToolDefinition(
                name: calendarCreateTool,
                description: "创建一条系统日历日程。",
                parametersJSON: #"{"type":"object","properties":{"title":{"type":"string"},"start":{"type":"string","description":"ISO8601 开始时间"},"end":{"type":"string","description":"可选，ISO8601 结束时间"},"location":{"type":"string"},"notes":{"type":"string"}},"required":["title","start"]}"#
            ),
            LLMToolDefinition(
                name: reminderCreateTool,
                description: "在系统「提醒事项」里创建待办。",
                parametersJSON: #"{"type":"object","properties":{"title":{"type":"string"},"due":{"type":"string","description":"可选，ISO8601 截止时间"},"notes":{"type":"string"}},"required":["title"]}"#
            ),
            LLMToolDefinition(
                name: contactsSearchTool,
                description: "按姓名或号码检索通讯录，返回姓名与电话。",
                parametersJSON: #"{"type":"object","properties":{"query":{"type":"string"}},"required":["query"]}"#
            ),
            LLMToolDefinition(
                name: dialTool,
                description: "准备拨打号码（交给系统拨号界面，不会自动拨出）。",
                parametersJSON: #"{"type":"object","properties":{"number":{"type":"string"},"name":{"type":"string"}},"required":["number"]}"#
            ),
            LLMToolDefinition(
                name: shareTool,
                description: "把文本或文件交给系统分享面板，用于跨 App 分发。",
                parametersJSON: #"{"type":"object","properties":{"text":{"type":"string"},"file_path":{"type":"string"}},"required":[]}"#
            ),
            LLMToolDefinition(
                name: locationTool,
                description: "获取一次当前位置（公里级精度，不做持续定位）。",
                parametersJSON: #"{"type":"object","properties":{},"required":[]}"#
            ),
            LLMToolDefinition(
                name: poiTool,
                description: "检索附近或指定城市的地点（餐厅、酒店、景点等）。",
                parametersJSON: #"{"type":"object","properties":{"query":{"type":"string"},"near":{"type":"string","description":"可选，参照地点"}},"required":["query"]}"#
            ),
            LLMToolDefinition(
                name: exportTool,
                description: "把内容导出为文件（txt / md / csv / pdf），存到本机「文件」App 的 Mimir 目录。",
                parametersJSON: #"{"type":"object","properties":{"filename":{"type":"string"},"format":{"type":"string","enum":["txt","md","csv","pdf"]},"content":{"type":"string"},"title":{"type":"string"}},"required":["filename","format","content"]}"#
            )
        ]
    }

    // MARK: - 分发

    static func invoke(name: String, argumentsJSON: String) async -> String {
        let args = Arguments(json: argumentsJSON)
        switch name {
        case timeTool: return currentTime()
        case calendarReadTool: return await calendarRead(args)
        case calendarCreateTool: return await calendarCreate(args)
        case reminderCreateTool: return await reminderCreate(args)
        case contactsSearchTool: return await contactsSearch(args)
        case dialTool: return prepareDial(args)
        case shareTool: return prepareShare(args)
        case locationTool: return await currentLocation()
        case poiTool: return await poiSearch(args)
        case exportTool: return exportFile(args)
        default: return "未知的系统工具：" + name
        }
    }

    // MARK: - 时间

    private static func currentTime() -> String {
        let now = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 EEEE HH:mm:ss"
        let zone = TimeZone.current
        let offsetHours = Double(zone.secondsFromGMT(for: now)) / 3600
        return "当前时间：" + formatter.string(from: now)
            + "；时区：" + zone.identifier
            + String(format: "（UTC%+.1f）", offsetHours)
    }

    // MARK: - 日历

    private static func eventsAccess(_ store: EKEventStore) async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    private static func calendarRead(_ args: Arguments) async -> String {
        let days = min(max(args.int("days") ?? 1, 1), 14)
        let store = EKEventStore()
        guard await eventsAccess(store) else {
            return "没有日历读取权限，请在系统设置中允许 Mimir 访问日历。"
        }
        let start = Calendar.current.startOfDay(for: Date())
        guard let end = Calendar.current.date(byAdding: .day, value: days, to: start) else {
            return "时间范围计算失败。"
        }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
        guard !events.isEmpty else {
            return days == 1 ? "今天没有日程。" : "接下来 \(days) 天没有日程。"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        let lines = events.prefix(20).map { event -> String in
            let time = event.isAllDay
                ? "全天"
                : formatter.string(from: event.startDate)
            return "- " + time + "｜" + (event.title ?? "未命名")
        }
        return "日程（\(events.count) 条）：\n" + lines.joined(separator: "\n")
    }

    private static func calendarCreate(_ args: Arguments) async -> String {
        guard let title = args.string("title") else { return "缺少日程标题。" }
        guard let start = args.date("start") else { return "缺少或无法解析开始时间（需要 ISO8601）。" }
        let end = args.date("end") ?? start.addingTimeInterval(3_600)

        let store = EKEventStore()
        guard await eventsAccess(store) else { return "没有日历写入权限，无法创建日程。" }
        guard let calendar = store.defaultCalendarForNewEvents else {
            return "没有可写入的默认日历。"
        }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = title
        event.startDate = start
        event.endDate = max(end, start.addingTimeInterval(300))
        event.location = args.string("location")
        event.notes = args.string("notes")

        do {
            try store.save(event, span: .thisEvent, commit: true)
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "M月d日 HH:mm"
            return "已创建日程「" + title + "」，时间 " + formatter.string(from: start) + "。"
        } catch {
            return "创建日程失败：" + error.localizedDescription
        }
    }

    // MARK: - 提醒事项

    private static func reminderCreate(_ args: Arguments) async -> String {
        guard let title = args.string("title") else { return "缺少待办标题。" }
        let store = EKEventStore()
        let granted = (try? await store.requestFullAccessToReminders()) ?? false
        guard granted else { return "没有提醒事项权限，请在系统设置中允许访问。" }
        guard let calendar = store.defaultCalendarForNewReminders() else {
            return "没有可写入的默认提醒列表。"
        }
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = calendar
        reminder.title = title
        reminder.notes = args.string("notes")
        if let due = args.date("due") {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: due
            )
            reminder.addAlarm(EKAlarm(absoluteDate: due))
        }
        do {
            try store.save(reminder, commit: true)
            return "已创建待办「" + title + "」。"
        } catch {
            return "创建待办失败：" + error.localizedDescription
        }
    }

    // MARK: - 通讯录与拨号

    private static func contactsSearch(_ args: Arguments) async -> String {
        guard let query = args.string("query"), !query.isEmpty else { return "缺少检索关键词。" }
        let store = CNContactStore()
        let granted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            store.requestAccess(for: .contacts) { ok, _ in continuation.resume(returning: ok) }
        }
        guard granted else { return "没有通讯录权限，请在系统设置中允许访问。" }

        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        var matches: [String] = []
        do {
            try store.enumerateContacts(with: request) { contact, stop in
                let name = [contact.familyName, contact.givenName].filter { !$0.isEmpty }.joined()
                let numbers = contact.phoneNumbers.map { $0.value.stringValue }
                let haystack = ([name, contact.organizationName] + numbers).joined(separator: "|")
                guard haystack.localizedCaseInsensitiveContains(query) else { return }
                let display = name.isEmpty ? contact.organizationName : name
                matches.append("- " + display + "｜" + (numbers.isEmpty ? "无号码" : numbers.joined(separator: " / ")))
                if matches.count >= 8 { stop.pointee = true }
            }
        } catch {
            return "通讯录检索失败：" + error.localizedDescription
        }
        guard !matches.isEmpty else { return "通讯录里没有匹配「" + query + "」的联系人。" }
        return "通讯录匹配：\n" + matches.joined(separator: "\n")
    }

    /// 拨号只能"准备"，由 UI 层调用 openURL —— 系统不允许 App 静默拨出。
    private static func prepareDial(_ args: Arguments) -> String {
        guard let raw = args.string("number") else { return "缺少电话号码。" }
        let digits = raw.filter { $0.isNumber || $0 == "+" || $0 == "-" }
        guard !digits.isEmpty else { return "电话号码格式不正确。" }
        let name = args.string("name")
        PendingSystemAction.shared.setDial(number: digits, name: name)
        return "已准备拨号" + (name.map { "给" + $0 } ?? "") + "：" + digits + "，请在界面上确认后拨出。"
    }

    private static func prepareShare(_ args: Arguments) -> String {
        var items: [String] = []
        if let text = args.string("text"), !text.isEmpty { items.append(text) }
        if let path = args.string("file_path"), !path.isEmpty { items.append(path) }
        if items.isEmpty, let url = PendingSystemAction.shared.lastExportURL {
            items.append(url.path)
        }
        guard !items.isEmpty else { return "没有可分享的内容。" }
        PendingSystemAction.shared.setShare(items: items)
        return "已准备分享内容（\(items.count) 项），请在界面上滑出分享面板。"
    }

    // MARK: - 定位与 POI

    private static func currentLocation() async -> String {
        do {
            let location = try await LocationProvider.shared.requestOnce()
            return String(
                format: "当前位置：纬度 %.4f，经度 %.4f（精度约 %.0f 米）",
                location.coordinate.latitude,
                location.coordinate.longitude,
                location.horizontalAccuracy
            )
        } catch {
            return "定位失败：" + error.localizedDescription
        }
    }

    private static func poiSearch(_ args: Arguments) async -> String {
        guard let query = args.string("query"), !query.isEmpty else { return "缺少检索关键词。" }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query

        if let near = args.string("near"), !near.isEmpty {
            let anchor = MKLocalSearch.Request()
            anchor.naturalLanguageQuery = near
            if let response = try? await MKLocalSearch(request: anchor).start(),
               let coordinate = response.mapItems.first?.placemark.coordinate {
                request.region = MKCoordinateRegion(
                    center: coordinate,
                    latitudinalMeters: 20_000,
                    longitudinalMeters: 20_000
                )
            }
        }

        do {
            let response = try await MKLocalSearch(request: request).start()
            guard !response.mapItems.isEmpty else { return "没有找到「" + query + "」相关地点。" }
            let lines = response.mapItems.prefix(5).enumerated().map { index, item -> String in
                let placemark = item.placemark
                let title = item.name ?? placemark.name ?? "未命名地点"
                let address = [placemark.locality, placemark.subLocality, placemark.thoroughfare]
                    .compactMap { $0 }.joined()
                return String(
                    format: "%d. %@｜%@｜%.5f, %.5f",
                    index + 1, title,
                    address.isEmpty ? "地址未知" : address,
                    placemark.coordinate.latitude,
                    placemark.coordinate.longitude
                )
            }
            return "地点检索结果：\n" + lines.joined(separator: "\n")
        } catch {
            return "地点检索失败：" + error.localizedDescription
        }
    }

    // MARK: - 文件导出

    private static func exportFile(_ args: Arguments) -> String {
        guard
            let filename = args.string("filename"),
            let formatRaw = args.string("format")?.lowercased(),
            let content = args.string("content")
        else {
            return "缺少 filename / format / content 参数。"
        }
        if formatRaw == "xlsx" {
            return "暂不支持 xlsx；可以改用 csv，Excel 可以直接打开。"
        }
        guard ["txt", "md", "csv", "pdf"].contains(formatRaw) else {
            return "不支持的格式：" + formatRaw + "（支持 txt / md / csv / pdf）。"
        }
        do {
            let url = try SystemFileExporter.export(
                title: args.string("title") ?? filename,
                body: content,
                filename: filename,
                fileExtension: formatRaw
            )
            PendingSystemAction.shared.setExport(url: url)
            return "已导出：" + url.lastPathComponent + "，路径 " + url.path + "（可在「文件」App 的 Mimir 目录找到）。"
        } catch {
            return "导出失败：" + error.localizedDescription
        }
    }
}

// MARK: - 参数解析

/// 工具参数读取器（工具参数都是扁平 JSON）。
struct Arguments {

    private let storage: [String: Any]

    init(json: String) {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            storage = [:]
            return
        }
        storage = dictionary
    }

    func string(_ key: String) -> String? {
        if let value = storage[key] as? String { return value }
        if let value = storage[key] as? NSNumber { return value.stringValue }
        return nil
    }

    func int(_ key: String) -> Int? {
        if let value = storage[key] as? Int { return value }
        if let value = storage[key] as? NSNumber { return value.intValue }
        if let value = storage[key] as? String { return Int(value) }
        return nil
    }

    func date(_ key: String) -> Date? {
        guard let raw = string(key) else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: raw)
    }
}

// MARK: - 待用户确认的系统动作

/// 拨号与分享不能静默执行，暂存在这里由 UI 层消费。
@MainActor
@Observable
final class PendingSystemAction {

    static let shared = PendingSystemAction()

    struct DialRequest: Equatable, Sendable {
        var number: String
        var name: String?
    }

    private(set) var dialRequest: DialRequest?
    private(set) var shareItems: [String] = []
    private(set) var lastExportURL: URL?

    private init() {}

    func setDial(number: String, name: String?) {
        dialRequest = DialRequest(number: number, name: name)
    }

    func consumeDial() -> DialRequest? {
        defer { dialRequest = nil }
        return dialRequest
    }

    func setShare(items: [String]) {
        shareItems = items
    }

    func consumeShare() -> [String] {
        defer { shareItems = [] }
        return shareItems
    }

    func setExport(url: URL) {
        lastExportURL = url
    }

    func dialURL(for request: DialRequest) -> URL? {
        URL(string: "tel://" + request.number)
    }
}

// MARK: - 单次定位

/// 只为"拿一次当前位置"存在（公里级精度，不记录轨迹、不持续定位）。
@MainActor
final class LocationProvider: NSObject {

    static let shared = LocationProvider()

    enum LocationError: LocalizedError {
        case denied
        case unavailable

        var errorDescription: String? {
            switch self {
            case .denied: return "没有定位权限，请在系统设置中允许「使用 App 期间」。"
            case .unavailable: return "暂时拿不到定位，请稍后重试。"
            }
        }
    }

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestOnce() async throws -> CLLocation {
        let status = manager.authorizationStatus
        if status == .denied || status == .restricted { throw LocationError.denied }
        if status == .notDetermined { manager.requestWhenInUseAuthorization() }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
        }
    }

    fileprivate func finish(_ result: Result<CLLocation, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }
}

extension LocationProvider: CLLocationManagerDelegate {

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in self.finish(.success(location)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(.failure(error)) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let status = self.manager.authorizationStatus
            guard status == .denied || status == .restricted else { return }
            self.finish(.failure(LocationProvider.LocationError.denied))
        }
    }
}

// MARK: - 文件导出

/// 极简文件导出：txt / md / csv / pdf 写入 App 文档目录的 `Exports/`。
///
/// 配合 Info.plist 里的 `UIFileSharingEnabled` 与 `LSSupportsOpeningDocumentsInPlace`，
/// 用户可以在「文件」App 里直接看到导出的文档。
enum SystemFileExporter {

    enum ExportError: LocalizedError {
        case emptyContent
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .emptyContent: return "内容为空，无法导出。"
            case .writeFailed(let reason): return "写入失败：" + reason
            }
        }
    }

    static func export(
        title: String,
        body: String,
        filename: String,
        fileExtension: String
    ) throws -> URL {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ExportError.emptyContent }

        let folder = try exportFolder()
        let target = folder
            .appendingPathComponent(sanitize(filename))
            .appendingPathExtension(fileExtension)

        do {
            switch fileExtension {
            case "pdf":
                try makePDF(title: title, body: trimmed).write(to: target, options: .atomic)
            case "csv":
                // 带 BOM，Excel 打开不乱码
                var data = Data([0xEF, 0xBB, 0xBF])
                data.append(Data(trimmed.utf8))
                try data.write(to: target, options: .atomic)
            default:
                try trimmed.write(to: target, atomically: true, encoding: .utf8)
            }
        } catch let error as ExportError {
            throw error
        } catch {
            throw ExportError.writeFailed(error.localizedDescription)
        }
        return target
    }

    private static func exportFolder() throws -> URL {
        let base = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folder = base.appendingPathComponent("Exports", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    private static func sanitize(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = name
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((cleaned.isEmpty ? "Mimir-Export" : cleaned).prefix(60))
    }

    private static func makePDF(title: String, body: String) -> Data {
        let pageSize = CGSize(width: 595, height: 842)   // A4 @72dpi
        let margin: CGFloat = 48
        let textWidth = pageSize.width - margin * 2
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))

        return renderer.pdfData { context in
            var cursorY = margin
            context.beginPage()

            title.draw(
                in: CGRect(x: margin, y: cursorY, width: textWidth, height: 30),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 20, weight: .semibold),
                    .foregroundColor: UIColor.label
                ]
            )
            cursorY += 40

            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.label
            ]
            for line in body.components(separatedBy: .newlines) {
                let bounding = (line as NSString).boundingRect(
                    with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attributes,
                    context: nil
                )
                let height = max(bounding.height, 16)
                if cursorY + height > pageSize.height - margin {
                    context.beginPage()
                    cursorY = margin
                }
                (line as NSString).draw(
                    in: CGRect(x: margin, y: cursorY, width: textWidth, height: height),
                    withAttributes: attributes
                )
                cursorY += height + 2
            }
        }
    }
}
