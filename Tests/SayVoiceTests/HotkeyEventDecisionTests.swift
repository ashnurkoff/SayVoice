import CoreGraphics
import XCTest
@testable import SayVoice

/// The event tap consumes keyboard events system-wide. Getting this wrong
/// once made the letter "D" stop typing in every app, so the decision
/// function is pure and tested here.
final class HotkeyEventDecisionTests: XCTestCase {
    private let ctrlOptCmd = CGEventFlags([.maskControl, .maskAlternate, .maskCommand]).rawValue
    private let shift = CGEventFlags.maskShift.rawValue

    func testPlainLetterPassesThrough() {
        let down = HotkeyEventDecision.decide(isKeyDown: true, isAutorepeat: false, flags: 0, required: ctrlOptCmd, wasDown: false)
        XCTAssertFalse(down.consume); XCTAssertFalse(down.handle)
        let up = HotkeyEventDecision.decide(isKeyDown: false, isAutorepeat: false, flags: 0, required: ctrlOptCmd, wasDown: down.isDown)
        XCTAssertFalse(up.consume, "release of a plain letter must reach the system")
    }

    func testPlainAutorepeatPassesThrough() {
        let r = HotkeyEventDecision.decide(isKeyDown: true, isAutorepeat: true, flags: 0, required: ctrlOptCmd, wasDown: false)
        XCTAssertFalse(r.consume)
    }

    func testHotkeyPressIsConsumedAndHandled() {
        let d = HotkeyEventDecision.decide(isKeyDown: true, isAutorepeat: false, flags: ctrlOptCmd, required: ctrlOptCmd, wasDown: false)
        XCTAssertTrue(d.consume); XCTAssertTrue(d.handle); XCTAssertTrue(d.isDown)
    }

    func testHotkeyAutorepeatIsConsumedButNotHandled() {
        let r = HotkeyEventDecision.decide(isKeyDown: true, isAutorepeat: true, flags: ctrlOptCmd, required: ctrlOptCmd, wasDown: true)
        XCTAssertTrue(r.consume); XCTAssertFalse(r.handle)
    }

    func testReleaseIsHandledEvenIfModifiersAlreadyUp() {
        let up = HotkeyEventDecision.decide(isKeyDown: false, isAutorepeat: false, flags: 0, required: ctrlOptCmd, wasDown: true)
        XCTAssertTrue(up.consume); XCTAssertTrue(up.handle); XCTAssertFalse(up.isDown)
    }

    func testExtraModifierIsNotTheHotkey() {
        let d = HotkeyEventDecision.decide(isKeyDown: true, isAutorepeat: false, flags: ctrlOptCmd | shift, required: ctrlOptCmd, wasDown: false)
        XCTAssertFalse(d.consume)
    }
}
