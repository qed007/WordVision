import SwiftUI

@MainActor
@Observable
class QuizViewModel {
    var quizWords: [Word] = []
    var currentQuestionIndex = 0
    var score = 0
    var totalAnswered = 0
    var isActive = false
    var lastResult: AnswerResult?
    var isComplete = false

    enum AnswerResult {
        case correct
        case incorrect(correctWord: String)
    }

    var currentDefinition: String? {
        guard isActive, currentQuestionIndex < quizWords.count else { return nil }
        return quizWords[currentQuestionIndex].definition
    }

    var currentAnswer: Word? {
        guard isActive, currentQuestionIndex < quizWords.count else { return nil }
        return quizWords[currentQuestionIndex]
    }

    var progress: String {
        "\(totalAnswered)/\(quizWords.count)"
    }

    var scoreText: String {
        "\(score)/\(totalAnswered)"
    }

    func startQuiz(with words: [Word]) {
        guard words.count >= 2 else { return }
        quizWords = words.shuffled()
        currentQuestionIndex = 0
        score = 0
        totalAnswered = 0
        isActive = true
        isComplete = false
        lastResult = nil
    }

    func checkAnswer(_ wordText: String) -> Bool {
        guard let answer = currentAnswer else { return false }
        let correct = wordText == answer.text
        totalAnswered += 1
        if correct {
            score += 1
            lastResult = .correct
        } else {
            lastResult = .incorrect(correctWord: answer.text)
        }
        return correct
    }

    func nextQuestion() {
        lastResult = nil
        currentQuestionIndex += 1
        if currentQuestionIndex >= quizWords.count {
            isComplete = true
            isActive = false
        }
    }

    func endQuiz() {
        isActive = false
        isComplete = false
        lastResult = nil
        quizWords = []
        currentQuestionIndex = 0
        score = 0
        totalAnswered = 0
    }
}
