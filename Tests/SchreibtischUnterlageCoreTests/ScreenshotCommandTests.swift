import XCTest
@testable import SchreibtischUnterlageCore

final class ScreenshotCommandTests: XCTestCase {
    func testParsesScreenshotPath() throws {
        for path in ["capture.png", "/tmp/screen shot.png", "./-capture.PNG"] {
            XCTAssertEqual(
                try ScreenshotCommand.parse(["--screenshot", path]),
                .capture(path: path)
            )
            XCTAssertEqual(
                try ScreenshotCommand.parse(["--screenshot=\(path)"]),
                .capture(path: path)
            )
        }
    }

    func testHelpDoesNotStartTheApp() throws {
        XCTAssertEqual(try ScreenshotCommand.parse(["--help"]), .help)
    }

    func testLeavesApplicationAndProbeArgumentsAlone() throws {
        for arguments in [[], ["--display-probe"], ["--preview-probe-seconds=5"]] {
            XCTAssertNil(try ScreenshotCommand.parse(arguments))
        }
    }

    func testRejectsMissingPathsAndConflictingOptions() {
        for arguments in [
            ["--screenshot"],
            ["--screenshot="],
            ["--screenshot", ""],
            ["--screenshot", "--help"],
            ["--screenshot", "bad\0.png"],
            ["--screenshot", "capture.png", "--display-probe"],
            ["--preview-probe-seconds=5", "--screenshot=capture.png"],
            ["--screenshot=capture.png", "--screenshot=other.png"],
            ["--screenshot-invalid"],
            ["--help", "--display-probe"],
        ] {
            XCTAssertThrowsError(try ScreenshotCommand.parse(arguments)) { error in
                guard case ScreenshotCommandError.invalidArguments = error else {
                    return XCTFail("Expected invalid arguments, received \(error)")
                }
            }
        }
    }

    func testRejectsNonPNGDestinations() {
        for path in ["capture", "capture.jpg", "capture.png/"] {
            XCTAssertThrowsError(try ScreenshotCommand.parse(["--screenshot", path])) { error in
                guard case ScreenshotCommandError.requiresPNG = error else {
                    return XCTFail("Expected PNG extension error, received \(error)")
                }
            }
        }
    }
}
