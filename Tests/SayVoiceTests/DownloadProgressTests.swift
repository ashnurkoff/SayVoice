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

    func testStatusTextClampsFraction() {
        XCTAssertEqual(DownloadProgress.statusText(fraction: 1.4, bytesPerSecond: nil, secondsLeft: nil), "100%")
        XCTAssertEqual(DownloadProgress.statusText(fraction: -1, bytesPerSecond: nil, secondsLeft: nil), "0%")
    }
}
