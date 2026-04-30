import SwiftUI
import RealityKit
import RealityKitContent

struct WordComponent: Component {
    var wordText: String
}

struct ImmersiveView: View {
    @Environment(AppModel.self) private var appModel

    @State private var rootEntity = Entity()
    @State private var orbitParent = Entity()
    @State private var orbitTask: Task<Void, Never>?

    var body: some View {
        RealityView { content in
            rootEntity.position = [0, 1.5, -2]
            content.add(rootEntity)

            orbitParent.name = "orbit"
            rootEntity.addChild(orbitParent)

        } update: { _ in
            syncBrowsingEntities()
        }
        .onAppear { startOrbit() }
        .onDisappear { orbitTask?.cancel() }
    }

    // MARK: - Entity Sync

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
}

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environment(AppModel())
}
