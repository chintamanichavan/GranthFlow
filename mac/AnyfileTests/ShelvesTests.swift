import XCTest
@testable import Anyfile

@MainActor
final class ShelvesTests: XCTestCase {
    private var dir: URL!
    private var lib: Library!
    private var shelves: Shelves!
    private var defaults: UserDefaults!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("anyfile-shelves-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        lib = Library(file: dir.appendingPathComponent("l.json"))
        defaults = UserDefaults(suiteName: "anyfile-shelves-\(UUID().uuidString)")!
        shelves = Shelves(library: lib, defaults: defaults)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func file(_ name: String) -> URL {
        let url = dir.appendingPathComponent(name)
        try! Data("x".utf8).write(to: url)
        lib.recordOpened(url, kind: "text")
        return url
    }

    func testNamesAreTrimmedUniqueAndKept() {
        XCTAssertEqual(shelves.create("  Reading "), "Reading")
        XCTAssertNil(shelves.create("reading"))                              // taken, whatever the case
        XCTAssertNil(shelves.create("   "))
        shelves.create("Work")
        XCTAssertEqual(Shelves(library: lib, defaults: defaults).names, ["Reading", "Work"])
        XCTAssertNotNil(shelves.available("Reading", except: "Reading"))     // renaming to itself is allowed
    }

    func testAFileCanSitOnSeveralShelves() {
        shelves.create("Reading")
        shelves.create("Work")
        let a = file("a.txt"), b = file("b.txt")
        lib.put(a, on: "Reading")
        lib.put(a, on: "Work")
        lib.put(a, on: "Work")                                                // once only
        lib.put(b, on: "Work")
        XCTAssertEqual(shelves.files(on: "Reading").map(\.name), ["a.txt"])
        XCTAssertEqual(Set(shelves.files(on: "Work").map(\.name)), ["a.txt", "b.txt"])
        XCTAssertEqual(lib.entry(for: a)?.shelves, ["Reading", "Work"])
        lib.take(a, off: "Reading")
        XCTAssertEqual(shelves.files(on: "Reading"), [])
        XCTAssertEqual(Library(file: dir.appendingPathComponent("l.json")).entry(for: b)?.shelves, ["Work"])   // saved
    }

    func testRenamingAndDeletingFollowThroughToTheFiles() {
        shelves.create("Wrk")
        let a = file("a.txt")
        lib.put(a, on: "Wrk")
        shelves.rename("Wrk", to: "Work")
        XCTAssertEqual(shelves.names, ["Work"])
        XCTAssertEqual(lib.entry(for: a)?.shelves, ["Work"])
        shelves.delete("Work")
        XCTAssertEqual(shelves.names, [])
        XCTAssertNil(lib.entry(for: a)?.shelves)                               // the file stays in the library
        XCTAssertNotNil(lib.entry(for: a))
    }

    func testRenamingOntoAnotherShelfIsRefused() {
        shelves.create("Home")
        shelves.create("Work")
        shelves.rename("Work", to: "home")
        XCTAssertEqual(shelves.names, ["Home", "Work"])
    }
}
