// SessionStore.swift
// Form — JSON Persistence Layer
//
// This file handles saving and loading all Session data to/from the device's
// local filesystem using JSON. No database, no SwiftData, no cloud.
//
// ─── WHY JSON TO THE DOCUMENTS DIRECTORY? ───────────────────────────────────
// For a beginner Swift developer, JSON persistence is the most transparent
// approach: you can open the file in any text editor and see exactly what's stored.
// It requires zero configuration, no schema migrations, and works offline.
//
// The Documents directory is the correct location for user-generated data:
//   - It's backed up to iCloud by default (can be disabled with .isExcludedFromBackup)
//   - It persists between app launches and OS updates
//   - It's sandboxed — only this app can read/write here
//
// Alternatives considered:
//   - SwiftData: Requires iOS 17+ and hides the storage format — not ideal for learning
//   - Core Data: Powerful but complex SQL-backed ORM with steep learning curve
//   - UserDefaults: Meant for small settings, not arrays of complex objects
//   - SQLite: Requires manual SQL or a third-party library
//
// ─── THREAD SAFETY ───────────────────────────────────────────────────────────
// File I/O runs on a background queue. @Published updates hop to main.
// This prevents disk writes from blocking the UI thread.

import Foundation
import Combine

// MARK: - SessionStore

/// Persists [Session] as a single JSON file in the app's Documents directory.
///
/// All views that need session history observe this store via @StateObject or
/// @EnvironmentObject. It's the single source of truth for historical data.
final class SessionStore: ObservableObject {

    // MARK: - Published State

    /// All sessions ever recorded, sorted by date descending (newest first).
    /// SwiftUI views observing this re-render when a new session is saved.
    @Published private(set) var sessions: [Session] = []

    // MARK: - File Path

    /// The URL where sessions.json is stored on disk.
    ///
    /// FileManager.default.urls(for:in:) returns the app's sandboxed directories.
    /// .documentDirectory is the standard place for user data files.
    /// .userDomainMask means "this user on this device" (always correct for iOS apps).
    private let storageURL: URL

    // MARK: - Background Queue

    /// All disk I/O happens on this queue. We use a serial queue (not concurrent)
    /// to prevent write-after-write races if two sessions complete rapidly.
    private let ioQueue: DispatchQueue

    // MARK: - Initializer

    init(
        storageURL: URL? = nil,
        ioQueue: DispatchQueue = DispatchQueue(
            label: "com.form.sessionStore.io",
            qos: .utility
        )
    ) {
        self.storageURL = storageURL ?? Self.defaultStorageURL
        self.ioQueue = ioQueue

        // Load existing sessions from disk when the store is created.
        // SessionStore is typically created once at app launch (in SessionListView).
        load()
    }

    // MARK: - Save

    /// Appends a session and persists the full array to disk.
    ///
    /// - Parameter session: The completed session to save.
    ///
    /// Saving happens on ioQueue (background). The published `sessions` array
    /// updates immediately on the main thread for responsive UI — the disk write
    /// follows asynchronously.
    func save(session: Session) {
        let updatedSessions = [session] + sessions

        // Update in-memory state immediately (optimistic update)
        // This way the UI reflects the new session before the disk write completes.
        if Thread.isMainThread {
            sessions = updatedSessions
        } else {
            DispatchQueue.main.sync {
                self.sessions = updatedSessions
            }
        }

        // Write to disk on background queue
        ioQueue.async { [weak self] in
            guard let self else { return }
            self.persist(sessions: updatedSessions)
        }
    }

    /// Deletes sessions at the given offsets (from SwiftUI's onDelete modifier).
    /// - Parameter offsets: IndexSet from the List's onDelete callback.
    func delete(at offsets: IndexSet) {
        sessions.remove(atOffsets: offsets)
        let updatedSessions = sessions
        ioQueue.async { [weak self] in self?.persist(sessions: updatedSessions) }
    }

    // MARK: - Private: Persist

    /// Encodes the current sessions array to JSON and writes it to disk.
    ///
    /// Called on ioQueue — never call from the main thread.
    private func persist(sessions: [Session]) {
        do {
            // Step 1: Create an encoder
            let encoder = JSONEncoder()

            // .iso8601 format: stores dates as "2025-01-15T10:30:00Z" strings.
            // Human-readable and standard. Alternative: .secondsSince1970 (compact).
            encoder.dateEncodingStrategy = .iso8601

            // .prettyPrinted makes the JSON file human-readable with indentation.
            // In production you'd remove this to save ~30% file size, but for a
            // learning project, readable JSON is more valuable than size savings.
            encoder.outputFormatting = .prettyPrinted

            // Step 2: Encode [Session] → Data (raw bytes)
            let data = try encoder.encode(sessions)

            // Step 3: Write Data to the file URL
            // .atomic: writes to a temp file first, then renames it to the target.
            // This prevents partial writes that would corrupt the file if the app crashes.
            try data.write(to: storageURL, options: .atomic)

            print("[SessionStore] ✅ Saved \(sessions.count) session(s) to \(storageURL.lastPathComponent)")
        } catch {
            // Encoding or disk write failed. Log it — we shouldn't crash the app
            // over a failed save, but we should surface it for debugging.
            print("[SessionStore] ❌ Save failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Private: Load

    /// Reads the JSON file from disk and decodes it into the sessions array.
    ///
    /// Called once during init(). Failures are graceful — a new user has no file yet.
    private func load() {
        ioQueue.async { [weak self] in
            guard let self else { return }

            // Step 1: Check if the file exists yet
            guard FileManager.default.fileExists(atPath: self.storageURL.path) else {
                print("[SessionStore] No existing session file found — starting fresh")
                return // First launch, no file yet
            }

            do {
                // Step 2: Read the raw bytes from disk
                let data = try Data(contentsOf: self.storageURL)

                // Step 3: Create a decoder matching our encoder settings
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601

                // Step 4: Decode Data → [Session]
                // If the JSON structure doesn't match our Swift types, this throws.
                let loadedSessions = try decoder.decode([Session].self, from: data)

                // Step 5: Update published state on main thread
                DispatchQueue.main.async {
                    self.sessions = loadedSessions
                    print("[SessionStore] ✅ Loaded \(loadedSessions.count) session(s)")
                }
            } catch {
                // Decoding failure. Possible causes:
                //   - Model changed (added/removed a required property)
                //   - File corruption
                // Don't delete the file here — let the developer inspect it first.
                print("[SessionStore] ❌ Load failed: \(error.localizedDescription)")
            }
        }
    }

    private static let defaultStorageURL: URL = {
        let documentsDir = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!
        return documentsDir.appendingPathComponent("form_sessions.json")
    }()
}
