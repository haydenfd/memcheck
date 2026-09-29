import Testing
@testable import Memcheck

struct MemoryHealthTests {
    @Test func warningNeedsTwentySeconds() {
        var evaluator = MemoryHealthEvaluator()
        let start = ContinuousClock.now
        #expect(evaluator.observe(.warning, at: start) == .normal)
        #expect(evaluator.observe(.warning, at: start.advanced(by: .seconds(19))) == .normal)
        #expect(evaluator.observe(.warning, at: start.advanced(by: .seconds(20))) == .warning)
    }

    @Test func recoveryNeedsThirtyContinuousSeconds() {
        var evaluator = MemoryHealthEvaluator()
        let start = ContinuousClock.now
        _ = evaluator.observe(.warning, at: start)
        _ = evaluator.observe(.warning, at: start.advanced(by: .seconds(20)))
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
        _ = evaluator.observe(.warning, at: start)
        _ = evaluator.observe(.normal, at: start.advanced(by: .seconds(10)))
        #expect(evaluator.observe(.warning, at: start.advanced(by: .seconds(11))) == .normal)
        #expect(evaluator.observe(.warning, at: start.advanced(by: .seconds(30))) == .normal)
        #expect(evaluator.observe(.warning, at: start.advanced(by: .seconds(31))) == .warning)
    }

    @Test func swapGrowthDoesNotMakeHistoricalSwapAWarning() {
        var monitor = MemoryMonitor()
        let start = ContinuousClock.now
        let snapshot = MemorySnapshot(
            totalBytes: 16_000_000_000, usedBytes: 12_000_000_000,
            availableBytes: 4_000_000_000, freeBytes: 1_000_000_000,
            compressedBytes: 2_000_000_000, wiredBytes: 2_000_000_000,
            swapUsedBytes: 3_000_000_000, systemPressure: .normal
        )
        #expect(monitor.update(snapshot, at: start) == .normal)
        #expect(monitor.update(snapshot, at: start.advanced(by: .seconds(30))) == .normal)
    }

    @Test func nativeReaderReturnsPlausiblePhysicalMemory() async throws {
        let first = try await MemoryReader.sample()
        #expect(first.totalBytes > 0)
        #expect(first.usedBytes + first.availableBytes == first.totalBytes)
        #expect(first.freeBytes <= first.availableBytes)
        let second = try await MemoryReader.sample()
        #expect(second.totalBytes == first.totalBytes)
    }
}
