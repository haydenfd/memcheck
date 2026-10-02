import Darwin
import Foundation

struct MemorySnapshot: Sendable {
    let totalBytes: UInt64
    let usedBytes: UInt64
    let availableBytes: UInt64
    let freeBytes: UInt64
    let compressedBytes: UInt64
    let wiredBytes: UInt64
    let swapUsedBytes: UInt64
    let systemPressure: MemoryHealthState
}

enum MemoryReadError: Error {
    case hostStatistics(kern_return_t)
    case pageSize(kern_return_t)
    case systemValue(String)
    case unknownPressure(Int32)
}

enum MemoryReader {
    @concurrent
    static func sample() async throws -> MemorySnapshot {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { throw MemoryReadError.hostStatistics(status) }

        var pageSize: vm_size_t = 0
        let pageStatus = host_page_size(mach_host_self(), &pageSize)
        guard pageStatus == KERN_SUCCESS else { throw MemoryReadError.pageSize(pageStatus) }

        var total: UInt64 = 0
        var totalSize = MemoryLayout<UInt64>.size
        guard sysctlbyname("hw.memsize", &total, &totalSize, nil, 0) == 0 else {
            throw MemoryReadError.systemValue("hw.memsize")
        }

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 else {
            throw MemoryReadError.systemValue("vm.swapusage")
        }

        var pressure: Int32 = 0
        var pressureSize = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &pressure, &pressureSize, nil, 0) == 0 else {
            throw MemoryReadError.systemValue("kern.memorystatus_vm_pressure_level")
        }
        let systemPressure: MemoryHealthState = switch pressure {
        case 1: .normal
        case 2: .warning
        case 4: .critical
        default: throw MemoryReadError.unknownPressure(pressure)
        }

        let size = UInt64(pageSize)
        let free = UInt64(stats.free_count) * size
        // Inactive and speculative pages can be reclaimed. This is an estimate,
        // not Activity Monitor's app-memory figure; compressed pages remain used.
        let available = min(total, free + (UInt64(stats.inactive_count) + UInt64(stats.speculative_count)) * size)
        return MemorySnapshot(
            totalBytes: total,
            usedBytes: total - available,
            availableBytes: available,
            freeBytes: free,
            compressedBytes: UInt64(stats.compressor_page_count) * size,
            wiredBytes: UInt64(stats.wire_count) * size,
            swapUsedBytes: swap.xsu_used,
            systemPressure: systemPressure
        )
    }
}

struct MemoryMonitor {
    private(set) var evaluator = MemoryHealthEvaluator()

    mutating func update(_ snapshot: MemorySnapshot, at now: ContinuousClock.Instant) -> MemoryHealthState {
        evaluator.observe(snapshot.systemPressure, at: now)
    }
}
