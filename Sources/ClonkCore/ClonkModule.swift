import SwiftUI
import iUX_MacOS

/// The single public surface for embedding Clonk in a bundle.
///
/// A host app initialises one `ClonkModule`, calls `start()` after the app
/// finishes launching, then embeds `settingsView()` wherever it wants to
/// surface Clonk's settings (e.g. a sidebar pane). The icon and menu-bar item
/// are standalone-only concerns — they are *not* part of this API.
@MainActor
public final class ClonkModule: AppModule {

    // MARK: - Identity

    public static let moduleID    = "ltd.anti.clonk"
    public static let displayName = "Clonk"
    public static let symbolName  = "keyboard"

    /// Scene identifier for the settings `Window`. Use with
    /// `@Environment(\.openWindow)` from any view inside the app.
    public static let windowID    = "clonk-settings"

    // MARK: - Core

    private let model: AppModel

    public required init() {
        model = AppModel()
    }

    /// Wire up the sound engine and keyboard monitor. Call once after the host
    /// app has finished launching.
    public func start() {
        model.start()
    }

    /// Whether the engine is currently suppressed by a sleep trigger.
    public var isMuted: Bool { model.isMuted }

    #if APPSTAGE
    /// Dev-only: render a named UI state for appstage screenshot capture.
    public func runAppStage(state: String) {
        AppStageCapture.run(state: state, model: model)
    }
    #endif

    // MARK: - UI

    /// A self-contained settings view ready to drop into a sidebar or sheet.
    public func settingsView() -> AnyView {
        AnyView(PopoverView(model: model))
    }

    /// The sidebar-style settings view, for embedding in a SwiftUI `Window`
    /// scene. The Scene gives `NavigationSplitView` the chrome it needs
    /// (unified toolbar, transparent titlebar, vibrant sidebar) — chrome a
    /// hand-rolled `NSWindow(contentViewController:)` can't reproduce.
    public func windowView() -> AnyView {
        AnyView(SettingsWindowView(model: model))
    }
}
