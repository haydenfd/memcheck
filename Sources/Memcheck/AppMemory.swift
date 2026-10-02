import Darwin
import Foundation

struct AppMemory: Sendable {
    let name: String
    let bytes: UInt64
    let bundlePath: String
}

struct AppMemoryTrend {
    private var startingBytes: [String: UInt64] = [:]

    mutating func reset() {
        startingBytes.removeAll()
    }

    mutating func change(for app: AppMemory) -> Int64 {
        let start = startingBytes[app.bundlePath] ?? app.bytes
        startingBytes[app.bundlePath] = start
        return Int64(clamping: app.bytes) - Int64(clamping: start)
    }
}

enum AppMemoryReader {
    @concurrent
    static func topFive() async -> [AppMemory] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let bytes = Int32(pids.count * MemoryLayout<pid_t>.stride)
        let found = proc_listallpids(&pids, bytes)
        guard found > 0 else { return [] }

        var totals: [String: UInt64] = [:]
        for pid in pids.prefix(Int(found)) where pid > 0 {
            var usage = rusage_info_v2()
            // Darwin declares this output buffer as void ** even though it writes rusage_info_v2.
            let status = withUnsafeMutablePointer(to: &usage) { pointer in
                proc_pid_rusage(pid, RUSAGE_INFO_V2,
                    UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: rusage_info_t?.self))
            }
            guard status == 0 else { continue }
            var path = [CChar](repeating: 0, count: 4096)
            guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { continue }
            let executablePath = String(decoding: path.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
            guard let bundlePath = appBundlePath(for: executablePath) else { continue }
            totals[bundlePath, default: 0] += usage.ri_phys_footprint
        }
        return totals.sorted { $0.value > $1.value }.prefix(5).map { path, bytes in
            AppMemory(name: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
                bytes: bytes, bundlePath: path)
        }
    }

    static func appBundlePath(for executablePath: String) -> String? {
        guard let range = executablePath.range(of: ".app/") else { return nil }
        return String(executablePath[..<range.lowerBound]) + ".app"
    }
}
