# Swift File Tools

A small, dependency-free bundle of macOS file utilities for tooling and code-review UIs — an ASCII project-tree renderer, a fast recursive project-wide text search, a `UserDefaults`-backed recent-files list, and a self-contained FSEvents directory watcher.

## Features

- 🌳 **ASCII tree** — render a folder as a `tree`-style diagram, ready to paste to an agent
- 🔍 **Project search** — fast recursive text or regex search across a directory
- 🕒 **Recent items** — persistent, capped, most-recent-first files & folders list
- 👀 **Directory watching** — debounced FSEvents stream of file-system changes
- 🚫 **Noise-aware** — shared ``SkippedDirs`` set (`.git`, `node_modules`, `.build`, …)
- 🪶 **Zero dependencies** — Foundation only

## Requirements

- macOS 10.15+
- Swift 5.9+

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/arraypress/swift-file-tools.git", from: "1.0.0")
]
```

## Usage

```swift
import FileTools

// Render a project as an ASCII tree.
print(FileTree.ascii(of: projectURL))

// Search the project for a query (dispatch to the background yourself).
let hits = ProjectSearch.search(query: "TODO", in: projectURL,
                                caseSensitive: false, regex: false,
                                isCancelled: { false })
for file in hits {
    for match in file.matches {
        print("\(file.url.lastPathComponent):\(match.line): \(match.lineText)")
    }
}

// Track recently-opened files.
RecentItems.addFile(fileURL)
let recent = RecentItems.files   // [URL], newest first

// Watch a directory for changes.
let watcher = DirectoryEventStream(directory: projectURL.path) { events in
    for event in events { print(event.eventType, event.path) }
}
// watcher.cancel() to stop.
```

## License

MIT
