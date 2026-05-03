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
    @State private var floatTask: Task<Void, Never>?
    @State private var lastSyncedQuestion = -1
    @State private var subscriptions: [EventSubscription] = []
    
    var body: some View {
        RealityView { content, attachments in
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
                controlsAnchor.position = [0, 1.45, -1.3]
                controlsAnchor.addChild(controls)
                sceneRoot.addChild(controlsAnchor)
            }
            
            let beginSub = content.subscribe(to: ManipulationEvents.WillBegin.self) { event in
                handleManipulationBegin(entity: event.entity)
            }
            let releaseSub = content.subscribe(to: ManipulationEvents.WillRelease.self) { event in
                handleManipulationRelease(entity: event.entity)
            }
            subscriptions.append(beginSub)
            subscriptions.append(releaseSub)
            
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
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in handleTap(on: value.entity) }
        )
        .onAppear {
            startFloatAnimation()
        }
        .onDisappear {
            floatTask?.cancel()
            subscriptions.removeAll()
        }
    }
    
    // MARK: - Sync Word Entities
    
    private func syncWordEntities() {
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
        
        let radius: Float = 1.4
        let count = words.count
        
        for (i, word) in words.enumerated() {
            let angle = Float(i) * (2 * .pi / Float(count)) - .pi / 2
            let pos = SIMD3<Float>(
                cos(angle) * radius * 0.9,
                sin(Float(i) * 0.7) * 0.18,
                -abs(sin(angle)) * radius * 0.4
            )
            
            let entity = makeWordEntity(text: word.text, homePosition: pos)
            entity.position = pos
            wordsParent.addChild(entity)
        }
    }
    
    private func makeWordEntity(text: String, homePosition: SIMD3<Float>) -> Entity {
        let mesh = MeshResource.generateText(
            text,
            extrusionDepth: 0.07,
            font: .systemFont(ofSize: 0.20, weight: .heavy),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byTruncatingTail
        )
        
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: 0.45, green: 0.85, blue: 1.0, alpha: 1.0))
        material.roughness = 0.18
        material.metallic = 0.95
        material.emissiveColor = .init(color: UIColor(red: 0.2, green: 0.7, blue: 1.0, alpha: 1.0))
        material.emissiveIntensity = 0.6
        material.clearcoat = 0.8
        material.clearcoatRoughness = 0.15
        
        let textEntity = ModelEntity(mesh: mesh, materials: [material])
        textEntity.name = "\(text)-mesh"
        
        let bounds = mesh.bounds
        let center = bounds.center
        textEntity.position = -center
        
        let wrapper = Entity()
        wrapper.name = text
        wrapper.addChild(textEntity)
        wrapper.components.set(QuizWordComponent(wordText: text, homePosition: homePosition))
        
        let extents = bounds.extents
        let collisionExtents = SIMD3<Float>(
            max(extents.x, 0.12),
            max(extents.y, 0.12),
            max(extents.z, 0.08)
        )
        let collisionShape = ShapeResource.generateBox(size: collisionExtents)
        
        ManipulationComponent.configureEntity(
            wrapper,
            hoverEffect: .spotlight(.init()),
            allowedInputTypes: .all,
            collisionShapes: [collisionShape]
        )
        
        if var manipulation = wrapper.components[ManipulationComponent.self] {
            manipulation.releaseBehavior = .stay
            wrapper.components.set(manipulation)
        }
        
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
                    if comp.isFree { continue }
                    
                    let phase = Float(i) * 0.6
                    let bob = sin(t + phase) * 0.04
                    let sway = cos(t * 0.7 + phase) * 0.025
                    child.position = comp.homePosition + SIMD3<Float>(sway, bob, 0)
                    child.transform.rotation = simd_quatf(angle: sin(t * 0.4 + phase) * 0.12, axis: [0, 1, 0])
                }
            }
        }
    }
    
    // MARK: - Manipulation Events
    
    private func handleManipulationBegin(entity: Entity) {
        if var comp = entity.components[QuizWordComponent.self], !comp.isFree {
            comp.isFree = true
            entity.components.set(comp)
        }
        
        if entity.components[PhysicsBodyComponent.self] == nil {
            var body = PhysicsBodyComponent(
                massProperties: .init(mass: 0.4),
                material: .generate(staticFriction: 0.4, dynamicFriction: 0.4, restitution: 0.2),
                mode: .dynamic
            )
            body.isAffectedByGravity = false
            body.linearDamping = 0.7
            body.angularDamping = 0.7
            entity.components.set(body)
        }
    }
    
    private func handleManipulationRelease(entity: Entity) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            
            guard quizViewModel.isActive,
                  quizViewModel.lastResult == nil,
                  let comp = entity.components[QuizWordComponent.self],
                  entity.parent != nil else { return }
            
            let pos = entity.position(relativeTo: nil)
            let defPos = definitionAnchor.position(relativeTo: nil)
            
            if simd_distance(pos, defPos) < 0.6 {
                let correct = quizViewModel.checkAnswer(comp.wordText)
                animateAnswer(entity: entity, correct: correct)
            }
        }
    }
    
    // MARK: - Tap
    
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
    
    // MARK: - Answer Animation
    
    private func animateAnswer(entity: Entity, correct: Bool) {
        entity.components.remove(PhysicsBodyComponent.self)
        entity.components.remove(PhysicsMotionComponent.self)
        entity.components.remove(ManipulationComponent.self)
        
        guard let modelEntity = entity.children.first as? ModelEntity else { return }
        
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: correct ? .systemGreen : .systemRed)
        material.roughness = 0.2
        material.metallic = 0.9
        material.emissiveColor = .init(color: correct ? UIColor.systemGreen : UIColor.systemRed)
        material.emissiveIntensity = 0.9
        material.clearcoat = 0.7
        modelEntity.model?.materials = [material]
        
        if correct {
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
