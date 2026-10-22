import XCTest
import simd
@testable import Anyfile

final class PageGeometryTests: XCTestCase {
    private let aspect: Float = 1.4
    private let w = PageGeometry.columns + 1

    func testAtRestThePageLiesFlatOnTheNextOne() {
        for v in PageGeometry.vertices(progress: 0, aspect: aspect) {
            XCTAssertEqual(v.position.z, 0, accuracy: 1e-5)
            XCTAssertEqual(v.position.x, v.uv.x, accuracy: 1e-4)              // exactly where it was printed
            XCTAssertEqual(v.position.y, v.uv.y * aspect, accuracy: 1e-5)
            XCTAssertEqual(v.normal.z, 1, accuracy: 1e-4)                       // facing the reader
        }
    }

    func testWhenTurnedThePageLiesFlatOnTheOtherSide() {
        for v in PageGeometry.vertices(progress: 1, aspect: aspect) {
            XCTAssertEqual(v.position.z, 0, accuracy: 1e-4)
            XCTAssertEqual(v.position.x, -v.uv.x, accuracy: 1e-4)              // mirrored across the spine
            XCTAssertEqual(v.normal.z, -1, accuracy: 1e-3)                      // its back to the reader
        }
    }

    func testPaperBendsButDoesNotStretch() {
        for p: Float in [0.1, 0.3, 0.5, 0.7, 0.9] {
            let verts = PageGeometry.vertices(progress: p, aspect: aspect)
            for r in [0, PageGeometry.rows / 2, PageGeometry.rows] {
                var length: Float = 0
                for c in 1...PageGeometry.columns {
                    length += simd_distance(verts[r * w + c].position, verts[r * w + c - 1].position)
                }
                XCTAssertEqual(length, 1, accuracy: 1e-4, "row \(r) at \(p)")
            }
        }
    }

    func testMidTurnThePageStandsUpAndTheOuterEdgeLeads() {
        let verts = PageGeometry.vertices(progress: 0.35, aspect: aspect)
        let mid = PageGeometry.rows / 2
        XCTAssertGreaterThan(verts[mid * w + PageGeometry.columns].position.z, 0.3)      // lifted toward the reader
        let near = PageGeometry.angle(u: 0.1, rowProgress: 0.35), far = PageGeometry.angle(u: 1, rowProgress: 0.35)
        XCTAssertGreaterThan(far, near)                                                    // bent, not a rigid board
    }

    func testTheBottomCornerLeadsTheTop() {
        XCTAssertGreaterThan(PageGeometry.rowProgress(0.4, v: 0), PageGeometry.rowProgress(0.4, v: 1))
        XCTAssertEqual(PageGeometry.rowProgress(0, v: 0), 0)
        XCTAssertEqual(PageGeometry.rowProgress(1, v: 1), 1)
        let edge = PageGeometry.edge(progress: 0.3, aspect: aspect)
        XCTAssertLessThan(edge.first!.x, edge.last!.x)                                    // bottom edge further over
    }

    func testIndicesCoverEveryCellOnce() {
        let i = PageGeometry.indices()
        XCTAssertEqual(i.count, PageGeometry.columns * PageGeometry.rows * 6)
        XCTAssertEqual(i.max(), UInt32((PageGeometry.columns + 1) * (PageGeometry.rows + 1) - 1))
    }

    /// The sheet is rebuilt every frame. Prints the time.
    func testGeometrySpeed() {
        let start = Date()
        for k in 0..<60 { _ = PageGeometry.vertices(progress: Float(k) / 60, aspect: aspect) }
        let perFrame = Date().timeIntervalSince(start) / 60
        print(String(format: "page geometry per frame: %.2f ms", perFrame * 1000))
        XCTAssertLessThan(perFrame, 0.004)
    }
}
