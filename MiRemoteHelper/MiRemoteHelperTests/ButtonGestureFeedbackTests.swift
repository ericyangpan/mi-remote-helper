import Testing
@testable import MiRemoteHelper

struct ButtonGestureFeedbackTests {
    @Test func doubleAppearsOnlyAfterSecondReleaseAndTripleStartsAnotherPair() {
        var feedback = ButtonGestureFeedback()
        for index in 0..<3 {
            let time = Double(index) * 0.1
            feedback.begin(.ok, at: time)
            let doubled = feedback.release(.ok, at: time + 0.04)
            #expect(doubled == (index == 1 ? .doubleTap : .tap))
        }
    }

    @Test func holdsAndExpiredPairsDoNotShowDouble() {
        for (firstRelease, secondDown, secondRelease) in [(0.5, 0.6, 0.65), (0.05, 0.125, 0.625), (0.05, 0.35, 0.4)] {
            var feedback = ButtonGestureFeedback()
            feedback.begin(.ok, at: 0)
            let first = feedback.release(.ok, at: firstRelease)
            feedback.begin(.ok, at: secondDown)
            let second = feedback.release(.ok, at: secondRelease)
            #expect(first == (firstRelease >= 0.5 ? .hold : .tap))
            #expect(second == (secondRelease - secondDown >= 0.5 ? .hold : .tap))
        }
    }

    @Test func otherButtonsVoiceAndCancellationBreakPairs() {
        for interruption in [RemoteButton.left, .microphone] {
            var feedback = ButtonGestureFeedback()
            feedback.begin(.ok, at: 0)
            _ = feedback.release(.ok, at: 0.04)
            feedback.begin(interruption, at: 0.1)
            _ = feedback.release(interruption, at: 0.14)
            feedback.begin(.ok, at: 0.2)
            let doubled = feedback.release(.ok, at: 0.24)
            #expect(doubled == .tap)
            feedback.cancel()
            feedback.begin(.ok, at: 0.3)
            let afterCancel = feedback.release(.ok, at: 0.34)
            #expect(afterCancel == .tap)
        }
        var feedback = ButtonGestureFeedback()
        for time in [0.0, 0.1] {
            feedback.begin(.microphone, at: time)
            let doubled = feedback.release(.microphone, at: time + 0.04)
            #expect(doubled == nil)
        }
    }
}
