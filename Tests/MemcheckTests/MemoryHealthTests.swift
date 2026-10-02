import Testing
@testable import Memcheck

struct MemoryHealthTests {
    @Test func warningIsImmediate() {
        var evaluator = MemoryHealthEvaluator()
        let start = ContinuousClock.now
        #expect(evaluator.observe(.warning, at: start) == .warning)
    }

    @Test func recoveryNeedsThirtyContinuousSeconds() {
        var evaluator = MemoryHealthEvaluator()
        let start = ContinuousClock.now
        _ = evaluator.observe(.warning, at: start)
        #expect(evaluator.observe(.normal, at: start.advanced(by: .seconds(21))) == .warning)
        #expect(evaluator.observe(.warning, at: start.advanced(by: .seconds(40))) == .warning)
        #expect(evaluator.observe(.normal, at: start.advanced(by: .seconds(41))) == .warning)
        #expect(evaluator.observe(.normal, at: start.advanced(by: .seconds(71))) == .normal)
    }

    @Test func criticalIsImmediateAndRecoveryPersists() {
        var evaluator = MemoryHealthEvaluator()
        let start = ContinuousClock.now
        #expect(evaluator.observe(.critical, at: start) == .critical)
        #expect(evaluator.observe(.warning, at: start.advanced(by: .seconds(1))) == .critical)
        #expect(evaluator.observe(.warning, at: start.advanced(by: .seconds(31))) == .warning)
    }

    @Test func briefWarningResetsOnHealthySample() {
        var evaluator = MemoryHealthEvaluator()
        let start = ContinuousClock.now
        #expect(evaluator.observe(.warning, at: start) == .warning)
        #expect(evaluator.observe(.normal, at: start.advanced(by: .seconds(10))) == .warning)
        #expect(evaluator.observe(.warning, at: start.advanced(by: .seconds(11))) == .warning)
        #expect(evaluator.observe(.normal, at: start.advanced(by: .seconds(12))) == .warning)
        #expect(evaluator.observe(.normal, at: start.advanced(by: .seconds(41))) == .warning)
        #expect(evaluator.observe(.normal, at: start.advanced(by: .seconds(42))) == .normal)
    }

    @Test func swapGrowthDoesNotOverrideNormalSystemPressure() {
        var monitor = MemoryMonitor()
        let start = ContinuousClock.now
        let snapshot = MemorySnapshot(
            totalBytes: 16_000_000_000, usedBytes: 12_000_000_000,
            availableBytes: 4_000_000_000, freeBytes: 1_000_000_000,
            compressedBytes: 2_000_000_000, wiredBytes: 2_000_000_000,
            swapUsedBytes: 3_000_000_000, systemPressure: .normal
        )
        #expect(monitor.update(snapshot, at: start) == .normal)
        let growingSwap = MemorySnapshot(
            totalBytes: snapshot.totalBytes, usedBytes: snapshot.usedBytes,
            availableBytes: snapshot.availableBytes, freeBytes: snapshot.freeBytes,
            compressedBytes: snapshot.compressedBytes, wiredBytes: snapshot.wiredBytes,
            swapUsedBytes: snapshot.swapUsedBytes + 128 * 1_048_576, systemPressure: .normal
        )
        #expect(monitor.update(growingSwap, at: start.advanced(by: .seconds(30))) == .normal)
    }

    @Test func pressureCanWarnWithMoreAvailableMemory() {
        var monitor = MemoryMonitor()
        let start = ContinuousClock.now
        let lowAvailable = MemorySnapshot(
            totalBytes: 16_000_000_000, usedBytes: 12_800_000_000,
            availableBytes: 3_200_000_000, freeBytes: 1_000_000_000,
            compressedBytes: 2_000_000_000, wiredBytes: 2_000_000_000,
            swapUsedBytes: 0, systemPressure: .normal
        )
        let higherAvailable = MemorySnapshot(
            totalBytes: 16_000_000_000, usedBytes: 12_000_000_000,
            availableBytes: 4_000_000_000, freeBytes: 1_000_000_000,
            compressedBytes: 2_000_000_000, wiredBytes: 2_000_000_000,
            swapUsedBytes: 0, systemPressure: .warning
        )
        #expect(monitor.update(lowAvailable, at: start) == .normal)
        #expect(monitor.update(higherAvailable, at: start.advanced(by: .seconds(1))) == .warning)
        #expect(monitor.update(higherAvailable, at: start.advanced(by: .seconds(21))) == .warning)
    }

    @Test func nativeReaderReturnsPlausiblePhysicalMemory() async throws {
        let first = try await MemoryReader.sample()
        #expect(first.totalBytes > 0)
        #expect(first.usedBytes + first.availableBytes == first.totalBytes)
        #expect(first.freeBytes <= first.availableBytes)
        let second = try await MemoryReader.sample()
        #expect(second.totalBytes == first.totalBytes)
    }

    @Test func helperProcessesBelongToOuterApp() {
        let helper = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper"
        #expect(AppMemoryReader.appBundlePath(for: helper) == "/Applications/Google Chrome.app")
        #expect(AppMemoryReader.appBundlePath(for: "/usr/bin/python3") == nil)
    }

    @Test func appMemoryChangeUsesFirstReadingUntilMenuReopens() {
        var trend = AppMemoryTrend()
        let first = AppMemory(name: "Firefox", bytes: 100_000_000, bundlePath: "/Applications/Firefox.app")
        #expect(trend.change(for: first) == 0)
        #expect(trend.change(for: AppMemory(name: first.name, bytes: 150_000_000,
            bundlePath: first.bundlePath)) == 50_000_000)
        #expect(trend.change(for: AppMemory(name: first.name, bytes: 90_000_000,
            bundlePath: first.bundlePath)) == -10_000_000)
        trend.reset()
        #expect(trend.change(for: first) == 0)
    }
}
