import SwiftUI

/// Which tab is showing, and the requests that cross tabs, such as opening a note from Home.
@MainActor
final class AppRouter: ObservableObject {
    enum TabID: Hashable { case home, notes, more, search }

    @Published var tab: TabID = .home
    @Published var showingSettings = false
    @Published var toolPath: [Tool] = []

    /// Launch arguments that open a given screen, for simulator fixtures: `-fixtureTab more`,
    /// `-fixtureTool calculator`, `-fixtureSettings YES`, `-fixtureNote <file name>`, and
    /// `-fixtureQuery <text>` for Search and the calculator. Ignored when absent.
    init(defaults: UserDefaults = .standard) {
        switch defaults.string(forKey: "fixtureTab") {
        case "notes": tab = .notes
        case "more": tab = .more
        case "search": tab = .search
        default: break
        }
        if let tool = defaults.string(forKey: "fixtureTool").flatMap(Tool.init(rawValue:)) { toolPath = [tool] }
        showingSettings = defaults.bool(forKey: "fixtureSettings")
    }

    /// Shows a note in the Notes tab.
    func open(noteID: String, in model: NotesModel) {
        model.selectedID = noteID
        tab = .notes
    }

    /// Starts a new note in the Notes tab with the keyboard up.
    func newNote(in model: NotesModel) {
        model.newNote()
        tab = .notes
    }
}

/// The app's tabs: Home, Notes, More and Search, with onboarding over them on first launch and
/// Settings as a sheet from any tab.
struct RootView: View {
    @ObservedObject var model: NotesModel
    @ObservedObject var themes: ThemeStore
    @StateObject private var router = AppRouter()
    @AppStorage("onboardingComplete") private var onboardingComplete = false

    var body: some View {
        if UserDefaults.standard.bool(forKey: "fixtureWidgets") {
            WidgetGallery()
        } else {
            tabs
        }
    }

    private var tabs: some View {
        TabView(selection: $router.tab) {
            Tab("Home", systemImage: "house", value: AppRouter.TabID.home) {
                HomeView()
            }
            Tab("Notes", systemImage: "note.text", value: AppRouter.TabID.notes) {
                NotesView(model: model, themes: themes)
            }
            Tab("More", systemImage: "square.grid.2x2", value: AppRouter.TabID.more) {
                MoreView()
            }
            Tab(value: AppRouter.TabID.search, role: .search) {
                SearchView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .environmentObject(model)
        .environmentObject(router)
        .environmentObject(themes)
        .sheet(isPresented: $router.showingSettings) {
            SettingsView(themes: themes, store: model.store, location: model.location)
                .environmentObject(router)
        }
        .onOpenURL { url in if let link = DeepLink(url) { router.handle(link, model: model) } }
        .onReceive(NotificationCenter.default.publisher(for: DeepLinkCenter.notification)) { _ in
            if let link = DeepLinkCenter.take() { router.handle(link, model: model) }
        }
        .onAppear {
            if let link = DeepLinkCenter.take() { router.handle(link, model: model) }
            if let id = UserDefaults.standard.string(forKey: "fixtureNote") { router.open(noteID: id, in: model) }
        }
        .fullScreenCover(isPresented: Binding(get: { !onboardingComplete }, set: { onboardingComplete = !$0 })) {
            OnboardingView { onboardingComplete = true }
        }
    }
}

/// The screen for a tool reached from Home, More or Search.
struct ToolDestination: View {
    let tool: Tool

    var body: some View {
        switch tool {
        case .snippets: SnippetsView()
        case .quicklinks: QuicklinksView()
        case .calculator: CalculatorView()
        case .notes: EmptyView()
        }
    }
}

/// The gear that opens Settings, shared by the Home and More toolbars.
struct SettingsButton: View {
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        Button { router.showingSettings = true } label: { Image(systemName: "gearshape") }
            .accessibilityLabel("Settings")
    }
}
