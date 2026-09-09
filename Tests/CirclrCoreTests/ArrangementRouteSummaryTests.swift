import XCTest
@testable import CirclrCore

final class ArrangementRouteSummaryTests: XCTestCase {
    private func fixture() -> Project { CoreTests().song() }
    private func assertMatchesCompiler(_ project: Project, file: StaticString = #filePath, line: UInt = #line) throws {
        let before = project, summary = ArrangementRouteSummary.make(project.active)
        let plan = try ArrangementCompiler.compile(project)
        var seen = Set<ID>()
        let order = plan.occurrences.compactMap { seen.insert($0.use.id).inserted ? $0.use.id : nil }
        XCTAssertNil(summary.error, file: file, line: line)
        XCTAssertEqual(summary.steps.map(\.id), order, file: file, line: line)
        XCTAssertEqual(summary.totalOccurrences, plan.occurrences.count, file: file, line: line)
        for step in summary.steps {
            XCTAssertEqual(step.repeatCount, plan.occurrences.filter { $0.use.id == step.id }.count, file: file, line: line)
        }
        XCTAssertEqual(summary.excluded.map(\.id), project.active.uses.filter { !seen.contains($0.id) }.map(\.id), file: file, line: line)
        XCTAssertEqual(project, before, file: file, line: line)
    }
    func testPlaybackOrderRepeatsAndTransitionsMatchCompilerNotStorageOrder() throws {
        var p = fixture()
        p.arrangements[0].uses[0].repeatCount = 3
        p.arrangements[0].edges[0].transition.mode = .overlap
        p.arrangements[0].edges[0].transition.length = 1
        p.arrangements[0].uses.reverse()
        try assertMatchesCompiler(p)
        XCTAssertNotEqual(ArrangementRouteSummary.make(p.active).steps.map(\.id), p.active.uses.map(\.id))
    }
    func testSingleEdgeIgnoresStaleChoiceAndEndOverridesConnections() throws {
        var p = fixture(); let start = p.active.startID!
        p.arrangements[0].chosenEdges[start] = "stale"
        try assertMatchesCompiler(p)
        p.arrangements[0].uses[0].isEnd = true
        // Invalid off-route repeat and source are intentionally not inspected.
        p.arrangements[0].uses[1].repeatCount = 0
        p.arrangements[0].uses[1].sectionID = "missing"
        try assertMatchesCompiler(p)
        XCTAssertEqual(ArrangementRouteSummary.make(p.active).excluded.count, 1)
    }
    func testChosenBranchMatchesCompilerAndPreservesExcludedStorageOrder() throws {
        var p = fixture(); let start = p.active.startID!
        let third = p.addSection(name: "대안", at: Point(), bars: 1)
        try ProjectEditing.connect(from: start, to: third, in: &p)
        p.arrangements[0].chosenEdges[start] = p.active.edges.first { $0.to == third }!.id
        try assertMatchesCompiler(p)
        XCTAssertEqual(ArrangementRouteSummary.make(p.active).steps.last?.id, third)
    }
    func testInvalidTopologyMatchesCompilerAndNeverReturnsPartialRoute() throws {
        let valid = fixture()
        var noStart = valid; noStart.arrangements[0].startID = nil
        var duplicate = valid; duplicate.arrangements[0].uses.append(duplicate.active.uses[0])
        var missing = valid; missing.arrangements[0].edges[0].to = "missing"
        var cycle = valid
        cycle.arrangements[0].uses[1].isEnd = false
        cycle.arrangements[0].edges.append(FlowEdge(from: cycle.active.uses[1].id, to: cycle.active.uses[0].id))
        var repeatInvalid = valid; repeatInvalid.arrangements[0].uses[1].repeatCount = 257
        var branch = valid
        branch.arrangements[0].edges.append(FlowEdge(from: branch.active.uses[0].id, to: branch.active.uses[1].id))
        var noNext = valid; noNext.arrangements[0].edges = []
        for p in [noStart, duplicate, missing, cycle, repeatInvalid, branch, noNext] {
            let before = p, summary = ArrangementRouteSummary.make(p.active)
            XCTAssertNotNil(summary.error); XCTAssertTrue(summary.steps.isEmpty); XCTAssertTrue(summary.excluded.isEmpty)
            XCTAssertEqual(summary.totalOccurrences, 0)
            XCTAssertThrowsError(try ArrangementCompiler.compile(p)) { XCTAssertEqual($0.localizedDescription, summary.error) }
            XCTAssertEqual(p, before)
        }
    }
    func testOnlyUseStopsBeforeBadOutgoingAndEmptyArrangementStillWins() throws {
        var p = fixture(); let first = p.active.uses[0].id
        p.arrangements[0].edges = []
        let plan = try ArrangementCompiler.compile(p, onlyUseID: first)
        XCTAssertEqual(plan.occurrences.map(\.use.id), [first])
        XCTAssertNotNil(ArrangementRouteSummary.make(p.active).error)
        p.arrangements[0].uses = []
        XCTAssertTrue(try ArrangementCompiler.compile(p, onlyUseID: "missing").occurrences.isEmpty)
        let summary = ArrangementRouteSummary.make(p.active)
        XCTAssertNil(summary.error); XCTAssertTrue(summary.steps.isEmpty); XCTAssertTrue(summary.excluded.isEmpty)
        XCTAssertEqual(summary.totalOccurrences, 0)
    }
    func testMusicErrorStillPrecedesOutgoingRouteErrorAndSummaryIsTopologyOnly() throws {
        var p = fixture()
        p.arrangements[0].uses[0].gain = .nan
        p.arrangements[0].edges = []
        XCTAssertThrowsError(try ArrangementCompiler.compile(p)) { XCTAssertEqual($0.localizedDescription, "서클 gain 값을 확인하세요") }
        XCTAssertTrue(ArrangementRouteSummary.make(p.active).error?.contains("다음 연결") == true)
        p.arrangements[0].uses[0].isEnd = true
        XCTAssertNil(ArrangementRouteSummary.make(p.active).error)
        XCTAssertThrowsError(try ArrangementCompiler.compile(p))
    }
    func testSummaryBoundsOccurrencesWithoutExpandingRepeats() {
        var a = Arrangement(), previous: ID?
        for index in 0..<40 {
            var use = SectionUse(sectionID: "shared", name: "섹션 \(index)")
            use.repeatCount = 250
            if let previous {
                a.uses[a.uses.count - 1].isEnd = false
                a.edges.append(FlowEdge(from: previous, to: use.id))
            } else { a.startID = use.id }
            a.uses.append(use); previous = use.id
        }
        XCTAssertEqual(ArrangementRouteSummary.make(a).totalOccurrences, 10_000)
        a.uses[39].repeatCount = 251
        let before = a, summary = ArrangementRouteSummary.make(a)
        XCTAssertNotNil(summary.error); XCTAssertTrue(summary.steps.isEmpty); XCTAssertTrue(summary.excluded.isEmpty)
        XCTAssertEqual(a, before)
    }
}
