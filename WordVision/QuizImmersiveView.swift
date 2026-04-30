import SwiftUI
import RealityKit
import RealityKitContent

struct QuizWordComponent: Component {
    var wordText: String
    var homePosition: SIMD3<Float>
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
    @State private var dragStartPositions: [ObjectIdentifier: SIMD3<Float>] = [:]
    @State private var floatTask: Task<Void, Never>?
    @State private var lastSyncedQuestion = -1

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

                        Text("Grab the matching word")
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
        .gesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in handleTap(on: value.entity) }
        )
        .onAppear { startFloatAnimation() }
        .onDisappear { floatTask?.cancel() }
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
                    // Skip if the user is currently dragging this entity.
                    if dragStartPositions[ObjectIdentifier(child)] != nil { continue }

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
        guard quizViewModel.isActive, quizViewModel.lastResult == nil,
              let wordEntity = findWordEntity(value.entity) else { return }

        let id = ObjectIdentifier(wordEntity)
        if dragStartPositions[id] == nil {
            dragStartPositions[id] = wordEntity.position(relativeTo: nil)
        }
        let startPos = dragStartPositions[id]!
        let translation = value.convert(value.translation3D, from: .local, to: .scene)
        wordEntity.setPosition(startPos + translation, relativeTo: nil)
    }

    private func handleDragEnded(_ value: EntityTargetValue<DragGesture.Value>) {
        guard let wordEntity = findWordEntity(value.entity) else { return }
        let id = ObjectIdentifier(wordEntity)
        defer { dragStartPositions.removeValue(forKey: id) }

        guard let comp = wordEntity.components[QuizWordComponent.self],
              quizViewModel.isActive,
              quizViewModel.lastResult == nil else {
            returnHome(wordEntity)
            return
        }

        let wordWorldPos = wordEntity.position(relativeTo: nil)
        let defWorldPos = definitionAnchor.position(relativeTo: nil)
        if simd_distance(wordWorldPos, defWorldPos) < 0.55 {
            let correct = quizViewModel.checkAnswer(comp.wordText)
            animateAnswer(entity: wordEntity, correct: correct)
        } else {
            returnHome(wordEntity)
        }
    }

    private func returnHome(_ entity: Entity) {
        guard let comp = entity.components[QuizWordComponent.self] else { return }
        var transform = entity.transform
        transform.translation = comp.homePosition
        entity.move(to: transform, relativeTo: wordsParent, duration: 0.4, timingFunction: .easeInOut)
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
            let defPos = definitionAnchor.position(relativeTo: wordsParent)
            var target = entity.transform
            target.translation = defPos
            target.scale = SIMD3<Float>(repeating: 0.01)
            entity.move(to: target, relativeTo: wordsParent, duration: 0.6, timingFunction: .easeIn)
        } else {
            let original = entity.transform
            Task { @MainActor in
                for offset in [-0.06, 0.06, -0.04, 0.04, 0.0] as [Float] {
                    var shake = original
                    shake.translation.x += offset
                    entity.move(to: shake, relativeTo: wordsParent, duration: 0.07)
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
