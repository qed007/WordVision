import SwiftUI

@MainActor
@Observable
class AppModel {
    let immersiveSpaceID = "ImmersiveSpace"
    let quizImmersiveSpaceID = "QuizImmersiveSpace"

    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }

    enum AppPhase {
        case browsing
        case quiz
    }

    var immersiveSpaceState = ImmersiveSpaceState.closed
    var quizImmersiveSpaceState = ImmersiveSpaceState.closed
    var appPhase = AppPhase.browsing
    var chosenWords: [Word] = []
}
