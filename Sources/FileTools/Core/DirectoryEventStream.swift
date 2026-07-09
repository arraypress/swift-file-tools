//
//  DirectoryEventStream.swift
//  SwiftFileTools
//
//  A self-contained FSEvents wrapper that streams file-system change events for
//  a directory. Lifted from CodeEdit (MIT). Original author: Khan Winter.
//
//  Created by David Sherlock on 7/9/26.
//

import Foundation

/// Creates a stream of events using the File System Events API.
///
/// The stream of events is started immediately upon initialization, and will only be stopped when either `cancel`
/// is called, or the object is deallocated. The stream is also configured to debounce notifications to happen
/// according to the `debounceDuration` parameter. This directly corresponds with the `latency` parameter in
/// `FSEventStreamCreate`, which will delay notifications until `latency` has passed at which point it will send all
/// the notifications built up during that period of time.
///
/// Use the `callback` parameter to listen for notifications.
/// Notifications are automatically filtered to include certain events, but the FS event API doesn't always correctly
/// flag events so use caution when handling events as they can come frequently.
///
/// The `callback` function will be called with all events that happened since the last event notification,
/// effectively batching all notifications every `debounceDuration`. This callback may not be called on a
/// predictable dispatch queue.
public final class DirectoryEventStream {

    /// A callback invoked with every batch of events since the last notification.
    public typealias EventCallback = ([Event]) -> Void

    private var streamRef: FSEventStreamRef?
    private var callback: EventCallback
    private let debounceDuration: TimeInterval

    /// A single file-system change: the affected `path` and its ``FSEvent`` kind.
    public struct Event {

        /// The absolute path of the item that changed.
        public let path: String

        /// The kind of change that occurred.
        public let eventType: FSEvent

        /// Creates a file-system event.
        /// - Parameters:
        ///   - path: The absolute path of the item that changed.
        ///   - eventType: The kind of change that occurred.
        public init(path: String, eventType: FSEvent) {
            self.path = path
            self.eventType = eventType
        }
    }

    /// Initialize the event stream and begin listening for events.
    /// - Parameters:
    ///   - directory: The directory to monitor.
    ///   - debounceDuration: The duration to delay notifications for to let the FS events API accumulate events.
    ///   - callback: A callback the stream will send events to.
    public init(directory: String, debounceDuration: TimeInterval = 0.1, callback: @escaping EventCallback) {
        self.debounceDuration = debounceDuration
        self.callback = callback
        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        var context = FSEventStreamContext(
            version: 0,
            info: selfPtr,
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let contextPtr = withUnsafeMutablePointer(to: &context) { ptr in UnsafeMutablePointer(ptr) }

        let cfDirectory = directory as CFString
        let pathsToWatch = [cfDirectory] as CFArray

        if let ref = FSEventStreamCreate(
            kCFAllocatorDefault,
            { streamRef, clientCallBackInfo, numEvents, eventPaths, eventFlags, eventIds in
                guard let clientCallBackInfo else { return }
                Unmanaged<DirectoryEventStream>
                    .fromOpaque(clientCallBackInfo)
                    .takeUnretainedValue()
                    .eventStreamHandler(streamRef, numEvents, eventPaths, eventFlags, eventIds)
            },
            contextPtr,
            pathsToWatch,
            UInt64(kFSEventStreamEventIdSinceNow),
            debounceDuration,
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagUseExtendedData
                | kFSEventStreamCreateFlagNoDefer
            )
        ) {
            self.streamRef = ref
            FSEventStreamSetDispatchQueue(ref, DispatchQueue.global(qos: .default))
            FSEventStreamStart(ref)
        }
    }

    deinit {
        cancel()
    }

    /// Cancels the events watcher. Re-initialize to begin streaming again.
    public func cancel() {
        if let streamRef {
            FSEventStreamStop(streamRef)
            FSEventStreamInvalidate(streamRef)
            FSEventStreamRelease(streamRef)
        }
        streamRef = nil
    }

    private func eventStreamHandler(
        _ streamRef: ConstFSEventStreamRef,
        _ numEvents: Int,
        _ eventPaths: UnsafeMutableRawPointer,
        _ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
        _ eventIds: UnsafePointer<FSEventStreamEventId>
    ) {
        guard let eventDictionaries = unsafeBitCast(eventPaths, to: NSArray.self) as? [NSDictionary] else {
            return
        }

        var events: [Event] = []

        for (index, dictionary) in eventDictionaries.enumerated() {
            guard let path = dictionary[kFSEventStreamEventExtendedDataPathKey] as? String else {
                continue
            }
            let fsEvents = getEventsFromFlags(eventFlags[index])
            for event in fsEvents {
                events.append(.init(path: path, eventType: event))
            }
        }

        callback(events)
    }

    /// Parses ``FSEvent`` from the raw flag value. There can be multiple events in one raw flag.
    private func getEventsFromFlags(_ raw: FSEventStreamEventFlags) -> Set<FSEvent> {
        var events: Set<FSEvent> = []

        if raw == 0 {
            events.insert(.changeInDirectory)
        }
        if raw & UInt32(kFSEventStreamEventFlagRootChanged) > 0 {
            events.insert(.rootChanged)
        }
        if raw & UInt32(kFSEventStreamEventFlagItemChangeOwner) > 0 {
            events.insert(.itemChangedOwner)
        }
        if raw & UInt32(kFSEventStreamEventFlagItemCreated) > 0 {
            events.insert(.itemCreated)
        }
        if raw & UInt32(kFSEventStreamEventFlagItemCloned) > 0 {
            events.insert(.itemCloned)
        }
        if raw & UInt32(kFSEventStreamEventFlagItemModified) > 0 {
            events.insert(.itemModified)
        }
        if raw & UInt32(kFSEventStreamEventFlagItemRemoved) > 0 {
            events.insert(.itemRemoved)
        }
        if raw & UInt32(kFSEventStreamEventFlagItemRenamed) > 0 {
            events.insert(.itemRenamed)
        }

        return events
    }
}
