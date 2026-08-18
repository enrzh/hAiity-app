import AppIntents
import Foundation

/// A palette selectable in a widget configuration. The raw ID is the same
/// value persisted by PaletteRef, so app and widget never maintain separate
/// palette identifiers.
struct GraphPaletteEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Farbe")
    static var defaultQuery = GraphPaletteEntityQuery()

    let id: String
    let name: String

    var paletteRef: PaletteRef {
        PaletteRef(rawValue: id) ?? .default
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: .init(stringLiteral: name))
    }

    init(ref: PaletteRef, name: String) {
        self.id = ref.rawValue
        self.name = name
    }
}

struct GraphPaletteEntityQuery: EntityQuery {
    let dataURL: URL

    init() {
        self.dataURL = SharedStorage.dataURL()
    }

    init(dataURL: URL) {
        self.dataURL = dataURL
    }

    private func all() -> [GraphPaletteEntity] {
        let data = HabitStore.read(dataURL) ?? .empty
        let builtIns = GraphPalette.allCases.map {
            GraphPaletteEntity(ref: .builtin($0), name: $0.displayName)
        }
        let custom = data.customPalettes.map {
            GraphPaletteEntity(ref: .custom($0.id), name: $0.displayName)
        }
        return builtIns + custom
    }

    func entities(for identifiers: [String]) async throws -> [GraphPaletteEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [GraphPaletteEntity] {
        all()
    }

    func defaultResult() async -> GraphPaletteEntity? {
        all().first { $0.paletteRef == .default }
    }
}
