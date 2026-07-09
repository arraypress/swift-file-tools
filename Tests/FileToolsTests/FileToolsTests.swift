//
//  FileToolsTests.swift
//  Tests for SwiftFileTools
//
//  Created by David Sherlock on 7/9/26.
//

import XCTest
@testable import FileTools

final class FileToolsTests: XCTestCase {

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FileToolsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tmp { try? FileManager.default.removeItem(at: tmp) }
    }

    // MARK: - Helpers

    private func write(_ contents: String, to relativePath: String) throws {
        let url = tmp.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func mkdir(_ relativePath: String) throws {
        try FileManager.default.createDirectory(
            at: tmp.appendingPathComponent(relativePath), withIntermediateDirectories: true)
    }

    // MARK: - FileTree

    func testFileTreeAsciiRendersStructure() throws {
        try write("print(1)\n", to: "Sources/main.swift")
        try write("# hi\n", to: "README.md")
        try mkdir("Sources/Empty")

        let tree = FileTree.ascii(of: tmp)
        let lines = tree.split(separator: "\n").map(String.init)

        // Root header ends in a slash.
        XCTAssertEqual(lines.first, tmp.lastPathComponent + "/")
        // Directories are rendered with a trailing slash, files without.
        XCTAssertTrue(tree.contains("Sources/"))
        XCTAssertTrue(tree.contains("main.swift"))
        XCTAssertTrue(tree.contains("README.md"))
        XCTAssertTrue(tree.contains("Empty/"))
        // Branch glyphs are present.
        XCTAssertTrue(tree.contains("├──") || tree.contains("└──"))
    }

    func testFileTreeSkipsNoiseDirectories() throws {
        try write("code\n", to: "keep.txt")
        try write("junk\n", to: ".git/config")
        try write("dep\n", to: "node_modules/pkg/index.js")

        let tree = FileTree.ascii(of: tmp)
        XCTAssertTrue(tree.contains("keep.txt"))
        XCTAssertFalse(tree.contains(".git"))
        XCTAssertFalse(tree.contains("node_modules"))
    }

    func testFileTreeDirectoriesListedBeforeFiles() throws {
        try write("a\n", to: "afile.txt")
        try mkdir("zdir")

        let tree = FileTree.ascii(of: tmp)
        let dirIndex = tree.range(of: "zdir/")!.lowerBound
        let fileIndex = tree.range(of: "afile.txt")!.lowerBound
        XCTAssertLessThan(dirIndex, fileIndex, "directories should be listed before files")
    }

    func testFileTreeRespectsMaxDepth() throws {
        try write("deep\n", to: "a/b/c/deep.txt")
        let shallow = FileTree.ascii(of: tmp, maxDepth: 1)
        XCTAssertFalse(shallow.contains("deep.txt"))
        let deep = FileTree.ascii(of: tmp, maxDepth: 8)
        XCTAssertTrue(deep.contains("deep.txt"))
    }

    // MARK: - ProjectSearch

    func testProjectSearchFindsMatch() throws {
        try write("let x = 1\nhello world\nlet y = 2\n", to: "a.swift")
        try write("nothing here\n", to: "b.swift")

        let results = ProjectSearch.search(
            query: "hello", in: tmp, caseSensitive: false, regex: false, isCancelled: { false })

        XCTAssertEqual(results.count, 1)
        let file = try XCTUnwrap(results.first)
        XCTAssertEqual(file.url.lastPathComponent, "a.swift")
        XCTAssertEqual(file.matches.count, 1)
        let match = try XCTUnwrap(file.matches.first)
        XCTAssertEqual(match.line, 2)
        XCTAssertEqual(match.lineText, "hello world")
        XCTAssertEqual(match.range.location, 0)
        XCTAssertEqual(match.range.length, 5)
    }

    func testProjectSearchIsCaseInsensitiveByDefault() throws {
        try write("HELLO there\n", to: "a.txt")
        let insensitive = ProjectSearch.search(
            query: "hello", in: tmp, caseSensitive: false, regex: false, isCancelled: { false })
        XCTAssertEqual(insensitive.count, 1)

        let sensitive = ProjectSearch.search(
            query: "hello", in: tmp, caseSensitive: true, regex: false, isCancelled: { false })
        XCTAssertTrue(sensitive.isEmpty)
    }

    func testProjectSearchRegex() throws {
        try write("id = 42\nid = abc\n", to: "a.txt")
        let results = ProjectSearch.search(
            query: #"id = \d+"#, in: tmp, caseSensitive: false, regex: true, isCancelled: { false })
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.matches.count, 1)
        XCTAssertEqual(results.first?.matches.first?.line, 1)
    }

    func testProjectSearchInvalidRegexReturnsNothing() throws {
        try write("anything\n", to: "a.txt")
        let results = ProjectSearch.search(
            query: "([", in: tmp, caseSensitive: false, regex: true, isCancelled: { false })
        XCTAssertTrue(results.isEmpty)
    }

    func testProjectSearchEmptyQueryReturnsNothing() throws {
        try write("hello\n", to: "a.txt")
        let results = ProjectSearch.search(
            query: "", in: tmp, caseSensitive: false, regex: false, isCancelled: { false })
        XCTAssertTrue(results.isEmpty)
    }

    func testProjectSearchSkipsNoiseDirectories() throws {
        try write("hello here\n", to: "keep.txt")
        try write("hello inside\n", to: "node_modules/dep.txt")

        let results = ProjectSearch.search(
            query: "hello", in: tmp, caseSensitive: false, regex: false, isCancelled: { false })
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.url.lastPathComponent, "keep.txt")
    }

    func testProjectSearchRespectsCancellation() throws {
        try write("hello\n", to: "a.txt")
        let results = ProjectSearch.search(
            query: "hello", in: tmp, caseSensitive: false, regex: false, isCancelled: { true })
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - SkippedDirs

    func testSkippedDirsContainsCommonNoise() {
        for name in [".git", "node_modules", ".build", "DerivedData", "Pods"] {
            XCTAssertTrue(SkippedDirs.names.contains(name), "expected \(name) to be skipped")
        }
    }

    // MARK: - RecentItems

    func testRecentItemsAddAndList() throws {
        RecentItems.clearAll()
        defer { RecentItems.clearAll() }

        let fileA = tmp.appendingPathComponent("a.txt")
        let fileB = tmp.appendingPathComponent("b.txt")
        try "a".write(to: fileA, atomically: true, encoding: .utf8)
        try "b".write(to: fileB, atomically: true, encoding: .utf8)

        RecentItems.addFile(fileA)
        RecentItems.addFile(fileB)

        // Most-recent-first ordering.
        XCTAssertEqual(RecentItems.files.map(\.lastPathComponent), ["b.txt", "a.txt"])

        // Re-adding moves it to the front without duplicating.
        RecentItems.addFile(fileA)
        XCTAssertEqual(RecentItems.files.map(\.lastPathComponent), ["a.txt", "b.txt"])

        // Folders are tracked separately.
        RecentItems.addFolder(tmp)
        XCTAssertEqual(RecentItems.folders.map(\.lastPathComponent), [tmp.lastPathComponent])

        RecentItems.clearAll()
        XCTAssertTrue(RecentItems.files.isEmpty)
        XCTAssertTrue(RecentItems.folders.isEmpty)
    }

    func testRecentItemsFiltersMissingPaths() throws {
        RecentItems.clearAll()
        defer { RecentItems.clearAll() }

        let file = tmp.appendingPathComponent("gone.txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        RecentItems.addFile(file)
        XCTAssertEqual(RecentItems.files.count, 1)

        try FileManager.default.removeItem(at: file)
        XCTAssertTrue(RecentItems.files.isEmpty, "missing paths should be filtered out on read")
    }

    // MARK: - DirectoryEventStream (compile / smoke only)

    func testDirectoryEventStreamInitAndCancel() {
        // FSEvents is async; we only verify the type builds, initializes and
        // cancels cleanly on a real directory.
        let stream = DirectoryEventStream(directory: tmp.path) { _ in }
        stream.cancel()

        // Event / FSEvent are part of the public surface.
        let event = DirectoryEventStream.Event(path: "/tmp/x", eventType: .itemModified)
        XCTAssertEqual(event.path, "/tmp/x")
        XCTAssertEqual(event.eventType, .itemModified)
        XCTAssertEqual(FSEvent.itemCreated.rawValue, "itemCreated")
    }
}
