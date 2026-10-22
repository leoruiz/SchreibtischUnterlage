import CoreGraphics
import Foundation
import ImageIO
import SchreibtischUnterlageCore
import XCTest
@testable import SchreibtischUnterlagePlatform

final class ManagedDisplayScreenshotTests: XCTestCase {
    func testSelectsOnlyTheManagedHardwareIdentity() throws {
        let identity = CGVirtualDisplayFactory().hardwareIdentity
        let displays = [
            display(id: 1, vendor: identity.vendorID + 1),
            display(id: 2, product: identity.productID + 1),
            display(id: 3, serial: identity.serialNumber + 1),
            display(id: 4),
        ]
        XCTAssertEqual(try ManagedDisplayScreenshot.selectDisplay(from: displays), 4)
    }

    func testNeverFallsBackToAnotherDisplay() {
        for displays in [[], [display(id: 1, vendor: 0)]] {
            XCTAssertThrowsError(try ManagedDisplayScreenshot.selectDisplay(from: displays)) { error in
                guard case ManagedDisplayScreenshotError.displayNotRunning = error else {
                    return XCTFail("Expected missing managed display, received \(error)")
                }
            }
        }
    }

    func testRejectsAmbiguousDisplays() {
        XCTAssertThrowsError(
            try ManagedDisplayScreenshot.selectDisplay(from: [display(id: 1), display(id: 2)])
        ) { error in
            guard case ManagedDisplayScreenshotError.multipleManagedDisplays = error else {
                return XCTFail("Expected ambiguous display error, received \(error)")
            }
        }
    }

    func testWritesFullResolutionPNGWithoutOverwriting() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("screen shot.png")
        let image = try makeImage()

        try ManagedDisplayScreenshot.writePNG(image, to: destination)

        let data = try Data(contentsOf: destination)
        XCTAssertEqual(Array(data.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(decoded.width, image.width)
        XCTAssertEqual(decoded.height, image.height)
        XCTAssertThrowsError(try ManagedDisplayScreenshot.writePNG(image, to: destination))
        XCTAssertEqual(try Data(contentsOf: destination), data)
    }

    func testRejectsMissingParentDirectory() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("missing/capture.png")
        XCTAssertThrowsError(try ManagedDisplayScreenshot.writePNG(makeImage(), to: destination))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testDoesNotFollowAnExistingSymlink() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("original.png")
        let link = directory.appendingPathComponent("link.png")
        let data = Data("unchanged".utf8)
        try data.write(to: original)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)

        XCTAssertThrowsError(try ManagedDisplayScreenshot.writePNG(makeImage(), to: link))
        XCTAssertEqual(try Data(contentsOf: original), data)
    }

    func testResultIsMachineReadable() throws {
        let result = ScreenshotResult(path: "/tmp/screen shot.png", displayID: 42, width: 1280, height: 720)
        let data = try JSONEncoder().encode(result)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["path", "displayID", "width", "height"])
        XCTAssertEqual(json["path"] as? String, result.path)
        XCTAssertEqual(json["displayID"] as? Int, 42)
        XCTAssertEqual(json["width"] as? Int, 1280)
        XCTAssertEqual(json["height"] as? Int, 720)
    }

    private func display(
        id: CGDirectDisplayID,
        vendor: UInt32? = nil,
        product: UInt32? = nil,
        serial: UInt32? = nil
    ) -> ScreenshotDisplay {
        let identity = CGVirtualDisplayFactory().hardwareIdentity
        return ScreenshotDisplay(
            displayID: id,
            identity: PhysicalDisplayIdentity(
                vendorID: vendor ?? identity.vendorID,
                modelID: product ?? identity.productID,
                serialNumber: serial ?? identity.serialNumber,
                unitNumber: 0
            )
        )
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    private func makeImage() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 32,
            height: 18,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 18))
        return try XCTUnwrap(context.makeImage())
    }
}
