//
//  ProjectSearch.swift
//  SwiftFileTools
//
//  Fast, recursive, project-wide text search over a directory. Runs
//  synchronously; callers should dispatch it to a background queue.
//
//  Created by David Sherlock on 7/9/26.
//

import Foundation

/// Fast recursive project-wide text search.
///
/// Runs synchronously on whatever queue it's called from — callers should
/// dispatch it to the background. Noise directories (see ``SkippedDirs``),
/// oversized files and binary files are skipped automatically.
///
/// ```swift
/// let hits = ProjectSearch.search(query: "TODO", in: root,
///                                 caseSensitive: false, regex: false,
///                                 isCancelled: { false })
/// ```
public enum ProjectSearch {
    /// Files bigger than this are skipped (likely generated/minified/lock files).
    private static let maxFileBytes = 2_000_000
    private static let maxTotalMatches = 5_000
    private static let maxMatchesPerFile = 200

    /// Recursively searches `root` for `query`.
    ///
    /// - Parameters:
    ///   - query: The text (or regular-expression pattern) to search for. An
    ///     empty query returns no results.
    ///   - root: The directory to search.
    ///   - caseSensitive: Whether matching is case-sensitive.
    ///   - regex: When `true`, `query` is treated as a regular expression; an
    ///     invalid pattern yields no results.
    ///   - isCancelled: Polled between files; return `true` to stop early.
    /// - Returns: One ``SearchFileResult`` per matching file, sorted by path.
    public static func search(
        query: String,
        in root: URL,
        caseSensitive: Bool,
        regex: Bool,
        isCancelled: () -> Bool
    ) -> [SearchFileResult] {
        guard !query.isEmpty else { return [] }

        let regexObj: NSRegularExpression? = regex
            ? try? NSRegularExpression(pattern: query,
                                       options: caseSensitive ? [] : [.caseInsensitive])
            : nil
        if regex && regexObj == nil { return [] }   // invalid pattern

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [SearchFileResult] = []
        var total = 0

        for case let url as URL in enumerator {
            if isCancelled() { break }

            let name = url.lastPathComponent
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                if SkippedDirs.names.contains(name) { enumerator.skipDescendants() }
                continue
            }
            if SkippedDirs.names.contains(name) { continue }

            // Only read regular files. Symlinks report the size of the LINK
            // (a few bytes) here while `Data(contentsOf:)` would follow them
            // and read the whole target — bypassing the size guard — and
            // special files (FIFOs, sockets, devices) aren't searchable text.
            let attrs = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard attrs?.isRegularFile == true else { continue }

            let size = attrs?.fileSize ?? 0
            if size > maxFileBytes { continue }

            guard let data = try? Data(contentsOf: url),
                  !data.prefix(4000).contains(0),                 // skip binary
                  let text = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1)
            else { continue }

            let fileMatches = matches(in: text, query: query,
                                      caseSensitive: caseSensitive, regex: regexObj)
            if !fileMatches.isEmpty {
                results.append(SearchFileResult(url: url, matches: fileMatches))
                total += fileMatches.count
                if total >= maxTotalMatches { break }
            }
        }

        results.sort { $0.url.path.localizedCaseInsensitiveCompare($1.url.path) == .orderedAscending }
        return results
    }

    private static func matches(
        in text: String,
        query: String,
        caseSensitive: Bool,
        regex: NSRegularExpression?
    ) -> [SearchMatch] {
        var out: [SearchMatch] = []
        var lineNo = 0

        text.enumerateLines { line, stop in
            lineNo += 1
            if out.count >= maxMatchesPerFile {   // per-file cap
                stop = true
                return
            }
            let ns = line as NSString
            let full = NSRange(location: 0, length: ns.length)

            if let regex {
                for m in regex.matches(in: line, options: [], range: full) {
                    if out.count >= maxMatchesPerFile { break }
                    out.append(SearchMatch(line: lineNo, lineText: line, range: m.range))
                }
            } else {
                var searchStart = 0
                let opts: NSString.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
                while searchStart < ns.length {
                    let r = ns.range(of: query, options: opts,
                                     range: NSRange(location: searchStart, length: ns.length - searchStart))
                    if r.location == NSNotFound { break }
                    if out.count >= maxMatchesPerFile { break }
                    out.append(SearchMatch(line: lineNo, lineText: line, range: r))
                    searchStart = NSMaxRange(r) > r.location ? NSMaxRange(r) : r.location + 1
                }
            }
        }
        return out
    }
}
