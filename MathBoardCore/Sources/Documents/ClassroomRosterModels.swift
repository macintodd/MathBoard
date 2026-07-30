//
//  ClassroomRosterModels.swift
//  MathBoardCore — Documents module
//

import Foundation
import Observation

struct Classroom: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var alternateIDPrefix: String
    var createdAt: Date
    var modifiedAt: Date
    var students: [RosterStudent]

    init(
        id: UUID = UUID(),
        name: String,
        alternateIDPrefix: String? = nil,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        students: [RosterStudent] = []
    ) {
        self.id = id
        self.name = name
        self.alternateIDPrefix = alternateIDPrefix ?? Self.defaultAlternateIDPrefix(for: name)
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.students = students
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case alternateIDPrefix
        case createdAt
        case modifiedAt
        case students
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        alternateIDPrefix = try container.decodeIfPresent(String.self, forKey: .alternateIDPrefix)
            ?? Self.defaultAlternateIDPrefix(for: name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        modifiedAt = try container.decode(Date.self, forKey: .modifiedAt)
        students = try container.decode([RosterStudent].self, forKey: .students)
    }

    static func defaultAlternateIDPrefix(for name: String) -> String {
        let prefix = name
            .uppercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { String($0.prefix(3)) }
            .joined()
        return prefix.isEmpty ? "CLASS" : prefix
    }
}

struct RosterStudent: Identifiable, Codable, Hashable {
    var id: UUID
    var firstName: String
    var lastName: String
    var officialStudentID: String
    var alternateStudentID: String

    init(
        id: UUID = UUID(),
        firstName: String,
        lastName: String,
        officialStudentID: String,
        alternateStudentID: String = ""
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.officialStudentID = officialStudentID
        self.alternateStudentID = alternateStudentID
    }
}

struct CSVColumnMapping: Equatable {
    var firstNameIndex: Int?
    var lastNameIndex: Int?
    var officialStudentIDIndex: Int?
    var alternateStudentIDIndex: Int?

    var canImport: Bool {
        firstNameIndex != nil && lastNameIndex != nil && officialStudentIDIndex != nil
    }
}

struct RosterCSVPreview: Equatable {
    var headers: [String]
    var rows: [[String]]
    var mapping: CSVColumnMapping
}

struct DuplicateRosterIDReport: Equatable {
    var officialStudentIDs: [String]
    var alternateStudentIDs: [String]

    var hasDuplicates: Bool {
        !officialStudentIDs.isEmpty || !alternateStudentIDs.isEmpty
    }

    var summary: String {
        var parts: [String] = []
        if !officialStudentIDs.isEmpty {
            parts.append("Student ID: \(officialStudentIDs.joined(separator: ", "))")
        }
        if !alternateStudentIDs.isEmpty {
            parts.append("Alternate ID: \(alternateStudentIDs.joined(separator: ", "))")
        }
        return parts.joined(separator: "  ")
    }
}

@MainActor
@Observable
public final class ClassroomRosterStore {
    var classrooms: [Classroom] = []

    private let rootURL: URL?
    private let fileManager: FileManager
    private static let directoryName = "Class Rosters"
    private static let storeFileName = "rosters.json"

    public init() {
        self.fileManager = .default
        self.rootURL = Self.locateRootURL(using: fileManager)
        reload()
    }

    init(rootURL: URL, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.rootURL = rootURL
        reload()
    }

    func reload() {
        do {
            classrooms = try loadClassrooms()
        } catch {
            print("[ClassroomRosterStore] Failed to load rosters: \(error)")
            classrooms = []
        }
    }

    @discardableResult
    func createClassroom(named name: String) throws -> Classroom {
        let finalName = try validatedClassName(name)
        var classroom = Classroom(name: finalName)
        classrooms.append(classroom)
        sortClassrooms()
        try save()
        classroom = try requireClassroom(id: classroom.id)
        return classroom
    }

    func renameClassroom(_ classroomID: UUID, to name: String) throws {
        let finalName = try validatedClassName(name)
        guard let index = classrooms.firstIndex(where: { $0.id == classroomID }) else {
            throw ClassroomRosterStoreError.classroomNotFound
        }
        let oldDefaultPrefix = Classroom.defaultAlternateIDPrefix(for: classrooms[index].name)
        classrooms[index].name = finalName
        if classrooms[index].alternateIDPrefix == oldDefaultPrefix {
            classrooms[index].alternateIDPrefix = Classroom.defaultAlternateIDPrefix(for: finalName)
        }
        classrooms[index].modifiedAt = Date()
        sortClassrooms()
        try save()
    }

    func deleteClassroom(_ classroomID: UUID) throws {
        classrooms.removeAll { $0.id == classroomID }
        try save()
    }

    @discardableResult
    func addStudent(to classroomID: UUID) throws -> RosterStudent {
        guard let classroomIndex = classrooms.firstIndex(where: { $0.id == classroomID }) else {
            throw ClassroomRosterStoreError.classroomNotFound
        }

        let student = RosterStudent(firstName: "", lastName: "", officialStudentID: "")
        classrooms[classroomIndex].students.insert(student, at: 0)
        classrooms[classroomIndex].modifiedAt = Date()
        try save()
        return student
    }

    func updateStudent(_ student: RosterStudent, in classroomID: UUID) throws {
        guard let classroomIndex = classrooms.firstIndex(where: { $0.id == classroomID }) else {
            throw ClassroomRosterStoreError.classroomNotFound
        }
        guard let studentIndex = classrooms[classroomIndex].students.firstIndex(where: { $0.id == student.id }) else {
            throw ClassroomRosterStoreError.studentNotFound
        }

        classrooms[classroomIndex].students[studentIndex] = student.normalized()
        classrooms[classroomIndex].modifiedAt = Date()
        try save()
    }

    func deleteStudents(_ studentIDs: Set<UUID>, from classroomID: UUID) throws {
        guard !studentIDs.isEmpty else { return }
        guard let classroomIndex = classrooms.firstIndex(where: { $0.id == classroomID }) else {
            throw ClassroomRosterStoreError.classroomNotFound
        }
        let originalCount = classrooms[classroomIndex].students.count

        classrooms[classroomIndex].students.removeAll { studentIDs.contains($0.id) }
        guard classrooms[classroomIndex].students.count != originalCount else {
            throw ClassroomRosterStoreError.studentNotFound
        }
        classrooms[classroomIndex].modifiedAt = Date()
        try save()
    }

    func moveStudents(_ studentIDs: Set<UUID>, from sourceClassroomID: UUID, to destinationClassroomID: UUID) throws {
        guard !studentIDs.isEmpty else { return }
        guard sourceClassroomID != destinationClassroomID else { return }
        guard let sourceIndex = classrooms.firstIndex(where: { $0.id == sourceClassroomID }),
              let destinationIndex = classrooms.firstIndex(where: { $0.id == destinationClassroomID }) else {
            throw ClassroomRosterStoreError.classroomNotFound
        }

        let movingStudents = classrooms[sourceIndex].students.filter { studentIDs.contains($0.id) }
        guard !movingStudents.isEmpty else {
            throw ClassroomRosterStoreError.studentNotFound
        }
        classrooms[sourceIndex].students.removeAll { studentIDs.contains($0.id) }
        classrooms[destinationIndex].students.append(contentsOf: movingStudents)
        classrooms[sourceIndex].modifiedAt = Date()
        classrooms[destinationIndex].modifiedAt = Date()
        sortStudents(in: sourceIndex)
        sortStudents(in: destinationIndex)
        try save()
    }

    func updateAlternateIDPrefix(_ prefix: String, for classroomID: UUID) throws {
        guard let classroomIndex = classrooms.firstIndex(where: { $0.id == classroomID }) else {
            throw ClassroomRosterStoreError.classroomNotFound
        }

        classrooms[classroomIndex].alternateIDPrefix = try validatedAlternateIDPrefix(prefix)
        classrooms[classroomIndex].modifiedAt = Date()
        try save()
    }

    func hasGeneratedAlternateIDs(in classroomID: UUID) -> Bool {
        guard let classroom = classrooms.first(where: { $0.id == classroomID }) else { return false }
        return classroom.students.contains {
            !$0.alternateStudentID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    func duplicateIDReport(for classroomID: UUID) throws -> DuplicateRosterIDReport {
        let classroom = try requireClassroom(id: classroomID)
        return Self.duplicateIDReport(for: classroom.students)
    }

    func duplicateIDReport(for preview: RosterCSVPreview) -> DuplicateRosterIDReport {
        guard preview.mapping.canImport,
              let firstNameIndex = preview.mapping.firstNameIndex,
              let lastNameIndex = preview.mapping.lastNameIndex,
              let officialIDIndex = preview.mapping.officialStudentIDIndex else {
            return DuplicateRosterIDReport(officialStudentIDs: [], alternateStudentIDs: [])
        }

        let alternateIDIndex = preview.mapping.alternateStudentIDIndex
        let students = preview.rows.compactMap { row -> RosterStudent? in
            let firstName = Self.value(in: row, at: firstNameIndex)
            let lastName = Self.value(in: row, at: lastNameIndex)
            let officialID = Self.value(in: row, at: officialIDIndex)
            let alternateID = alternateIDIndex.map { Self.value(in: row, at: $0) } ?? ""
            guard !firstName.isEmpty || !lastName.isEmpty || !officialID.isEmpty else { return nil }
            return RosterStudent(
                firstName: firstName,
                lastName: lastName,
                officialStudentID: officialID,
                alternateStudentID: alternateID
            )
        }

        return Self.duplicateIDReport(for: students)
    }

    func generateAlternateIDs(for classroomID: UUID, overwriteExisting: Bool = false) throws {
        guard let classroomIndex = classrooms.firstIndex(where: { $0.id == classroomID }) else {
            throw ClassroomRosterStoreError.classroomNotFound
        }

        let prefix = try validatedAlternateIDPrefix(classrooms[classroomIndex].alternateIDPrefix)
        var proposedStudents = classrooms[classroomIndex].students
        for index in proposedStudents.indices {
            if overwriteExisting || proposedStudents[index].alternateStudentID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                proposedStudents[index].alternateStudentID = "\(prefix)-\(String(format: "%03d", index + 1))"
            }
        }
        guard Self.duplicateIDReport(for: proposedStudents).alternateStudentIDs.isEmpty else {
            throw ClassroomRosterStoreError.duplicateAlternateStudentID
        }

        classrooms[classroomIndex].alternateIDPrefix = prefix
        classrooms[classroomIndex].students = proposedStudents
        classrooms[classroomIndex].modifiedAt = Date()
        try save()
    }

    func previewCSV(at sourceURL: URL) throws -> RosterCSVPreview {
        let text = try String(contentsOf: sourceURL, encoding: .utf8)
        let rows = Self.parseCSV(text)
        guard let header = rows.first, rows.count > 1 else {
            throw ClassroomRosterStoreError.emptyCSV
        }

        return RosterCSVPreview(
            headers: header,
            rows: Array(rows.dropFirst()),
            mapping: Self.inferredMapping(from: header)
        )
    }

    @discardableResult
    func importCSV(preview: RosterCSVPreview, className: String) throws -> Classroom {
        let finalName = try validatedClassName(className)
        let students = try students(from: preview)

        let classroom = Classroom(name: finalName, students: students.sortedForRoster())
        classrooms.append(classroom)
        sortClassrooms()
        try save()
        return classroom
    }

    @discardableResult
    func importCSV(preview: RosterCSVPreview, into classroomID: UUID) throws -> Classroom {
        guard let classroomIndex = classrooms.firstIndex(where: { $0.id == classroomID }) else {
            throw ClassroomRosterStoreError.classroomNotFound
        }
        let importedStudents = try students(from: preview)
        classrooms[classroomIndex].students.insert(contentsOf: importedStudents.sortedForRoster(), at: 0)
        classrooms[classroomIndex].modifiedAt = Date()
        sortStudents(in: classroomIndex)
        try save()
        return classrooms[classroomIndex]
    }

    // MARK: - Persistence

    private static func locateRootURL(using fileManager: FileManager) -> URL? {
        do {
            return try fileManager.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        } catch {
            print("[ClassroomRosterStore] Failed to locate Documents directory: \(error)")
            return nil
        }
    }

    private var storeURL: URL {
        get throws {
            guard let rootURL else { throw ClassroomRosterStoreError.noRoot }
            let directoryURL = rootURL.appendingPathComponent(Self.directoryName, isDirectory: true)
            if !fileManager.fileExists(atPath: directoryURL.path) {
                try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            }
            return directoryURL.appendingPathComponent(Self.storeFileName)
        }
    }

    private func loadClassrooms() throws -> [Classroom] {
        let url = try storeURL
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try Self.jsonDecoder.decode([Classroom].self, from: data).sortedForRoster()
    }

    private func save() throws {
        let data = try Self.jsonEncoder.encode(classrooms)
        try data.write(to: try storeURL, options: .atomic)
    }

    private func requireClassroom(id: UUID) throws -> Classroom {
        guard let classroom = classrooms.first(where: { $0.id == id }) else {
            throw ClassroomRosterStoreError.classroomNotFound
        }
        return classroom
    }

    private func validatedClassName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ClassroomRosterStoreError.emptyClassName }
        return trimmed
    }

    private func sortClassrooms() {
        classrooms = classrooms.sortedForRoster()
    }

    private func sortStudents(in classroomIndex: Int) {
        classrooms[classroomIndex].students = classrooms[classroomIndex].students.sortedForRoster()
    }

    private func validatedAlternateIDPrefix(_ prefix: String) throws -> String {
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ClassroomRosterStoreError.emptyAlternateIDPrefix }
        return trimmed.uppercased()
    }

    // MARK: - CSV

    private func students(from preview: RosterCSVPreview) throws -> [RosterStudent] {
        guard preview.mapping.canImport,
              let firstNameIndex = preview.mapping.firstNameIndex,
              let lastNameIndex = preview.mapping.lastNameIndex,
              let officialIDIndex = preview.mapping.officialStudentIDIndex else {
            throw ClassroomRosterStoreError.missingRequiredColumn
        }

        let students = preview.rows.compactMap { row -> RosterStudent? in
            let firstName = Self.value(in: row, at: firstNameIndex)
            let lastName = Self.value(in: row, at: lastNameIndex)
            let officialID = Self.value(in: row, at: officialIDIndex)
            let alternateID = preview.mapping.alternateStudentIDIndex.map { Self.value(in: row, at: $0) } ?? ""
            guard !firstName.isEmpty || !lastName.isEmpty || !officialID.isEmpty else { return nil }
            return RosterStudent(
                firstName: firstName,
                lastName: lastName,
                officialStudentID: officialID,
                alternateStudentID: alternateID
            )
        }

        guard !students.isEmpty else {
            throw ClassroomRosterStoreError.emptyCSV
        }

        return students
    }

    static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var isInsideQuotes = false
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]

            if character == "\"" {
                let nextIndex = text.index(after: index)
                if isInsideQuotes, nextIndex < text.endIndex, text[nextIndex] == "\"" {
                    field.append("\"")
                    index = nextIndex
                } else {
                    isInsideQuotes.toggle()
                }
            } else if character == "," && !isInsideQuotes {
                row.append(field.trimmingCharacters(in: .whitespacesAndNewlines))
                field = ""
            } else if character == "\n" && !isInsideQuotes {
                row.append(field.trimmingCharacters(in: .whitespacesAndNewlines))
                rows.append(row)
                row = []
                field = ""
            } else if character != "\r" {
                field.append(character)
            }

            index = text.index(after: index)
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field.trimmingCharacters(in: .whitespacesAndNewlines))
            rows.append(row)
        }

        return rows.filter { !$0.allSatisfy(\.isEmpty) }
    }

    static func inferredMapping(from headers: [String]) -> CSVColumnMapping {
        CSVColumnMapping(
            firstNameIndex: firstMatchingIndex(in: headers, candidates: ["first name", "firstname", "first"]),
            lastNameIndex: firstMatchingIndex(in: headers, candidates: ["last name", "lastname", "last", "surname"]),
            officialStudentIDIndex: firstMatchingIndex(in: headers, candidates: ["student id", "studentid", "id", "student number", "number"]),
            alternateStudentIDIndex: firstMatchingIndex(in: headers, candidates: ["alternate id", "alternateid", "alternate", "alt id", "alt", "teacher id", "teacher"])
        )
    }

    private static func firstMatchingIndex(in headers: [String], candidates: [String]) -> Int? {
        headers.firstIndex { header in
            let normalized = header
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
            return candidates.contains(normalized)
        }
    }

    private static func value(in row: [String], at index: Int) -> String {
        guard row.indices.contains(index) else { return "" }
        return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func duplicateIDReport(for students: [RosterStudent]) -> DuplicateRosterIDReport {
        DuplicateRosterIDReport(
            officialStudentIDs: duplicateValues(in: students.map(\.officialStudentID)),
            alternateStudentIDs: duplicateValues(in: students.map(\.alternateStudentID))
        )
    }

    private static func duplicateValues(in values: [String]) -> [String] {
        let normalizedValues = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty }

        let counts = Dictionary(normalizedValues.map { ($0, 1) }, uniquingKeysWith: +)
        return counts
            .filter { $0.value > 1 }
            .map(\.key)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

enum ClassroomRosterStoreError: LocalizedError {
    case noRoot
    case emptyClassName
    case classroomNotFound
    case studentNotFound
    case emptyCSV
    case missingRequiredColumn
    case emptyAlternateIDPrefix
    case duplicateAlternateStudentID

    var errorDescription: String? {
        switch self {
        case .noRoot:
            "MathBoard could not access the Documents folder."
        case .emptyClassName:
            "Class name cannot be empty."
        case .classroomNotFound:
            "MathBoard could not find that class."
        case .studentNotFound:
            "MathBoard could not find that student."
        case .emptyCSV:
            "Choose a CSV with a header row and at least one student."
        case .missingRequiredColumn:
            "Map First Name, Last Name, and Student ID before importing."
        case .emptyAlternateIDPrefix:
            "Number prefix cannot be empty."
        case .duplicateAlternateStudentID:
            "Generated alternate IDs would duplicate an existing alternate ID. Change the prefix or regenerate all IDs."
        }
    }
}

private extension RosterStudent {
    func normalized() -> RosterStudent {
        RosterStudent(
            id: id,
            firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
            officialStudentID: officialStudentID.trimmingCharacters(in: .whitespacesAndNewlines),
            alternateStudentID: alternateStudentID.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

private extension Array where Element == Classroom {
    func sortedForRoster() -> [Classroom] {
        sorted { first, second in
            first.name.localizedStandardCompare(second.name) == .orderedAscending
        }
    }
}

private extension Array where Element == RosterStudent {
    func sortedForRoster() -> [RosterStudent] {
        sorted { first, second in
            if first.lastName.localizedStandardCompare(second.lastName) == .orderedSame {
                return first.firstName.localizedStandardCompare(second.firstName) == .orderedAscending
            }
            return first.lastName.localizedStandardCompare(second.lastName) == .orderedAscending
        }
    }
}
