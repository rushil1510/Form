// FormApp.swift
// Form — Offline-First Gym Form Correction
//
// This file is the application's ENTRY POINT. Every SwiftUI app needs exactly
// one struct marked with @main — this tells the Swift compiler "start here."
//
// WHY @main?
// In UIKit, you'd have a main.m file and AppDelegate. SwiftUI replaces that
// with the @main attribute on a struct conforming to App. Think of it as the
// equivalent of `int main()` in C, but lifecycle-managed by the OS.

import SwiftUI

// MARK: - App Entry Point

@main
struct FormApp: App {

    // MARK: - State Objects

    // @StateObject creates AppState ONCE and keeps it alive for the entire
    // app lifecycle. We use @StateObject (not @ObservedObject) here because
    // FormApp *owns* this object — it's the root of the state tree.
    //
    // AppState holds global state: which exercise is selected, whether a
    // session is in progress, etc. Child views observe it via @EnvironmentObject.
    @StateObject private var appState = AppState()

    // MARK: - Scene Body

    // `body` returns a Scene — in iOS apps this is almost always a WindowGroup,
    // which tells iOS "this app has one main window."
    var body: some Scene {
        WindowGroup {
            // ContentView is the root UI. We inject appState into the SwiftUI
            // environment so ANY descendant view can access it with:
            //   @EnvironmentObject var appState: AppState
            //
            // This is dependency injection without passing values through every
            // intermediate view (which SwiftUI calls "prop drilling" in React terms).
            ContentView()
                .environmentObject(appState)
        }
    }
}

// MARK: - Root Navigation View

/// ContentView is the root navigation shell for the app.
/// It decides which top-level screen to show based on AppState.
///
/// Architecture note: We keep this thin — it's a router, not a feature view.
/// Real UI lives inside Features/ and UI/ folders.
struct ContentView: View {

    @EnvironmentObject var appState: AppState

    var body: some View {
        // TabView gives us the bottom tab bar common to iOS fitness apps.
        // Each tab is its own navigation stack, which is the idiomatic iOS pattern.
        TabView {
            // Tab 1: Start a workout session
            WorkoutView()
                .tabItem {
                    Label("Workout", systemImage: "figure.strengthtraining.traditional")
                }

            // Tab 2: Browse past sessions
            SessionListView()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
        }
        // Accent color applied globally — SF Symbols and interactive elements
        // will inherit this tint throughout the app.
        .tint(.orange)
    }
}
