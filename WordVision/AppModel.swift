import SwiftUI

@MainActor
@Observable
class AppModel {
    let immersiveSpaceID = "ImmersiveSpace"

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
    var appPhase = AppPhase.browsing
    var chosenWords: [Word] = []
}
