import XCTest
import simd
@testable import HDRICreator

final class SphereLayoutTests: XCTestCase {
    func testHas28UniqueTargetsWithExpectedStructure() {
        let l = SphereLayout()
        XCTAssertEqual(l.targets.count, 28)
        func n(_ k: TargetKind) -> Int { l.targets.filter { $0.kind == k }.count }
        XCTAssertEqual(n(.zenith), 1); XCTAssertEqual(n(.nadir), 1)
        XCTAssertEqual(n(.upperRing), 8); XCTAssertEqual(n(.middleRing), 8); XCTAssertEqual(n(.lowerRing), 8)
        XCTAssertEqual(n(.supplemental), 2)
        for i in 0..<28 { for j in (i + 1)..<28 where j < 28 {
            XCTAssertGreaterThan(simd_distance(l.targets[i].direction, l.targets[j].direction), 0.05, "targets \(i) and \(j) coincide")
        } }
    }
    func testFullSphereCoverage() {
        for h in [55.0, 67.4, 75.0] {
            let l = SphereLayout(horizontalFOV: h)
            let c = l.coverage(of: Set(0..<28), samples: SphereLayout.fibonacciSphere(20000))
            XCTAssertGreaterThan(c, 0.995, "FOV \(h): coverage \(c)")
        }
    }
    func testCoverageGrowsAsTargetsAreCaptured() {
        let l = SphereLayout(); let s = SphereLayout.fibonacciSphere(4000)
        XCTAssertLessThan(l.coverage(of: [0], samples: s), l.coverage(of: Set(0..<10), samples: s))
    }
}
