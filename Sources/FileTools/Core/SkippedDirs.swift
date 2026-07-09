//
//  SkippedDirs.swift
//  SwiftFileTools
//
//  The set of "noise" directory names (version-control metadata, build output,
//  dependency caches) that scanners should skip when walking a project tree.
//
//  Created by David Sherlock on 7/9/26.
//

import Foundation

/// A shared set of directory names that file scanners should ignore.
///
/// These are the usual noise folders — version-control metadata, package
/// managers, build output and caches — that you almost never want to descend
/// into when searching or rendering a project's structure.
///
/// ```swift
/// if SkippedDirs.names.contains(url.lastPathComponent) { continue }
/// ```
public enum SkippedDirs {

    /// Directory names to skip when scanning a project (e.g. `.git`,
    /// `node_modules`, `.build`, `DerivedData`).
    public static let names: Set<String> = [
        ".git", ".svn", ".hg", "node_modules", ".build", ".swiftpm",
        "Pods", "DerivedData", ".next", "__pycache__", ".cache",
        "build", "dist", ".DS_Store", ".Trash",
    ]
}
