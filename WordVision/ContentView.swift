import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(QuizViewModel.self) private var quizViewModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Query(sort: \Word.dateAdded, order: .reverse) private var words: [Word]
    @Environment(\.modelContext) private var modelContext

    @State private var searchText = ""
    @State private var showingAddSheet = false
    @State private var editingWord: Word?

    private var filteredWords: [Word] {
        guard !searchText.isEmpty else { return words }
        return words.filter {
            $0.text.localizedCaseInsensitiveContains(searchText) ||
            $0.definition.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if quizViewModel.isComplete {
                    quizCompleteView
                } else if quizViewModel.isActive {
                    quizActiveView
                } else {
                    browsingView
                }
            }
            .navigationTitle("Word Vision")
            .toolbar {
                if !quizViewModel.isActive && !quizViewModel.isComplete {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showingAddSheet = true
                        } label: {
                            Label("Add Word", systemImage: "plus")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddEditWordSheet(word: nil)
        }
        .sheet(item: $editingWord) { word in
            AddEditWordSheet(word: word)
        }
        .onAppear {
            if words.isEmpty {
                addSampleWords()
            }
        }
    }

    // MARK: - Browsing

    private var browsingView: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("My Dictionary")
                    .font(.title2.bold())

                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search words...", text: $searchText)
                }
                .padding(10)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                if words.isEmpty {
                    emptyStateView
                } else {
                    List {
                        ForEach(filteredWords) { word in
                            wordRow(for: word)
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                let word = filteredWords[index]
                                appModel.chosenWords.removeAll { $0.id == word.id }
                                modelContext.delete(word)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()

            Divider()

            VStack(spacing: 16) {
                Text("Quiz Words")
                    .font(.title2.bold())

                if appModel.chosenWords.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("Tap + on words to\nadd them to the quiz")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(appModel.chosenWords) { word in
                                HStack {
                                    Text(word.text)
                                        .font(.body.bold())
                                    Spacer()
                                    Button {
                                        withAnimation(.spring(response: 0.3)) {
                                            appModel.chosenWords.removeAll { $0.id == word.id }
                                        }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.borderless)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(.blue.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }

                Divider()

                VStack(spacing: 12) {
                    if appModel.chosenWords.count >= 2 {
                        Button {
                            startImmersiveQuiz()
                        } label: {
                            Label("Start Immersive Quiz (\(appModel.chosenWords.count) words)",
                                  systemImage: "visionpro")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(appModel.quizImmersiveSpaceState == .inTransition)
                    } else {
                        Text("Select at least 2 words")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    immersiveSpaceButton
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
    }

    // MARK: - Quiz Active (window companion)

    private var quizActiveView: some View {
        VStack(spacing: 24) {
            Image(systemName: "visionpro")
                .font(.system(size: 64))
                .foregroundStyle(.cyan)

            Text("Quiz in Immersive Space")
                .font(.largeTitle.bold())

            Text("Look around — definitions float in front of you and the answer words drift in 3D. Pinch and drag a word onto the definition card, or tap one to answer.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 560)

            HStack(spacing: 40) {
                statBubble(title: "Score", value: quizViewModel.scoreText, color: .blue)
                statBubble(title: "Progress", value: quizViewModel.progress, color: .purple)
            }

            if appModel.quizImmersiveSpaceState != .open {
                Button {
                    startImmersiveQuiz()
                } label: {
                    Label("Re-enter Immersive Space", systemImage: "visionpro")
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(appModel.quizImmersiveSpaceState == .inTransition)
            }

            Spacer()

            Button("End Quiz") {
                endImmersiveQuiz()
            }
            .foregroundStyle(.red)
        }
        .padding(30)
    }

    // MARK: - Quiz Complete

    private var quizCompleteView: some View {
        VStack(spacing: 24) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 80))
                .foregroundStyle(.yellow)

            Text("Quiz Complete!")
                .font(.largeTitle.bold())

            let percentage = quizViewModel.quizWords.isEmpty ? 0 :
                Int(Double(quizViewModel.score) / Double(quizViewModel.quizWords.count) * 100)

            Text("\(percentage)%")
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(percentage >= 70 ? .green : percentage >= 50 ? .orange : .red)

            Text("\(quizViewModel.score) out of \(quizViewModel.quizWords.count) correct")
                .font(.title2)
                .foregroundStyle(.secondary)

            Button {
                endImmersiveQuiz()
            } label: {
                Label("Back to Words", systemImage: "arrow.left")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(30)
    }

    // MARK: - Quiz Lifecycle

    private func startImmersiveQuiz() {
        Task {
            // Close the mixed-immersion browsing space first; visionOS allows
            // only one immersive space open at a time.
            if appModel.immersiveSpaceState == .open {
                appModel.immersiveSpaceState = .inTransition
                await dismissImmersiveSpace()
            }

            quizViewModel.startQuiz(with: appModel.chosenWords)
            appModel.appPhase = .quiz

            appModel.quizImmersiveSpaceState = .inTransition
            switch await openImmersiveSpace(id: appModel.quizImmersiveSpaceID) {
            case .opened: break
            case .userCancelled, .error: fallthrough
            @unknown default:
                appModel.quizImmersiveSpaceState = .closed
            }
        }
    }

    private func endImmersiveQuiz() {
        Task {
            quizViewModel.endQuiz()
            appModel.appPhase = .browsing
            if appModel.quizImmersiveSpaceState == .open {
                appModel.quizImmersiveSpaceState = .inTransition
                await dismissImmersiveSpace()
            }
        }
    }

    // MARK: - Components

    private func wordRow(for word: Word) -> some View {
        let isChosen = appModel.chosenWords.contains { $0.id == word.id }

        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(word.text)
                    .font(.headline)
                Text(word.definition)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button {
                editingWord = word
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)

            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    if isChosen {
                        appModel.chosenWords.removeAll { $0.id == word.id }
                    } else {
                        appModel.chosenWords.append(word)
                    }
                }
            } label: {
                Image(systemName: isChosen ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(isChosen ? .green : .blue)
                    .font(.title3)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No words yet")
                .font(.title3)
            Text("Tap + to add your first word")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func statBubble(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title.bold())
                .foregroundStyle(color)
        }
        .padding()
        .glassBackgroundEffect()
    }

    private var immersiveSpaceButton: some View {
        Button {
            Task {
                switch appModel.immersiveSpaceState {
                case .open:
                    appModel.immersiveSpaceState = .inTransition
                    await dismissImmersiveSpace()
                case .closed:
                    if appModel.quizImmersiveSpaceState == .open {
                        appModel.quizImmersiveSpaceState = .inTransition
                        await dismissImmersiveSpace()
                    }
                    appModel.immersiveSpaceState = .inTransition
                    switch await openImmersiveSpace(id: appModel.immersiveSpaceID) {
                    case .opened: break
                    case .userCancelled, .error: fallthrough
                    @unknown default:
                        appModel.immersiveSpaceState = .closed
                    }
                case .inTransition:
                    break
                }
            }
        } label: {
            Label(
                appModel.immersiveSpaceState == .open ? "Exit 3D Space" : "Browse Words in 3D",
                systemImage: appModel.immersiveSpaceState == .open ? "xmark.circle" : "visionpro"
            )
        }
        .disabled(appModel.immersiveSpaceState == .inTransition)
    }

    // MARK: - Sample Data

    private func addSampleWords() {
        let samples: [(String, String, String)] = [
            ("Ephemeral", "Lasting for a very short time", "The beauty of cherry blossoms is ephemeral."),
            ("Ubiquitous", "Present, appearing, or found everywhere", "Smartphones have become ubiquitous in modern society."),
            ("Eloquent", "Fluent or persuasive in speaking or writing", "Her eloquent speech moved the audience to tears."),
            ("Serendipity", "The occurrence of events by chance in a happy way", "Finding that bookshop was pure serendipity."),
            ("Resilient", "Able to recover quickly from difficulties", "Children are remarkably resilient creatures."),
            ("Pragmatic", "Dealing with things in a practical way", "She took a pragmatic approach to the problem."),
            ("Candid", "Truthful and straightforward; frank", "He gave a candid assessment of the situation."),
            ("Tenacious", "Holding firmly to something; persistent", "Her tenacious spirit helped her overcome obstacles."),
        ]
        for (text, definition, example) in samples {
            modelContext.insert(Word(text: text, definition: definition, example: example))
        }
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
        .environment(QuizViewModel())
        .modelContainer(for: Word.self, inMemory: true)
}
