import SwiftUI
import SwiftData

@main
struct WordVisionApp: App {
    @State private var appModel = AppModel()
    @State private var quizViewModel = QuizViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
                .environment(quizViewModel)
        }
        .defaultSize(width: 900, height: 600)
        .modelContainer(for: Word.self)

        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            ImmersiveView()
                .environment(appModel)
                .environment(quizViewModel)
                .onAppear { appModel.immersiveSpaceState = .open }
                .onDisappear { appModel.immersiveSpaceState = .closed }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)

        ImmersiveSpace(id: appModel.quizImmersiveSpaceID) {
            QuizImmersiveView()
                .environment(appModel)
                .environment(quizViewModel)
                .onAppear { appModel.quizImmersiveSpaceState = .open }
                .onDisappear { appModel.quizImmersiveSpaceState = .closed }
        }
        .immersionStyle(selection: .constant(.full), in: .full)
    }
}
