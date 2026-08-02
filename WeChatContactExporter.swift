import Cocoa
import Vision
import ApplicationServices

struct Contact {
    let index: Int
    let remark: String
    let nickname: String
    let wechatID: String
    let phone: String
    let region: String
    let tags: String
    let raw: String
}

func csv(_ value: String) -> String {
    "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
}

func alert(_ message: String) {
    let escaped = message.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    p.arguments = ["-e", "display alert \"\(escaped)\""]
    try? p.run()
    p.waitUntilExit()
}

func fail(_ message: String) -> Never {
    fputs("\n错误：\(message)\n", stderr)
    alert(message)
    exit(1)
}

func wechatWindow() -> (id: CGWindowID, bounds: CGRect)? {
    guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
    for w in windows {
        let owner = w[kCGWindowOwnerName as String] as? String ?? ""
        let layer = w[kCGWindowLayer as String] as? Int ?? -1
        guard layer == 0, owner.localizedCaseInsensitiveContains("WeChat") || owner.contains("微信") else { continue }
        guard let number = w[kCGWindowNumber as String] as? NSNumber,
              let dict = w[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: dict) else { continue }
        if bounds.width > 500 && bounds.height > 400 { return (CGWindowID(number.uint32Value), bounds) }
    }
    return nil
}

func capture(windowID: CGWindowID, to url: URL) -> Bool {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-x", "-o", "-l", String(windowID), url.path]
    do { try p.run(); p.waitUntilExit(); return p.terminationStatus == 0 } catch { return false }
}

func recognize(_ url: URL, minimumX: CGFloat = 0.38) -> [String] {
    guard let image = NSImage(contentsOf: url),
          let data = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: data),
          let cg = rep.cgImage else { return [] }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
    do { try VNImageRequestHandler(cgImage: cg).perform([request]) } catch { return [] }
    let observations = request.results ?? []
    // 微信左侧通常是联系人列表；只保留窗口右侧约 62% 的资料区域。
    return observations
        .filter { $0.boundingBox.midX > minimumX }
        .sorted {
            if abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.018 { return $0.boundingBox.midY > $1.boundingBox.midY }
            return $0.boundingBox.minX < $1.boundingBox.minX
        }
        .compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

func value(after labels: [String], in lines: [String]) -> String {
    for (i, line) in lines.enumerated() {
        for label in labels {
            if line == label, i + 1 < lines.count { return lines[i + 1] }
            if line.hasPrefix(label) {
                let v = String(line.dropFirst(label.count)).trimmingCharacters(in: CharacterSet(charactersIn: "：: "))
                if !v.isEmpty { return v }
            }
        }
    }
    return ""
}

func phoneNumbers(in lines: [String]) -> String {
    // Finds common international/local phone formats in text already visible on
    // the profile. Dates and digit strings outside 7...15 digits are excluded.
    guard let regex = try? NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9])\+?\d[\d\s()\-.]{5,}\d(?![A-Za-z0-9])"#
    ) else { return "" }
    var found: [String] = []
    for line in lines {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        for match in regex.matches(in: line, range: range) {
            guard let r = Range(match.range, in: line) else { continue }
            let candidate = String(line[r]).trimmingCharacters(in: .whitespacesAndNewlines)
            let digits = candidate.filter(\.isNumber)
            guard (7...15).contains(digits.count) else { continue }
            // Avoid ISO-style dates such as 2023-11-26 and compact YYYYMMDD dates.
            if candidate.range(of: #"^(19|20)\d{2}[-/.]\d{1,2}[-/.]\d{1,2}$"#, options: .regularExpression) != nil { continue }
            if digits.count == 8, digits.hasPrefix("19") || digits.hasPrefix("20") { continue }
            let normalized = candidate.hasPrefix("+") ? "+" + digits : digits
            if !found.contains(normalized) { found.append(normalized) }
        }
    }
    return found.joined(separator: "; ")
}

func activateWeChat() {
    if let app = NSWorkspace.shared.runningApplications.first(where: {
        $0.bundleIdentifier == "com.tencent.xinWeChat"
    }) { app.activate(options: [.activateAllWindows]) }
}

// Locate WeChat's green selected-contact row in the left portion of the captured window.
// The returned point uses global macOS screen coordinates and accounts for Retina scale.
func selectedRowPoint(in imageURL: URL, windowBounds: CGRect) -> CGPoint? {
    guard let image = NSImage(contentsOf: imageURL),
          let data = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: data) else { return nil }
    let width = bitmap.pixelsWide, height = bitmap.pixelsHigh
    guard width > 0, height > 0 else { return nil }
    let maxX = Int(Double(width) * 0.38)
    var bestY = -1, bestCount = 0, bestSumX = 0
    for y in 0..<height {
        var count = 0, sumX = 0
        for x in 0..<maxX {
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
            let r = color.redComponent, g = color.greenComponent, b = color.blueComponent
            // Covers current WeChat selection greens while excluding icons and pale backgrounds.
            if g > 0.48 && g > r * 1.65 && g > b * 1.25 && r < 0.38 {
                count += 1; sumX += x
            }
        }
        if count > bestCount { bestCount = count; bestY = y; bestSumX = sumX }
    }
    guard bestY >= 0, bestCount > max(30, width / 20) else { return nil }
    let pixelX = CGFloat(bestSumX / bestCount)
    // For screenshots loaded through NSBitmapImageRep, colorAt uses the raster's
    // top-down row order here, matching global screen coordinates.
    let pixelYFromTop = CGFloat(bestY)
    let pointX = windowBounds.minX + pixelX * windowBounds.width / CGFloat(width)
    let pointY = windowBounds.minY + pixelYFromTop * windowBounds.height / CGFloat(height)
    return CGPoint(x: pointX, y: pointY)
}

func click(_ point: CGPoint) {
    let source = CGEventSource(stateID: .hidSystemState)
    CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.12)
    CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
}

func scrollContactsDown(at point: CGPoint) {
    let source = CGEventSource(stateID: .hidSystemState)
    CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.12)
    // Negative wheel movement scrolls the contact list downward.
    CGEvent(scrollWheelEvent2Source: source, units: .line, wheelCount: 1,
            wheel1: -6, wheel2: 0, wheel3: 0)?.post(tap: .cghidEventTap)
}

let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
guard AXIsProcessTrustedWithOptions(options) else {
    fail("缺少辅助功能权限。请在“系统设置 → 隐私与安全性 → 辅助功能”中允许 Terminal，然后完全退出并重新打开 Terminal。")
}

if !CGPreflightScreenCaptureAccess() {
    _ = CGRequestScreenCaptureAccess()
    fail("缺少屏幕录制权限。请在“系统设置 → 隐私与安全性 → 屏幕与系统音频录制”中允许 Terminal，然后完全退出并重新打开 Terminal。")
}

print("\n请先在微信中打开“通讯录”，并点击第一位要导出的好友。")
print("输入最多导出多少人（首次测试请输入 1），然后按回车：", terminator: " ")
fflush(stdout)
guard let requested = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
      let limit = Int(requested), limit > 0 else {
    fail("输入无效。请输入大于 0 的整数，例如 1。")
}

activateWeChat()
Thread.sleep(forTimeInterval: 1.5)
guard let window = wechatWindow() else {
    fail("未找到微信主窗口。请确认 Mac 微信已登录、主窗口不是最小化状态，并停留在通讯录页面。")
}

let fm = FileManager.default
let desktop = fm.urls(for: .desktopDirectory, in: .userDomainMask)[0]
let formatter = DateFormatter(); formatter.dateFormat = "yyyyMMdd-HHmmss"
let output = desktop.appendingPathComponent("wechat-contacts-\(formatter.string(from: Date())).csv")
let diagnosticFolder = desktop.appendingPathComponent("WeChatContactExporter", isDirectory: true)
try? fm.createDirectory(at: diagnosticFolder, withIntermediateDirectories: true)
let temp = diagnosticFolder.appendingPathComponent("last-capture.png")
let diagnosticText = diagnosticFolder.appendingPathComponent("last-ocr.txt")
var rows: [Contact] = []
var seen = Set<String>()
var repeats = 0

for i in 1...limit {
    autoreleasepool {
        Thread.sleep(forTimeInterval: Double.random(in: 1.1...1.8))
        guard capture(windowID: window.id, to: temp), fm.fileExists(atPath: temp.path) else {
            fail("微信窗口截图失败。请确认 Terminal 已获得“屏幕与系统音频录制”权限，并在授权后完全退出、重新打开 Terminal。")
        }
        let allLines = recognize(temp, minimumX: 0.0)
        let lines = recognize(temp, minimumX: 0.38)
        let diagnostic = "窗口：\(Int(window.bounds.width))×\(Int(window.bounds.height))\n全窗口 OCR 行数：\(allLines.count)\n右侧资料区 OCR 行数：\(lines.count)\n\n全窗口：\n" + allLines.joined(separator: "\n") + "\n\n右侧资料区：\n" + lines.joined(separator: "\n")
        try? diagnostic.write(to: diagnosticText, atomically: true, encoding: .utf8)
        print("第 \(i) 位：全窗口识别 \(allLines.count) 行，资料区识别 \(lines.count) 行")
        fflush(stdout)
        if lines.isEmpty {
            fail("没有识别到资料页文字。诊断截图和 OCR 日志已保存到桌面的 WeChatContactExporter 文件夹，请保留它们用于校准。")
        }
        let joined = lines.joined(separator: " ").lowercased()
        let isProfile = joined.contains("friend profile") ||
            joined.contains("wechat id") || joined.contains("微信号") || joined.contains("微信號")
        if !isProfile {
            fail("当前画面不是好友资料页，脚本已停止以避免导出聊天记录。请先点击微信左侧绿色“通讯录”图标，展开 Contacts，单击一位好友，确认右侧出现 Friend Profile 和 WeChat ID，再重新运行。")
        }
        let raw = lines.joined(separator: " | ")
        let remark = lines.first ?? ""
        let nick = value(after: ["昵称", "暱稱"], in: lines)
        let wxid = value(after: ["微信号", "微信號", "WeChat ID"], in: lines)
        let phone = phoneNumbers(in: lines)
        let region = value(after: ["地区", "地區", "Region"], in: lines)
        let tags = value(after: ["标签", "標籤", "Tags"], in: lines)
        let fingerprint = wxid.isEmpty ? raw : wxid
        if fingerprint.isEmpty || seen.contains(fingerprint) { repeats += 1 } else {
            repeats = 0; seen.insert(fingerprint)
            rows.append(Contact(index: i, remark: remark, nickname: nick, wechatID: wxid, phone: phone, region: region, tags: tags, raw: raw))
        }
    }
    if repeats >= 3 { break }
    guard let rowPoint = selectedRowPoint(in: temp, windowBounds: window.bounds) else {
        fail("找不到左侧绿色高亮的联系人行，无法安全切换到下一位。请确保 Contacts 列表中有一位好友被绿色高亮选中。")
    }
    // Contact rows in WeChat 4.1.2 are about 54 points high. If a section
    // heading falls between rows, a repeated profile adds an extra heading offset.
    var nextPoint = CGPoint(x: rowPoint.x, y: rowPoint.y + 54 + CGFloat(repeats * 26))
    let listBottom = window.bounds.maxY - 18
    if nextPoint.y >= listBottom {
        scrollContactsDown(at: rowPoint)
        Thread.sleep(forTimeInterval: 0.8)
        guard capture(windowID: window.id, to: temp),
              let movedRow = selectedRowPoint(in: temp, windowBounds: window.bounds) else {
            fail("联系人列表滚动后无法定位当前高亮行，已安全停止。")
        }
        nextPoint = CGPoint(x: movedRow.x, y: movedRow.y + 54 + CGFloat(repeats * 26))
    }
    click(nextPoint)
    Thread.sleep(forTimeInterval: 0.55)
}

var text = "序号,备注/资料页首行,昵称,微信号,Phone Number,地区,标签,OCR原文\n"
for r in rows {
    text += [String(r.index), r.remark, r.nickname, r.wechatID, r.phone, r.region, r.tags, r.raw].map(csv).joined(separator: ",") + "\n"
}
do {
    try text.write(to: output, atomically: true, encoding: .utf8)
    alert("完成：导出 \(rows.count) 条。文件已保存到桌面：\n\(output.lastPathComponent)\n\n请先抽查 OCR 内容，再进行大批量导出。")
} catch {
    fail("无法写入 CSV：\(error.localizedDescription)")
}
