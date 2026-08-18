import AppIntents

enum GraphWidgetSource: String, AppEnum, CaseIterable, Codable, Sendable {
    case habit
    case github

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Graph")
    }

    static var caseDisplayRepresentations: [GraphWidgetSource: DisplayRepresentation] {
        [
            .habit: DisplayRepresentation(title: "Habit"),
            .github: DisplayRepresentation(title: "GitHub")
        ]
    }
}
