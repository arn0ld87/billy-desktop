import XCTest
@testable import BillyCore

final class SoundPolicyTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testReactionsPlayAtFullVolume() {
        var policy = SoundPolicy(level: .reactions, volume: 0.6)
        XCTAssertEqual(policy.volume(for: .bark, isReaction: true, microphoneInUse: false, now: t0), 0.6)
        // „Nur Reaktionen“: nichts aus Eigeninitiative
        XCTAssertNil(policy.volume(for: .snore, isReaction: false, microphoneInUse: false, now: t0))
    }

    func testAmbientIsQuieterAndRare() throws {
        var policy = SoundPolicy(level: .lively, volume: 0.6)
        let first = try XCTUnwrap(policy.volume(for: .snore, isReaction: false, microphoneInUse: false, now: t0))
        XCTAssertEqual(first, 0.6 * 0.33, accuracy: 0.001)
        XCTAssertNil(policy.volume(for: .pant, isReaction: false, microphoneInUse: false, now: t0.addingTimeInterval(60)))
        XCTAssertNotNil(policy.volume(for: .pant, isReaction: false, microphoneInUse: false, now: t0.addingTimeInterval(151)))
        // Reaktionen sind vom Intervall nicht betroffen
        XCTAssertEqual(policy.volume(for: .bark, isReaction: true, microphoneInUse: false, now: t0.addingTimeInterval(152)), 0.6)
    }

    func testSilentWhenOffMutedOrMicrophoneInUse() {
        var off = SoundPolicy(level: .off, volume: 1)
        XCTAssertNil(off.volume(for: .bark, isReaction: true, microphoneInUse: false, now: t0))
        var muted = SoundPolicy(level: .lively, volume: 0)
        XCTAssertNil(muted.volume(for: .bark, isReaction: true, microphoneInUse: false, now: t0))
        var call = SoundPolicy(level: .lively, volume: 1)
        XCTAssertNil(call.volume(for: .bark, isReaction: true, microphoneInUse: true, now: t0))
        // Ein unterdrücktes Geräusch verbraucht das Intervall nicht
        XCTAssertNil(call.volume(for: .snore, isReaction: false, microphoneInUse: true, now: t0))
        XCTAssertNotNil(call.volume(for: .snore, isReaction: false, microphoneInUse: false, now: t0.addingTimeInterval(1)))
    }
}
