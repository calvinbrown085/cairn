import SwiftUI
import SwiftData

@main
struct StacksApp: App {
    private let container: ModelContainer
    @State private var archive: ArchiveService
    @State private var preferences = ReadingPreferences.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let container = StacksApp.makeContainer()
        self.container = container
        _archive = State(initialValue: ArchiveService(context: container.mainContext))
        StacksApp.applyNavigationBarAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(archive)
                .environment(preferences)
                .tint(Palette.accent)
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            // Anything shared while the app was in the background is waiting.
            if phase == .active { archive.drainSharedInbox() }
        }
    }

    /// Sets navigation titles in New York to match the lists and the reader.
    /// Only the text attributes are touched, so the bar keeps its system
    /// background and materials.
    private static func applyNavigationBarAppearance() {
        func serif(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
            let base = UIFont.systemFont(ofSize: size, weight: weight)
            guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
            return UIFont(descriptor: descriptor, size: size)
        }

        UINavigationBar.appearance().largeTitleTextAttributes = [
            .font: serif(32, .bold),
            .foregroundColor: UIColor(Palette.ink),
        ]
        UINavigationBar.appearance().titleTextAttributes = [
            .font: serif(16, .semibold),
            .foregroundColor: UIColor(Palette.ink),
        ]
    }

    /// Builds the CloudKit-backed store, falling back to a local one if the
    /// iCloud container isn't available — an unsigned build or a device with no
    /// iCloud account should still run rather than crash on launch.
    private static func makeContainer() -> ModelContainer {
        let schema = Schema([Post.self, StoredImage.self, Highlight.self, InkStroke.self])

        let synced = ModelConfiguration(
            schema: schema,
            url: AppGroup.storeURL,
            cloudKitDatabase: .private(AppGroup.cloudKitContainer)
        )

        do {
            return try ModelContainer(for: schema, configurations: [synced])
        } catch {
            let local = ModelConfiguration(schema: schema, url: AppGroup.storeURL)
            if let container = try? ModelContainer(for: schema, configurations: [local]) {
                return container
            }
            // Last resort: an in-memory store, so the UI can explain itself.
            let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: [memory])
        }
    }
}
