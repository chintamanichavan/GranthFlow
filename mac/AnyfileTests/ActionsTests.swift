import XCTest
@testable import Anyfile

final class ActionsTests: XCTestCase {
    private let kinds = ["pdf", "epub", "markdown", "text", "binary"]

    func testFiveActionsInFixedOrder() {
        XCTAssertEqual(DocumentAction.allCases.map(\.title), ["Contents", "Find", "Edit", "Mark", "Info"])
        XCTAssertEqual(Set(DocumentAction.allCases.map(\.symbol)).count, 5)
    }

    func testEveryEngineCommandHasExactlyOneRole() {
        XCTAssertTrue(CommandRole.changing.isDisjoint(with: CommandRole.reading))
        for kind in kinds {
            for c in Engine.commands(for: kind) {
                XCTAssertTrue(CommandRole.changing.contains(c.name) || CommandRole.reading.contains(c.name),
                              "\(kind): engine command '\(c.name)' is in neither list")
            }
        }
    }

    func testEveryListedCommandExistsInTheEngine() {
        let all = Set(kinds.flatMap { Engine.commands(for: $0).map(\.name) })
        XCTAssertEqual(CommandRole.changing.subtracting(all), [])
        XCTAssertEqual(CommandRole.reading.subtracting(all), [])
    }

    func testInfoAndEditSplitTheCommandsWithoutLoss() {
        for kind in kinds {
            let info = CommandRole.infoCommands(for: kind).map(\.name)
            let edit = CommandRole.editCommands(for: kind).map(\.name)
            XCTAssertEqual(info.first, "info", kind)
            XCTAssertFalse(info.contains("help"), kind)
            XCTAssertTrue(Set(info).isDisjoint(with: edit), kind)
            let everything = Set(Engine.commands(for: kind).map(\.name)).subtracting(["help"])
            XCTAssertEqual(Set(info + edit), everything, kind)
        }
    }

    func testEditCommandsReallyChangeTheFile() {
        let r = Engine.run(CommandRole.editCommands(for: "text").first { $0.name == "append" }!.name,
                           args: ["delta"], on: Data(Fixtures.text.utf8), name: "a.txt", kind: "text")
        XCTAssertNotNil(r.changedData)
        for name in CommandRole.infoCommands(for: "text").map(\.name) {
            XCTAssertNil(Engine.run(name, args: [], on: Data(Fixtures.text.utf8), name: "a.txt", kind: "text").changedData, name)
        }
    }
}
