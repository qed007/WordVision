import SwiftUI
import RealityKit
import RealityKitContent

struct QuizWordComponent: Component {
    var wordText: String
    var homePosition: SIMD3<Float>
    var isFree: Bool = false
}

struct QuizImmersiveView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(QuizViewModel.self) private var quizViewModel
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    @State private var sceneRoot = Entity()
    @State private var wordsParent = Entity()
    @State private var definitionAnchor = Entity()
    @State private var scoreAnchor = Entity()
    @State private var controlsAnchor = Entity()
    @State private var dragStates: [ObjectIdentifier: DragState] = [:]
    @State private var throwTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    @State private var rotationStarts: [ObjectIdentifier: simd_quatf] = [:]
    @State private var floatTask: Task<Void, Never>?
    @State private var lastSyncedQuestion = -1

    /// Tracks per-entity drag samples so we can compute throw velocity on release.
    private struct DragState {
        var startPosition: SIMD3<Float>
        var startRotation: simd_quatf
        var lastPosition: SIMD3<Float>
        var lastTime: TimeInterval
        var velocity: SIMD3<Float>
    }

    var body: some View {
        RealityView { content, attachments in
            // Load Apple's default immersive scene from RealityKitContent
            // (SkyDome + Ground assets shipped by the visionOS template).
            if let scene = try? await Entity(named: "Immersive", in: realityKitContentBundle) {
                sceneRoot.addChild(scene)
            }
            content.add(sceneRoot)

            wordsParent.position = [0, 1.4, -1.6]
            sceneRoot.addChild(wordsParent)

            if let def = attachments.entity(for: "definition") {
                definitionAnchor.position = [0, 1.7, -1.4]
                definitionAnchor.addChild(def)
                sceneRoot.addChild(definitionAnchor)
            }

            if let score = attachments.entity(for: "score") {
                scoreAnchor.position = [0, 2.3, -1.6]
                scoreAnchor.addChild(score)
                sceneRoot.addChild(scoreAnchor)
            }

            if let controls = attachments.entity(for: "controls") {
                controlsAnchor.position = [0, 0.9, -1.2]
                controlsAnchor.addChild(controls)
                sceneRoot.addChild(controlsAnchor)
            }

        } update: { _, _ in
            syncWordEntities()

        } attachments: {
            Attachment(id: "definition") {
                if let definition = quizViewModel.currentDefinition {
                    VStack(spacing: 14) {
                        Image(systemName: "sparkles")
                            .font(.title)
                            .foregroundStyle(.cyan)

                        Text("Throw the matching word here")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(definition)
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                    }
                    .padding(28)
                    .frame(width: 460)
                    .glassBackgroundEffect()
                } else if let result = quizViewModel.lastResult {
                    resultCard(result)
                }
            }

            Attachment(id: "score") {
                if quizViewModel.isActive || quizViewModel.isComplete {
                    HStack(spacing: 24) {
                        Label("\(quizViewModel.score)", systemImage: "star.fill")
                            .foregroundStyle(.yellow)
                        Text("\(quizViewModel.totalAnswered) / \(quizViewModel.quizWords.count)")
                            .foregroundStyle(.white)
                    }
                    .font(.title.bold())
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .glassBackgroundEffect()
                }
            }

            Attachment(id: "controls") {
                HStack(spacing: 16) {
                    if quizViewModel.lastResult != nil && !quizViewModel.isComplete {
                        Button {
                            quizViewModel.nextQuestion()
                        } label: {
                            Label("Next Question", systemImage: "arrow.right.circle.fill")
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Button {
                        Task {
                            quizViewModel.endQuiz()
                            appModel.appPhase = .browsing
                            await dismissImmersiveSpace()
                        }
                    } label: {
                        Label("Exit Quiz", systemImage: "xmark.circle")
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                .padding(12)
                .glassBackgroundEffect()
            }
        }
        .gesture(
            DragGesture()
                .targetedToAnyEntity()
                .onChanged { value in handleDragChanged(value) }
                .onEnded { value in handleDragEnded(value) }
        )
        .simultaneousGesture(
            RotateGesture3D()
                .targetedToAnyEntity()
                .onChanged { value in handleRotateChanged(value) }
                .onEnded { value in handleRotateEnded(value) }
        )
        .gesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in handleTap(on: value.entity) }
        )
        .onAppear { startFloatAnimation() }
        .onDisappear {
            floatTask?.cancel()
            for task in throwTasks.values { task.cancel() }
            throwTasks.removeAll()
        }
    }

    // MARK: - Sync Word Entities

    private func syncWordEntities() {
        // Rebuild entities whenever the question advances or quiz set changes.
        let currentQuestion = quizViewModel.currentQuestionIndex
        let existingTexts = Set(wordsParent.children.compactMap {
            $0.components[QuizWordComponent.self]?.wordText
        })
        let quizTexts = Set(quizViewModel.quizWords.map(\.text))

        let needsRebuild =
            existingTexts != quizTexts ||
            currentQuestion != lastSyncedQuestion

        if needsRebuild {
            for task in throwTasks.values { task.cancel() }
            throwTasks.removeAll()
            dragStates.removeAll()
            rotationStarts.removeAll()

            for child in Array(wordsParent.children) {
                child.removeFromParent()
            }
            buildWordEntities()
            lastSyncedQuestion = currentQuestion
        }
    }

    private func buildWordEntities() {
        let words = quizViewModel.quizWords
        guard !words.isEmpty else { return }

        let radius: Float = 1.1
        let count = words.count

        for (i, word) in words.enumerated() {
            let angle = Float(i) * (2 * .pi / Float(count)) - .pi / 2
            // Spread words on a gentle arc in front of the user.
            let pos = SIMD3<Float>(
                cos(angle) * radius * 0.9,
                sin(Float(i) * 0.7) * 0.15,
                -abs(sin(angle)) * radius * 0.4
            )

            let entity = makeWordEntity(text: word.text, homePosition: pos)
            entity.position = pos
            wordsParent.addChild(entity)
        }
    }

    private func makeWordEntity(text: String, homePosition: SIMD3<Float>) -> ModelEntity {
        let mesh = MeshResource.generateText(
            text,
            extrusionDepth: 0.04,
            font: .systemFont(ofSize: 0.12, weight: .heavy),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byTruncatingTail
        )

        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: .cyan)
        material.roughness = 0.25
        material.metallic = 0.85
        material.emissiveColor = .init(color: UIColor.cyan.withAlphaComponent(0.6))

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = text

        // Center the extruded text on its bounds so dragging feels natural.
        let bounds = mesh.bounds
        let center = bounds.center
        entity.position = -center

        let wrapper = ModelEntity()
        wrapper.addChild(entity)
        wrapper.components.set(QuizWordComponent(wordText: text, homePosition: homePosition))
        wrapper.components.set(InputTargetComponent(allowedInputTypes: .all))
        wrapper.components.set(HoverEffectComponent())

        let collisionExtents = SIMD3<Float>(
            max(bounds.extents.x, 0.1),
            max(bounds.extents.y, 0.1),
            max(bounds.extents.z, 0.05)
        )
        wrapper.components.set(CollisionComponent(shapes: [
            .generateBox(size: collisionExtents)
        ]))

        return wrapper
    }

    // MARK: - Floating Animation

    private func startFloatAnimation() {
        floatTask = Task { @MainActor in
            var t: Float = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                t += 0.05

                for (i, child) in wordsParent.children.enumerated() {
                    guard let comp = child.components[QuizWordComponent.self] else { continue }
                    // Skip entities the user is interacting with or has already thrown.
                    let id = ObjectIdentifier(child)
                    if dragStates[id] != nil { continue }
                    if throwTasks[id] != nil { continue }
                    if comp.isFree { continue }

                    let phase = Float(i) * 0.6
                    let bob = sin(t + phase) * 0.03
                    let sway = cos(t * 0.7 + phase) * 0.02
                    child.position = comp.homePosition + SIMD3<Float>(sway, bob, 0)
                    child.transform.rotation = simd_quatf(angle: sin(t * 0.4 + phase) * 0.1, axis: [0, 1, 0])
                }
            }
        }
    }

    // MARK: - Gestures

    private func findWordEntity(_ entity: Entity) -> Entity? {
        var current: Entity? = entity
        while let e = current {
            if e.components[QuizWordComponent.self] != nil { return e }
            current = e.parent
        }
        return nil
    }

    private func handleTap(on entity: Entity) {
        guard let wordEntity = findWordEntity(entity),
              let comp = wordEntity.components[QuizWordComponent.self],
              quizViewModel.isActive,
              quizViewModel.lastResult == nil else { return }

        let correct = quizViewModel.checkAnswer(comp.wordText)
        animateAnswer(entity: wordEntity, correct: correct)
    }

    private func handleDragChanged(_ value: EntityTargetValue<DragGesture.Value>) {
        guard let wordEntity = findWordEntity(value.entity) else { return }
        let id = ObjectIdentifier(wordEntity)

        // Cancel any in-flight throw — the user has grabbed the word.
        if let existing = throwTasks.removeValue(forKey: id) {
            existing.cancel()
        }

        let now = CACurrentMediaTime()
        let translation = value.convert(value.translation3D, from: .local, to: .scene)

        if dragStates[id] == nil {
            let startPos = wordEntity.position(relativeTo: nil)
            dragStates[id] = DragState(
                startPosition: startPos,
                startRotation: wordEntity.transform.rotation,
                lastPosition: startPos,
                lastTime: now,
                velocity: .zero
            )
        }

        guard var state = dragStates[id] else { return }

        let newPos = state.startPosition + translation
        let dt = max(Float(now - state.lastTime), 1.0 / 240.0)
        let instantaneous = (newPos - state.lastPosition) / dt
        // Low-pass filter so a sudden flick doesn't dominate; still tracks throws.
        let smoothed = state.velocity * 0.6 + instantaneous * 0.4

        state.lastPosition = newPos
        state.lastTime = now
        state.velocity = smoothed
        dragStates[id] = state

        wordEntity.setPosition(newPos, relativeTo: nil)

        // Apply a subtle tilt in the direction of motion so the word leans into
        // the throw. Combined with the user's accumulated rotation.
        let tilt = motionTilt(velocity: smoothed)
        wordEntity.transform.rotation = tilt * state.startRotation
    }

    private func handleDragEnded(_ value: EntityTargetValue<DragGesture.Value>) {
        guard let wordEntity = findWordEntity(value.entity) else { return }
        let id = ObjectIdentifier(wordEntity)
        let state = dragStates.removeValue(forKey: id)
        let velocity = state?.velocity ?? .zero

        guard let comp = wordEntity.components[QuizWordComponent.self] else { return }

        // Decide whether the release counts as an answer attempt: either the
        // word ended up near the definition card or it was thrown toward it
        // with enough velocity that the predicted landing point is near it.
        let releasePos = wordEntity.position(relativeTo: nil)
        let defPos = definitionAnchor.position(relativeTo: nil)
        let predictedLanding = releasePos + velocity * 0.35

        let nearOnRelease = simd_distance(releasePos, defPos) < 0.55
        let predictedNear = simd_distance(predictedLanding, defPos) < 0.55
            && simd_length(velocity) > 0.6

        if quizViewModel.isActive,
           quizViewModel.lastResult == nil,
           nearOnRelease || predictedNear {
            let correct = quizViewModel.checkAnswer(comp.wordText)
            animateAnswer(entity: wordEntity, correct: correct)
            return
        }

        // Mark the word as free so the float loop leaves it alone, then let it
        // coast to a stop with friction-based deceleration and gentle tumbling.
        var updated = comp
        updated.isFree = true
        wordEntity.components.set(updated)

        startThrow(entity: wordEntity, initialVelocity: velocity)
    }

    private func handleRotateChanged(_ value: EntityTargetValue<RotateGesture3D.Value>) {
        guard let wordEntity = findWordEntity(value.entity) else { return }
        let id = ObjectIdentifier(wordEntity)

        // Don't fight with an active drag — drag's tilt rewrites rotation each frame.
        if dragStates[id] != nil { return }

        // A rotate cancels any in-flight throw so the word holds still.
        if let throwing = throwTasks.removeValue(forKey: id) {
            throwing.cancel()
        }

        if rotationStarts[id] == nil {
            rotationStarts[id] = wordEntity.transform.rotation
        }
        guard let base = rotationStarts[id] else { return }

        let q = value.rotation.quaternion
        let delta = simd_quatf(
            ix: Float(q.imag.x),
            iy: Float(q.imag.y),
            iz: Float(q.imag.z),
            r: Float(q.real)
        )
        wordEntity.transform.rotation = delta * base

        // Manual rotation also frees the word from the orbit's bobbing motion.
        if var comp = wordEntity.components[QuizWordComponent.self], !comp.isFree {
            comp.isFree = true
            wordEntity.components.set(comp)
        }
    }

    private func handleRotateEnded(_ value: EntityTargetValue<RotateGesture3D.Value>) {
        guard let wordEntity = findWordEntity(value.entity) else { return }
        rotationStarts.removeValue(forKey: ObjectIdentifier(wordEntity))
    }

    // MARK: - Throw Simulation

    /// Returns a small tilt rotation that leans the word in the direction of
    /// motion. Capped so the text stays legible.
    private func motionTilt(velocity: SIMD3<Float>) -> simd_quatf {
        let pitch = max(-0.35, min(0.35, -velocity.y * 0.4))
        let roll = max(-0.45, min(0.45, -velocity.x * 0.4))
        let yaw = max(-0.25, min(0.25, velocity.x * 0.15))
        let qPitch = simd_quatf(angle: pitch, axis: [1, 0, 0])
        let qRoll = simd_quatf(angle: roll, axis: [0, 0, 1])
        let qYaw = simd_quatf(angle: yaw, axis: [0, 1, 0])
        return qYaw * qPitch * qRoll
    }

    private func startThrow(entity: Entity, initialVelocity: SIMD3<Float>) {
        let id = ObjectIdentifier(entity)
        // If velocity is tiny, just leave the word where it sits — no animation.
        guard simd_length(initialVelocity) > 0.05 else { return }

        let task = Task { @MainActor in
            var velocity = initialVelocity
            // Tumble axis is perpendicular to the throw direction so the word
            // rotates end-over-end naturally.
            let tumbleAxis = normalizeOrDefault(simd_cross(velocity, SIMD3<Float>(0, 1, 0)),
                                                fallback: SIMD3<Float>(1, 0, 0))
            let tumbleSpeed = min(simd_length(initialVelocity) * 1.5, 6.0)

            // Tunable friction (per-second multiplier) and termination threshold.
            let friction: Float = 2.2
            let minSpeed: Float = 0.05
            let timestep: Float = 1.0 / 60.0

            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                if Task.isCancelled { break }

                // Exponential velocity decay — feels like a soft drag on the word.
                let decay = expf(-friction * timestep)
                velocity *= decay

                let pos = entity.position(relativeTo: nil) + velocity * timestep
                entity.setPosition(pos, relativeTo: nil)

                // Tumble — angular speed decays alongside linear speed so the word
                // settles upright-ish.
                let speedFactor = simd_length(velocity) / max(simd_length(initialVelocity), 0.001)
                let stepAngle = tumbleSpeed * speedFactor * timestep
                let stepRot = simd_quatf(angle: stepAngle, axis: tumbleAxis)
                entity.transform.rotation = stepRot * entity.transform.rotation

                if simd_length(velocity) < minSpeed { break }
            }

            // Settle: ease the residual tilt back toward upright so the word is
            // readable wherever it landed.
            if !Task.isCancelled {
                var target = entity.transform
                target.rotation = settledRotation(from: entity.transform.rotation)
                entity.move(to: target, relativeTo: entity.parent, duration: 0.4,
                            timingFunction: .easeOut)
            }

            throwTasks.removeValue(forKey: id)
        }

        throwTasks[id] = task
    }

    private func normalizeOrDefault(_ v: SIMD3<Float>, fallback: SIMD3<Float>) -> SIMD3<Float> {
        let len = simd_length(v)
        return len > 0.0001 ? v / len : fallback
    }

    /// Reduces an arbitrary rotation toward a gentler, near-upright orientation
    /// so a thrown word remains legible after it settles.
    private func settledRotation(from rotation: simd_quatf) -> simd_quatf {
        let halfAngle = rotation.angle * 0.35
        return simd_quatf(angle: halfAngle, axis: rotation.axis)
    }

    // MARK: - Answer Animation

    private func animateAnswer(entity: Entity, correct: Bool) {
        guard let modelEntity = entity.children.first as? ModelEntity else { return }

        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: correct ? .systemGreen : .systemRed)
        material.roughness = 0.2
        material.metallic = 0.9
        material.emissiveColor = .init(color: (correct ? UIColor.systemGreen : UIColor.systemRed)
            .withAlphaComponent(0.8))
        modelEntity.model?.materials = [material]

        if correct {
            // Animate to the definition anchor in world space so it works
            // regardless of where the user released the word.
            let defWorldPos = definitionAnchor.position(relativeTo: nil)
            entity.setParent(sceneRoot, preservingWorldTransform: true)
            var target = entity.transform
            target.translation = defWorldPos
            target.scale = SIMD3<Float>(repeating: 0.01)
            entity.move(to: target, relativeTo: sceneRoot, duration: 0.6, timingFunction: .easeIn)
        } else {
            let original = entity.transform
            Task { @MainActor in
                for offset in [-0.06, 0.06, -0.04, 0.04, 0.0] as [Float] {
                    var shake = original
                    shake.translation.x += offset
                    entity.move(to: shake, relativeTo: entity.parent, duration: 0.07)
                    try? await Task.sleep(for: .milliseconds(70))
                }
            }
        }
    }

    // MARK: - Result Card

    @ViewBuilder
    private func resultCard(_ result: QuizViewModel.AnswerResult) -> some View {
        VStack(spacing: 14) {
            switch result {
            case .correct:
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.green)
                Text("Correct!")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.green)
            case .incorrect(let correctWord):
                Image(systemName: "xmark.seal.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.red)
                Text("Not quite")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.red)
                Text("Answer: \(correctWord)")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(28)
        .frame(width: 460)
        .glassBackgroundEffect()
    }
}

#Preview(immersionStyle: .full) {
    QuizImmersiveView()
        .environment(AppModel())
        .environment(QuizViewModel())
}
