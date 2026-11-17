import SwiftUI
import AppKit
import EventKit
import IOKit.ps
import IOKit.pwr_mgt
import CoreAudio

// MARK: Battery
final class BatteryService: ObservableObject {
    static let shared = BatteryService()
    @Published var percent = 100
    @Published var charging = false
    @Published var plugged = false
    @Published var hasBattery = false
    private var first = true
    private var lowFired = false

    func start() {
        let t = Timer(timeInterval: 4, repeats: true) { [weak self] _ in self?.update() }
        RunLoop.main.add(t, forMode: .common)
        update()
    }
    private func update() {
        if Background.paused { return }
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
                  let cap = d[kIOPSCurrentCapacityKey] as? Int else { continue }
            let mx = (d[kIOPSMaxCapacityKey] as? Int) ?? 100
            let pct = mx > 0 ? cap * 100 / mx : cap
            let isCharging = (d[kIOPSIsChargingKey] as? Bool) ?? false
            let ac = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let changedPlug = ac != plugged
            hasBattery = true
            percent = pct; charging = isCharging
            plugged = ac
            if !first && changedPlug && P.bool("chargingAlerts") {
                NotchState.shared.post(IslandAlert(symbol: ac ? "bolt.fill" : "battery.50", tint: ac ? .green : .orange,
                                                   title: ac ? "Charging" : "On Battery", detail: "\(pct)%", level: Double(pct) / 100))
            }
            if !ac && pct <= 20 && !lowFired && P.bool("lowBatteryAlerts") {
                lowFired = true
                NotchState.shared.post(IslandAlert(symbol: "battery.25", tint: .red, title: "Low Battery", detail: "\(pct)% remaining", level: Double(pct) / 100, duration: 4))
            }
            if pct > 25 || ac { lowFired = false }
            first = false
            return
        }
    }
    var symbol: String {
        if charging || plugged { return "battery.100.bolt" }
        switch percent {
        case 0..<15: return "battery.0"
        case 15..<40: return "battery.25"
        case 40..<65: return "battery.50"
        case 65..<90: return "battery.75"
        default: return "battery.100"
        }
    }
}


// MARK: Tray
final class TrayStore: ObservableObject {
    static let shared = TrayStore()
    @Published var files: [URL] = []
    @Published var selected = Set<URL>()
    var selectedFiles: [URL] { files.filter { selected.contains($0) } }
    init() {
        guard Demo.on else { return }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Notchly Demo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for n in ["Design brief.pdf", "Hero shot.png", "Budget.xlsx", "Release notes.md", "Moodboard.key", "Demo reel.mov"] {
            let u = dir.appendingPathComponent(n)
            if !FileManager.default.fileExists(atPath: u.path) { FileManager.default.createFile(atPath: u.path, contents: Data("demo".utf8)) }
            files.append(u)
        }
        selected = Set(files.prefix(2))
    }
    func add(_ urls: [URL]) {
        for u in urls where !files.contains(u) { files.append(u) }
    }
    func toggle(_ u: URL) {
        if selected.contains(u) { selected.remove(u) } else { selected.insert(u) }
    }
    func selectAll() { selected = Set(files) }
    func deselect() { selected = [] }
    func remove(_ list: [URL]) {
        let s = Set(list)
        files.removeAll { s.contains($0) }
        selected.subtract(s)
    }
    func remove(_ u: URL) { remove([u]) }
    func clear() { files = []; selected = [] }
}

func loadFileURLs(_ providers: [NSItemProvider], _ done: @escaping ([URL]) -> Void) {
    var out: [URL] = []
    let lock = NSLock()
    let g = DispatchGroup()
    for p in providers where p.hasItemConformingToTypeIdentifier("public.file-url") {
        g.enter()
        p.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            var found: URL?
            if let d = item as? Data { found = URL(dataRepresentation: d, relativeTo: nil) }
            else if let u = item as? URL { found = u }
            else if let u = item as? NSURL { found = u as URL }
            if let u = found { lock.lock(); out.append(u); lock.unlock() }
            g.leave()
        }
    }
    g.notify(queue: .main) { done(out) }
}

// MARK: Timer
enum TimerMode: String, CaseIterable { case timer = "Timer", stopwatch = "Stopwatch", focus = "Focus" }

final class TimerStore: ObservableObject {
    static let shared = TimerStore()
    @Published var mode: TimerMode = .timer
    @Published var running = false
    @Published var remaining: TimeInterval = 300
    @Published var elapsed: TimeInterval = 0
    @Published var onBreak = false
    @Published var total: TimeInterval = 300
    private var tmr: Timer?
    private var endDate = Date()
    private var base = Date()

    func setMode(_ m: TimerMode) {
        stop()
        mode = m
        onBreak = false
        elapsed = 0
        total = m == .focus ? P.dbl("focusMinutes") * 60 : (m == .timer ? 300 : 0)
        remaining = total
    }
    func setMinutes(_ m: Double) { stop(); total = m * 60; remaining = total }
    func toggle() { running ? stop() : start() }
    func start() {
        if running { return }
        if mode == .stopwatch { base = Date().addingTimeInterval(-elapsed) }
        else {
            if remaining <= 0 { remaining = total }
            endDate = Date().addingTimeInterval(remaining)
        }
        running = true
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        tmr = t
    }
    func stop() { tmr?.invalidate(); tmr = nil; running = false }
    func reset() { stop(); elapsed = 0; remaining = total }
    private func tick() {
        if mode == .stopwatch { elapsed = Date().timeIntervalSince(base); return }
        remaining = max(0, endDate.timeIntervalSinceNow)
        if remaining <= 0 { finish() }
    }
    private func finish() {
        stop()
        if P.bool("timerSound") { NSSound(named: "Glass")?.play() }
        var title = "Timer done"
        if mode == .focus {
            title = onBreak ? "Break over" : "Focus complete"
            onBreak.toggle()
            total = (onBreak ? P.dbl("breakMinutes") : P.dbl("focusMinutes")) * 60
            remaining = total
            if P.bool("autoBreak") { start() }
        } else { remaining = total }
        NotchState.shared.post(IslandAlert(symbol: "timer", tint: .orange, title: title, duration: 4))
    }
    var progress: Double {
        if mode == .stopwatch || total <= 0 { return 0 }
        return 1 - remaining / total
    }
    var display: String {
        let v = mode == .stopwatch ? elapsed : remaining
        let s = Int(v.rounded(mode == .stopwatch ? .down : .up))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }
}

// MARK: Keep awake
final class KeepAwake: ObservableObject {
    static let shared = KeepAwake()
    @Published var on = false
    private var aid: IOPMAssertionID = 0
    func set(_ v: Bool) {
        if v == on { return }
        if v {
            IOPMAssertionCreateWithName("PreventUserIdleDisplaySleep" as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                        "Notchly keep awake" as CFString, &aid)
        } else { IOPMAssertionRelease(aid) }
        on = v
        NotchState.shared.post(IslandAlert(symbol: v ? "cup.and.saucer.fill" : "moon.zzz.fill", tint: v ? .orange : .gray,
                                           title: v ? "Keep Awake On" : "Keep Awake Off", duration: 1.8))
    }
    func toggle() { set(!on) }
}

// MARK: Stats
final class StatsService: ObservableObject {
    static let shared = StatsService()
    @Published var cpu: Double = 0
    @Published var mem: Double = 0
    @Published var disk: Double = 0
    @Published var cpuHistory: [Double] = Array(repeating: 0, count: 30)
    private var prev: (Double, Double, Double, Double)?

    func start() {
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            if !Background.paused && NotchState.shared.expanded && (NotchState.shared.tab == .stats || NotchState.shared.tab == .home) { self?.sample() }
        }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        sample()
    }
    static func demoHistory() -> [Double] {
        var out: [Double] = []
        for i in 0..<30 {
            let x = Double(i)
            let a: Double = 0.15 * sin(x / 3.0)
            let b: Double = 0.05 * sin(x * 1.7)
            out.append(0.2 + a + b)
        }
        return out
    }
    func sample() {
        if Demo.on { cpu = 0.27; mem = 0.58; disk = 0.64; cpuHistory = StatsService.demoHistory(); return }
        cpu = readCPU(); mem = readMem(); disk = readDisk()
        cpuHistory.append(cpu); if cpuHistory.count > 30 { cpuHistory.removeFirst(cpuHistory.count - 30) }
    }
    private func readCPU() -> Double {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        var info = host_cpu_load_info()
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        if r != KERN_SUCCESS { return cpu }
        let cur = (Double(info.cpu_ticks.0), Double(info.cpu_ticks.1), Double(info.cpu_ticks.2), Double(info.cpu_ticks.3))
        defer { prev = cur }
        guard let p = prev else { return 0 }
        let user = cur.0 - p.0, sys = cur.1 - p.1, idle = cur.2 - p.2, nice = cur.3 - p.3
        let tot = user + sys + idle + nice
        return tot > 0 ? (user + sys + nice) / tot : 0
    }
    private func readMem() -> Double {
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        var vm = vm_statistics64()
        let r = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }
        if r != KERN_SUCCESS { return mem }
        let page = Double(getpagesize())
        let used = (Double(vm.active_count) + Double(vm.wire_count) + Double(vm.compressor_page_count)) * page
        return min(1, used / Double(ProcessInfo.processInfo.physicalMemory))
    }
    private func readDisk() -> Double {
        let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        guard let t = v?.volumeTotalCapacity, let a = v?.volumeAvailableCapacityForImportantUsage, t > 0 else { return 0 }
        return 1 - Double(a) / Double(t)
    }
}

// MARK: Volume HUD
final class VolumeMonitor {
    static let shared = VolumeMonitor()
    private var last: Float = -1
    func start() {
        let t = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in self?.check() }
        RunLoop.main.add(t, forMode: .common)
        last = read() ?? -1
    }
    private var tickN = 0
    private func check() {
        if Background.paused { return }
        tickN += 1
        if Eco.on && tickN % 3 != 0 { return }
        guard let v = read() else { return }
        if last >= 0 && abs(v - last) > 0.001 && P.bool("levelAlerts") {
            let sym = v < 0.01 ? "speaker.slash.fill" : (v < 0.34 ? "speaker.wave.1.fill" : (v < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"))
            NotchState.shared.post(IslandAlert(symbol: sym, tint: .white, title: "Volume", level: Double(v), duration: 1.4))
        }
        last = v
    }
    private func read() -> Float? {
        var dev = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev) == noErr else { return nil }
        var vol: Float32 = 0
        size = UInt32(MemoryLayout<Float32>.size)
        var va = AudioObjectPropertyAddress(mSelector: 0x766D7663, mScope: kAudioDevicePropertyScopeOutput,
                                            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(dev, &va, 0, nil, &size, &vol) == noErr else { return nil }
        return vol
    }
}

// MARK: Downloads
final class DownloadsWatcher {
    static let shared = DownloadsWatcher()
    private var src: DispatchSourceFileSystemObject?
    private var known = Set<String>()
    func start() {
        guard let url = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return }
        known = Set((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? [])
        let fd = open(url.path, O_EVTONLY)
        if fd < 0 { return }
        let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        s.setEventHandler { [weak self] in
            guard let self = self else { return }
            if Background.paused { return }
            let now = Set((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? [])
            let new = now.subtracting(self.known)
            self.known = now
            guard P.bool("downloadAlerts") else { return }
            for n in new where !n.hasPrefix(".") && !n.hasSuffix(".crdownload") && !n.hasSuffix(".download") && !n.hasSuffix(".part") {
                NotchState.shared.post(IslandAlert(symbol: "arrow.down.circle.fill", tint: .blue, title: "Download complete", detail: n, duration: 3.5))
            }
        }
        s.setCancelHandler { close(fd) }
        s.resume()
        src = s
    }
}
