# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

WordVision is a visionOS app for learning vocabulary. Users build a personal dictionary, mark words for a quiz, then answer in either a 2D window or a mixed-immersive RealityKit scene where word entities orbit and can be tapped or thrown at the definition prompt.

- Platform: visionOS (`SUPPORTED_PLATFORMS = xros xrsimulator`), `XROS_DEPLOYMENT_TARGET = 26.4`, `TARGETED_DEVICE_FAMILY = 7`
- App target Swift version: 5.0; the local `RealityKitContent` package uses swift-tools-version 6.2
- Tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`), not XCTest

## Build, run, test

Open `WordVision.xcodeproj` in Xcode and run on the visionOS simulator, or from the command line:

```bash
# Build
xcodebuild -project WordVision.xcodeproj -scheme WordVision \
  -destination 'platform=visionOS Simulator,name=Apple Vision Pro' build

# Test (Swift Testing runs through xcodebuild test)
xcodebuild -project WordVision.xcodeproj -scheme WordVision \
  -destination 'platform=visionOS Simulator,name=Apple Vision Pro' test

# Run a single test by name
xcodebuild -project WordVision.xcodeproj -scheme WordVision \
  -destination 'platform=visionOS Simulator,name=Apple Vision Pro' \
  test -only-testing:WordVisionTests/WordVisionTests/example
```

## Source layout quirk

Some Swift sources live at the **repository root** rather than under `WordVision/`, but they are still members of the `WordVision` app target (see `WordVision.xcodeproj/project.pbxproj`):

- Root: `Word.swift`, `QuizViewModel.swift`, `AddEditWordSheet.swift`
- `WordVision/`: `WordVisionApp.swift`, `ContentView.swift`, `ImmersiveView.swift`, `AppModel.swift`, plus `AVPlayer*` and `ToggleImmersiveSpaceButton` (template leftovers, not currently wired into the UI)

When adding a new Swift file, add it to the Xcode target — being on disk is not enough.

## Architecture

Two `@MainActor @Observable` objects own all app state and are injected once in `WordVisionApp` via `.environment(...)`, then read by both the 2D window and the immersive scene:

- **`AppModel`** — `immersiveSpaceState` (closed/inTransition/open), `appPhase` (browsing/quiz), and `chosenWords: [Word]` (the user's selected quiz set).
- **`QuizViewModel`** — quiz lifecycle: `quizWords`, `currentQuestionIndex`, `score`, `lastResult`, `isActive`, `isComplete`. `startQuiz` shuffles the chosen words; `checkAnswer` compares text and sets `lastResult`; `nextQuestion` advances and flips to `isComplete` at the end.

`Word` is a SwiftData `@Model`. Persistence is configured by `WindowGroup { ... }.modelContainer(for: Word.self)` in `WordVisionApp`. `ContentView` reads via `@Query(sort: \Word.dateAdded, order: .reverse)` and seeds eight sample words on first launch when the store is empty.

### Two views of the same state

`ContentView` switches between three sub-views based on quiz state (`browsingView` / `quizActiveView` / `quizCompleteView`) and lets the user toggle the `ImmersiveSpace` (id: `"ImmersiveSpace"`).

`ImmersiveView` mirrors the same observable state into a RealityKit scene built inside a `RealityView`:

- A persistent `rootEntity` parents two orbits: `orbitParent` (browsing — shows `appModel.chosenWords`) and `quizOrbitParent` (active quiz — shows `quizViewModel.quizWords`), plus two attachment entities (`"definition"`, `"score"`).
- The `update:` closure calls `syncEntities()`, which enables exactly one orbit based on `appPhase`/`isActive`/`isComplete` and reconciles its children against the corresponding word list — adding/removing `ModelEntity`s as the lists change. Each entity carries a custom `WordComponent { wordText: String }` so gesture handlers can recover the word from a tapped/dragged entity (walking up via `findWordEntity`).
- `startOrbit()` runs a `Task` that rotates both orbit parents every 16ms until the view disappears.
- A tap or a drag that ends within 0.4m of the definition attachment calls `quizViewModel.checkAnswer(...)`; `animateAnswer` recolors the entity green/red and either shrinks it into the prompt or shake-rejects it. `returnToOrbit` re-parents a dragged entity back into `quizOrbitParent` and re-spaces the ring via `repositionOrbitChildren`.

When changing quiz flow or the `chosenWords` list, remember the immersive scene reflects that state automatically through `syncEntities()` — there is no separate "refresh" call.

## Local Swift package

`Packages/RealityKitContent` is a local Swift package (RealityComposer Pro content bundle template). It is referenced from the app target but currently empty of custom assets.
