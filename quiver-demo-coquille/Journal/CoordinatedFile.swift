// Copyright 2026 Wayne W Bishop. All rights reserved.
//
//
// Licensed under the Apache License, Version 2.0 (the "License"); you may not use this
// file except in compliance with the License. You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software distributed under
// the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF
// ANY KIND, either express or implied. See the License for the specific language governing
// permissions and limitations under the License.

import Foundation

/// Reads and changes journal files through `NSFileCoordinator`, so a file is never changed
/// while the system or another app is in the middle of syncing or editing it, as iCloud
/// and the Files app can be.
enum CoordinatedFile {

    /// Runs `body` on `url` once the system lets Coquille read it.
    static func read<Value>(_ url: URL, _ body: (URL) throws -> Value) throws -> Value {
        var coordinationError: NSError?
        var result: Result<Value, any Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { url in
            result = Result { try body(url) }
        }
        return try finish(result, coordinationError)
    }

    /// Writes `data` to `url`, replacing what's there.
    static func write(_ data: Data, to url: URL) throws {
        var coordinationError: NSError?
        var result: Result<Void, any Error>?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { url in
            result = Result { try data.write(to: url, options: .atomic) }
        }
        try finish(result, coordinationError)
    }

    /// Moves the file at `source` to `destination`, which may be in another folder.
    static func move(_ source: URL, to destination: URL) throws {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var result: Result<Void, any Error>?
        coordinator.coordinate(
            writingItemAt: source, options: .forMoving,
            writingItemAt: destination, options: .forReplacing,
            error: &coordinationError
        ) { source, destination in
            result = Result {
                try FileManager.default.moveItem(at: source, to: destination)
                coordinator.item(at: source, didMoveTo: destination)
            }
        }
        try finish(result, coordinationError)
    }

    /// Removes the file at `url`.
    static func remove(_ url: URL) throws {
        var coordinationError: NSError?
        var result: Result<Void, any Error>?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { url in
            result = Result { try FileManager.default.removeItem(at: url) }
        }
        try finish(result, coordinationError)
    }

    /// Returns the body's value, or throws the coordinator's error or the body's own.
    private static func finish<Value>(_ result: Result<Value, any Error>?, _ coordinationError: NSError?) throws -> Value {
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        return try result.get()
    }
}
