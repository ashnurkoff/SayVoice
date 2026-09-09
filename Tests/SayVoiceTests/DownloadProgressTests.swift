import XCTest
@testable import SayVoice

final class DownloadProgressTests: XCTestCase {

    func testStatusTextWithSpeedAndEta() {
        XCTAssertEqual(DownloadProgress.statusText(fraction: 0.34, bytesPerSecond: 12_400_000, secondsLeft: 38), "34% · 12.4 MB/s · 38 s left")
    }

    func testStatusTextWithoutSpeedYet() {
        XCTAssertEqual(DownloadProgress.statusText(fraction: 0.02, bytesPerSecond: nil, secondsLeft: nil), "2%")
    }

    func testStatusTextMinutesAndHours() {
        XCTAssertEqual(DownloadProgress.statusText(fraction: 0.5, bytesPerSecond: 900_000, secondsLeft: 125), "50% · 0.9 MB/s · 2 min left")
        XCTAssertEqual(DownloadProgress.statusText(fraction: 0.1, bytesPerSecond: 100_000, secondsLeft: 4_000), "10% · 0.1 MB/s · 1 h 7 min left")
    }

    func testPercentDoesNotLoseAPointToFloatingPoint() {
        // 0.29 * 100 is 28.999… in binary: floored naively it reads "28%".
        XCTAssertEqual(DownloadProgress.statusText(fraction: 0.29, bytesPerSecond: nil, secondsLeft: nil), "29%")
        XCTAssertEqual(DownloadProgress.statusText(fraction: 0.57, bytesPerSecond: nil, secondsLeft: nil), "57%")
    }

    func testWholeHoursDropTheMinutes() {
        XCTAssertEqual(DownloadProgress.statusText(fraction: 0.1, bytesPerSecond: nil, secondsLeft: 3_570), "10% · 1 h left")
        XCTAssertEqual(DownloadProgress.statusText(fraction: 0.1, bytesPerSecond: nil, secondsLeft: 3_599), "10% · 1 h left")
        XCTAssertEqual(DownloadProgress.statusText(fraction: 0.1, bytesPerSecond: nil, secondsLeft: 3_660), "10% · 1 h 1 min left")
    }

    func testAbsurdTimeLeftIsOmitted() {
        // A stalled transfer can compute a time left of billions of seconds;
        // converting that to Int traps, so the part is dropped instead.
        XCTAssertEqual(DownloadProgress.statusText(fraction: 0.1, bytesPerSecond: 1, secondsLeft: 1e12), "10% · 0.0 MB/s")
    }

    func testStatusTextClampsFraction() {
        XCTAssertEqual(DownloadProgress.statusText(fraction: 1.4, bytesPerSecond: nil, secondsLeft: nil), "100%")
        XCTAssertEqual(DownloadProgress.statusText(fraction: -1, bytesPerSecond: nil, secondsLeft: nil), "0%")
    }
}
