import SwiftUI
import RealityKit
import RealityKitContent

struct WordComponent: Component {
    var wordText: String
}

struct ImmersiveView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(QuizViewModel.self) private var quizViewModel

    @State private var rootEntity = Entity()
    @State private var orbitParent = Entity()
    @State private var quizOrbitParent = Entity()
    @State private var definitionAttachment: Entity?
    @State private var scoreAttachment: Entity?
    @State private var orbitTask: Task<Void, Never>?
    @State private var dragStartPositions: [ObjectIdentifier: SIMD3<Float>] = [:]

    var body: some View {
        RealityView { content, attachments in
            rootEntity.position = [0, 1.5, -2]
            content.add(rootEntity)

            orbitParent.name = "orbit"
            rootEntity.addChild(orbitParent)

            quizOrbitParent.name = "quizOrbit"
            quizOrbitParent.isEnabled = false
            rootEntity.addChild(quizOrbitParent)

            if let def = attachments.entity(for: "definition") {
                def.position = [0, 0.3, 0]
                def.isEnabled = false
                definitionAttachment = def
                rootEntity.addChild(def)
            }

            if let score = attachments.entity(for: "score") {
                score.position = [0, 0.8, 0]
                score.isEnabled = false
                scoreAttachment = score
                rootEntity.addChild(score)
            }

        } update: { content, attachments in
            syncEntities()

        } attachments: {
            Attachment(id: "definition") {
                if let definition = quizViewModel.currentDefinition {
                    VStack(spacing: 12) {
                        Image(systemName: "questionmark.circle")
                            .font(.title)
                            .foregroundStyle(.blue)

                        Text("What word matches this definition?")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(definition)
                            .font(.title3.bold())
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                    .padding(24)
                    .frame(width: 400)
                    .glassBackgroundEffect()
                }
            }

            Attachment(id: "score") {
                if quizViewModel.isActive {
                    HStack(spacing: 20) {
                        Label("\(quizViewModel.score)", systemImage: "star.fill")
                            .foregroundStyle(.yellow)
                        Text("\(quizViewModel.totalAnswered)/\(quizViewModel.quizWords.count)")
                            .foregroundStyle(.secondary)
                    }
                    .font(.title2.bold())
                    .padding(16)
                    .glassBackgroundEffect()
                }
            }
        }
        .gesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    handleTap(on: value.entity)
                }
        )
        .gesture(
            DragGesture()
                .targetedToAnyEntity()
                .onChanged { value in
                    handleDragChanged(value)
                }
                .onEnded { value in
                    handleDragEnded(value)
                }
        )
        .onAppear { startOrbit() }
        .onDisappear { orbitTask?.cancel() }
    }

    // MARK: - Entity Sync

    private func syncEntities() {
        if appModel.appPhase == .quiz && quizViewModel.isActive {
            orbitParent.isEnabled = false
            quizOrbitParent.isEnabled = true
            definitionAttachment?.isEnabled = true
            scoreAttachment?.isEnabled = true
            syncQuizEntities()
        } else if quizViewModel.isComplete {
            orbitParent.isEnabled = false
            quizOrbitParent.isEnabled = false
            definitionAttachment?.isEnabled = false
            scoreAttachment?.isEnabled = false
        } else {
            orbitParent.isEnabled = true
            quizOrbitParent.isEnabled = false
            definitionAttachment?.isEnabled = false
            scoreAttachment?.isEnabled = false
            syncBrowsingEntities()
        }
    }

    private func syncBrowsingEntities() {
        let existingTexts = Set(orbitParent.children.compactMap {
            $0.components[WordComponent.self]?.wordText
        })
        let chosenTexts = Set(appModel.chosenWords.map(\.text))

        for child in Array(orbitParent.children) {
            if let comp = child.components[WordComponent.self],
               !chosenTexts.contains(comp.wordText) {
                child.removeFromParent()
            }
        }

        for word in appModel.chosenWords where !existingTexts.contains(word.text) {
            let entity = makeWordEntity(text: word.text, color: .white)
            orbitParent.addChild(entity)
        }

        repositionOrbitChildren(parent: orbitParent, radius: 0.5)
    }

    private func syncQuizEntities() {
        let existingTexts = Set(quizOrbitParent.children.compactMap {
            $0.components[WordComponent.self]?.wordText
        })
        let quizTexts = Set(quizViewModel.quizWords.map(\.text))

        if existingTexts != quizTexts {
            for child in Array(quizOrbitParent.children) {
                child.removeFromParent()
            }
            for word in quizViewModel.quizWords {
                let entity = makeWordEntity(text: word.text, color: .systemCyan)
                quizOrbitParent.addChild(entity)
            }
            repositionOrbitChildren(parent: quizOrbitParent, radius: 0.8)
        }
    }

    // MARK: - Entity Factory

    private func makeWordEntity(text: String, color: UIColor) -> ModelEntity {
        let mesh = MeshResource.generateText(
            text,
            extrusionDepth: 0.02,
            font: .systemFont(ofSize: 0.06, weight: .bold)
        )
        let material = SimpleMaterial(color: color, roughness: 0.3, isMetallic: true)
        let entity = ModelEntity(mesh: mesh, materials: [material])

        entity.name = text
        entity.components.set(WordComponent(wordText: text))
        entity.components.set(InputTargetComponent(allowedInputTypes: .all))
        entity.generateCollisionShapes(recursive: false)
        entity.components.set(HoverEffectComponent())

        return entity
    }

    // MARK: - Orbit Animation

    private func startOrbit() {
        orbitTask = Task { @MainActor in
            var angle: Float = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                angle += 0.003
                orbitParent.transform.rotation = simd_quatf(angle: angle, axis: [0, 1, 0])
                quizOrbitParent.transform.rotation = simd_quatf(angle: angle * 0.6, axis: [0, 1, 0])
            }
        }
    }

    private func repositionOrbitChildren(parent: Entity, radius: Float) {
        let children = parent.children.filter { $0.components[WordComponent.self] != nil }
        guard !children.isEmpty else { return }

        for (i, child) in children.enumerated() {
            let angle = Float(i) * (2 * .pi / Float(children.count))
            let pos = SIMD3<Float>(cos(angle) * radius, 0, sin(angle) * radius)

            var transform = child.transform
            transform.translation = pos
            child.move(to: transform, relativeTo: parent, duration: 0.5, timingFunction: .easeInOut)
        }
    }

    // MARK: - Gestures

    private func findWordEntity(_ entity: Entity) -> Entity? {
        var current: Entity? = entity
        while let e = current {
            if e.components[WordComponent.self] != nil { return e }
            current = e.parent
        }
        return nil
    }

    private func handleTap(on entity: Entity) {
        guard let wordEntity = findWordEntity(entity),
              let comp = wordEntity.components[WordComponent.self],
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
            if wordEntity.parent == quizOrbitParent {
                let worldPos = wordEntity.position(relativeTo: nil)
                rootEntity.addChild(wordEntity)
                wordEntity.setPosition(worldPos, relativeTo: nil)
            }
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

        guard let comp = wordEntity.components[WordComponent.self],
              quizViewModel.isActive,
              quizViewModel.lastResult == nil else {
            returnToOrbit(wordEntity)
            return
        }

        if let defEntity = definitionAttachment {
            let wordPos = wordEntity.position(relativeTo: nil)
            let defPos = defEntity.position(relativeTo: nil)
            if simd_distance(wordPos, defPos) < 0.4 {
                let correct = quizViewModel.checkAnswer(comp.wordText)
                animateAnswer(entity: wordEntity, correct: correct)
                return
            }
        }

        returnToOrbit(wordEntity)
    }

    private func returnToOrbit(_ entity: Entity) {
        guard entity.parent != quizOrbitParent else { return }
        let worldPos = entity.position(relativeTo: nil)
        quizOrbitParent.addChild(entity)
        entity.setPosition(worldPos, relativeTo: nil)
        repositionOrbitChildren(parent: quizOrbitParent, radius: 0.8)
    }

    // MARK: - Answer Animation

    private func animateAnswer(entity: Entity, correct: Bool) {
        guard let modelEntity = entity as? ModelEntity else { return }

        let color: UIColor = correct ? .systemGreen : .systemRed
        modelEntity.model?.materials = [SimpleMaterial(color: color, roughness: 0.3, isMetallic: true)]

        if correct {
            if let defEntity = definitionAttachment {
                let targetPos = defEntity.position(relativeTo: entity.parent)
                var target = entity.transform
                target.translation = targetPos
                target.scale = SIMD3<Float>(repeating: 0.01)
                entity.move(to: target, relativeTo: entity.parent, duration: 0.5, timingFunction: .easeIn)
            }
        } else {
            let original = entity.transform
            Task { @MainActor in
                for offset in [-0.05, 0.05, -0.03, 0.03, 0.0] as [Float] {
                    var shake = original
                    shake.translation.x += offset
                    entity.move(to: shake, relativeTo: entity.parent, duration: 0.08)
                    try? await Task.sleep(for: .milliseconds(80))
                }
            }
        }
    }
}

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environment(AppModel())
        .environment(QuizViewModel())
}
