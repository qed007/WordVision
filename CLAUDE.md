# WordVision Vision OS App

## Project Overview

a visionOS definition-quiz game. A definition floats in front of the user, four 3D word entities spawn in an arc, the user pinches/drags/throws the correct one through a glowing target ring. Correct word in the ring scores; wrong word bounces out.

## Build & run

- Xcode 16+, visionOS 2.0+, Swift 5.10+
- Scheme: `WordThrower`, destination: **Apple Vision Pro**
- Simulator works for the window and static scene; hand-tracked drag requires the device.
- `Info.plist` requires `NSHandsTrackingUsageDescription`.

## Architecture invariants

- **`AppModel` is the sole writer of game state** (score, current `Round`, immersive lifecycle). `ImmersiveView` and `ContentView` read via `@Environment` and never mutate it directly.
- **One `RealityView` owns the scene graph.** Spawning, despawning, and gesture handling live there. No entity creation outside factory enums.
- **Factories return fully-configured entities.** `WordEntity.make(_:)` and `TargetEntity.make()` attach all components (collision, physics, input, tags) before returning. Callers position and parent only.
- **Drag is kinematic-on-grab → dynamic-on-release.** Setting position on a dynamic body fights the solver; flip the mode for the duration of the drag, then restore and inject velocity via `PhysicsMotionComponent`.
- **Round transitions go through `AppModel.startRound()`.** Never mutate `round` from a view.

## Conventions

- Entity naming: `word:<text>` for word entities, `target` for the ring, `target.trigger` for its collision volume. Collision handlers identify entities by `WordTagComponent` and the trigger’s `name`, never by string parsing.
- Frame-based positioning for 3D content; no SwiftUI layout inside the immersive scene.
- All mesh and material work runs on `@MainActor`.

## Gotchas

- `MeshResource.generateText` anchors text at the lower-left of its bounds. Recenter via `visualBounds(relativeTo: nil).center` before parenting, otherwise rotation and physics behave unintuitively.
- The target needs a **trigger** collision (`CollisionComponent.Mode.trigger`) so words pass through and emit `CollisionEvents.Began`. A solid collider just deflects them off the rim.
- Compute throw velocity from the last 2–3 sampled (position, time) pairs in the drag — not from `value.predictedEndLocation3D`. The prediction is tuned for 2D content and is wrong in 3D.
- Despawn words that fall below the floor or escape a ~5 m radius. Orphaned dynamic bodies accumulate fast and tank frame rate.

## File map

```
WordThrower/
├── WordThrowerApp.swift     @main, WindowGroup + ImmersiveSpace("Sandbox")
├── ContentView.swift        2D control window: score, definition, immersive toggle
├── ImmersiveView.swift      RealityView, gestures, collision subs, spawn/despawn
├── AppModel.swift           @Observable game state, round logic
├── QuizModel.swift          QuizItem, Round, curated word pool
├── WordEntity.swift         Factory + WordTagComponent
└── TargetEntity.swift       Factory for ring + trigger volume
```

## Out of scope for v1

Difficulty tiers, SwiftData high scores, spatial audio, SharePlay. Don’t pre-build hooks for these — wire them in when they’re real.
