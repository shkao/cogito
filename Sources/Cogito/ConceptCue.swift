import Foundation

// MARK: - Feynman Technique Step

enum FeynmanStep: Int, Codable, Comparable {
    case explain = 2    // step 2: write your explanation
    case reviewed = 3   // step 3: gaps identified by LLM
    case refined = 4    // step 4: refined, model comparison available

    static func < (lhs: FeynmanStep, rhs: FeynmanStep) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Concept Cue

struct ConceptCue: Codable, Identifiable {
    let id: UUID
    let concept: String
    let promptQuestion: String
    let pageIndex: Int
    var userExplanation: String
    var gapFeedback: [String]?
    var modelExplanation: String?
    var step: FeynmanStep

    init(concept: String, promptQuestion: String, pageIndex: Int) {
        self.id = UUID()
        self.concept = concept
        self.promptQuestion = promptQuestion
        self.pageIndex = pageIndex
        self.userExplanation = ""
        self.gapFeedback = nil
        self.modelExplanation = nil
        self.step = .explain
    }
}

// MARK: - Persistence container

struct ConceptCueStore: Codable {
    var cues: [ConceptCue]
    var chapterLabel: String
}
