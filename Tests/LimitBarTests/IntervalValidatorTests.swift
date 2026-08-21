import Foundation
import Testing
@testable import limit_bar

@Suite("IntervalValidator")
struct IntervalValidatorTests {

    private let message = IntervalValidator.allowedRangeMessage

    private func assertFailure(_ raw: String) {
        guard case .failure(let error) = IntervalValidator.validate(raw) else {
            Issue.record("Expected validation failure for \(raw)")
            return
        }
        #expect(error.message == message)
    }

    @Test("Accepts an in-range numeric interval")
    func acceptsInRange() {
        #expect(try! IntervalValidator.validate("120").get() == 120)
        #expect(try! IntervalValidator.validate(" 300 ").get() == 300)
    }

    @Test("Accepts the boundary values 60 and 3600 seconds")
    func acceptsBoundaries() {
        #expect(try! IntervalValidator.validate("60").get() == 60)
        #expect(try! IntervalValidator.validate("3600").get() == 3600)
    }

    @Test("Rejects intervals below the 60-second floor with the allowed-range message")
    func rejectsBelowFloor() {
        assertFailure("10")
    }

    @Test("Rejects intervals above the 3600-second cap with the allowed-range message")
    func rejectsAboveCap() {
        assertFailure("7200")
    }

    @Test("Rejects non-numeric input with the allowed-range message")
    func rejectsNonNumeric() {
        for input in ["abc", "", "3o0"] {
            assertFailure(input)
        }
    }
}
