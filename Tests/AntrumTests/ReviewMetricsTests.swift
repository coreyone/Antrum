import Testing
@testable import Antrum

@Suite("Review metrics")
struct ReviewMetricsTests {
    @Test
    func singularizesSpeakerAndBlockCounts() {
        let metrics = ReviewMetrics(speakerCount: "1", blockCount: "1", duration: "0m 07s")

        #expect(metrics.speakerCountLabel == "1 speaker")
        #expect(metrics.blockCountLabel == "1 block")
    }

    @Test
    func pluralizesCountsAboveOne() {
        let metrics = ReviewMetrics(speakerCount: "2", blockCount: "3", duration: "0m 07s")

        #expect(metrics.speakerCountLabel == "2 speakers")
        #expect(metrics.blockCountLabel == "3 blocks")
    }
}
