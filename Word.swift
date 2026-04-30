import SwiftData
import Foundation

@Model
final class Word {
    var text: String
    var definition: String
    var example: String
    var dateAdded: Date

    init(text: String, definition: String, example: String = "", dateAdded: Date = .now) {
        self.text = text
        self.definition = definition
        self.example = example
        self.dateAdded = dateAdded
    }
}
