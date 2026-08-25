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
        "PREFIX"
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
        firstNameIndex != nil && lastNameIndex != nil
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
        var usedSuffixes = Set(
            proposedStudents.compactMap { s -> String? in
                let id = s.alternateStudentID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                guard id.hasPrefix(prefix + "-") else { return nil }
                return String(id.dropFirst(prefix.count + 1))
            }
        )
        for index in proposedStudents.indices {
            if overwriteExisting || proposedStudents[index].alternateStudentID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let suffix = Self.uniqueRandomSuffix(avoiding: usedSuffixes)
                usedSuffixes.insert(suffix)
                proposedStudents[index].alternateStudentID = "\(prefix)-\(suffix)"
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
        // Try common encodings in priority order. Many SIS exports are UTF-8;
        // Excel on Windows often produces UTF-16 or Latin-1.
        let rawText: String
        if let s = try? String(contentsOf: sourceURL, encoding: .utf8) {
            rawText = s
        } else if let s = try? String(contentsOf: sourceURL, encoding: .utf16) {
            rawText = s
        } else if let s = try? String(contentsOf: sourceURL, encoding: .isoLatin1) {
            rawText = s
        } else if let s = try? String(contentsOf: sourceURL, encoding: .windowsCP1252) {
            rawText = s
        } else {
            throw ClassroomRosterStoreError.unreadableFile
        }

        // Strip UTF-8 BOM that Excel sometimes prepends, which breaks the first header match.
        let text = rawText.hasPrefix("\u{FEFF}") ? String(rawText.dropFirst()) : rawText

        let delimiter = Self.detectDelimiter(in: text)
        let rawRows = Self.parseCSV(text, delimiter: delimiter)

        // Skip metadata preamble rows (school name, teacher info, etc.) by finding
        // the first row that contains recognizable column-header keywords.
        let headerIndex = Self.findHeaderRowIndex(in: rawRows)
        guard headerIndex < rawRows.count - 1 else {
            throw ClassroomRosterStoreError.emptyCSV
        }

        // Expand any "Last, First MI" combined-name columns into separate columns
        // so the standard mapping logic works without special cases.
        let (headers, dataRows) = Self.expandCombinedNameColumns(
            headers: rawRows[headerIndex],
            rows: Array(rawRows.dropFirst(headerIndex + 1))
        )
        guard !dataRows.isEmpty else {
            throw ClassroomRosterStoreError.emptyCSV
        }

        return RosterCSVPreview(
            headers: headers,
            rows: dataRows,
            mapping: Self.inferredMapping(from: headers)
        )
    }

    /// Routes to the correct importer based on file extension (.xlsx → XLSX reader, all
    /// others → CSV text parser). Returns the same RosterCSVPreview either way so the
    /// column-mapping UI and import flow are shared between both formats.
    func previewFile(at sourceURL: URL) throws -> RosterCSVPreview {
        if sourceURL.pathExtension.lowercased() == "xlsx" {
            return try previewXLSX(at: sourceURL)
        }
        return try previewCSV(at: sourceURL)
    }

    func previewXLSX(at sourceURL: URL) throws -> RosterCSVPreview {
        let rawRows = try XLSXRosterReader.rows(from: sourceURL)

        let headerIndex = Self.findHeaderRowIndex(in: rawRows)
        guard headerIndex < rawRows.count - 1 else {
            throw ClassroomRosterStoreError.emptyCSV
        }

        let (headers, dataRows) = Self.expandCombinedNameColumns(
            headers: rawRows[headerIndex],
            rows: Array(rawRows.dropFirst(headerIndex + 1))
        )
        guard !dataRows.isEmpty else {
            throw ClassroomRosterStoreError.emptyCSV
        }

        return RosterCSVPreview(
            headers: headers,
            rows: dataRows,
            mapping: Self.inferredMapping(from: headers)
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
              let lastNameIndex = preview.mapping.lastNameIndex else {
            throw ClassroomRosterStoreError.missingRequiredColumn
        }

        let students = preview.rows.compactMap { row -> RosterStudent? in
            let firstName = Self.value(in: row, at: firstNameIndex)
            let lastName = Self.value(in: row, at: lastNameIndex)
            let officialID = preview.mapping.officialStudentIDIndex.map { Self.value(in: row, at: $0) } ?? ""
            let alternateID = preview.mapping.alternateStudentIDIndex.map { Self.value(in: row, at: $0) } ?? ""
            guard !firstName.isEmpty || !lastName.isEmpty else { return nil }
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

    // Auto-detect whether the file uses comma, tab, or semicolon as its field separator.
    // Counts occurrences in the first non-empty line; the most frequent wins.
    static func detectDelimiter(in text: String) -> Character {
        let firstLine = text.components(separatedBy: "\n").first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
        let counts: [(Character, Int)] = [
            (",", firstLine.filter { $0 == "," }.count),
            ("\t", firstLine.filter { $0 == "\t" }.count),
            (";", firstLine.filter { $0 == ";" }.count),
        ]
        return counts.max(by: { $0.1 < $1.1 })?.0 ?? ","
    }

    static func parseCSV(_ text: String, delimiter: Character = ",") -> [[String]] {
        // Normalize all line-ending styles to \n before parsing.
        // CR-only (\r) files — common from some SIS exports — otherwise get
        // collapsed into a single row because \r is discarded and \n never fires.
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var isInsideQuotes = false
        var index = normalized.startIndex

        while index < normalized.endIndex {
            let character = normalized[index]

            if character == "\"" {
                let nextIndex = normalized.index(after: index)
                if isInsideQuotes, nextIndex < normalized.endIndex, normalized[nextIndex] == "\"" {
                    field.append("\"")
                    index = nextIndex
                } else {
                    isInsideQuotes.toggle()
                }
            } else if character == delimiter && !isInsideQuotes {
                row.append(field.trimmingCharacters(in: .whitespacesAndNewlines))
                field = ""
            } else if character == "\n" && !isInsideQuotes {
                row.append(field.trimmingCharacters(in: .whitespacesAndNewlines))
                rows.append(row)
                row = []
                field = ""
            } else {
                field.append(character)
            }

            index = normalized.index(after: index)
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field.trimmingCharacters(in: .whitespacesAndNewlines))
            rows.append(row)
        }

        return rows.filter { !$0.allSatisfy(\.isEmpty) }
    }

    // Scan up to the first 10 rows and return the index of the row that best resembles
    // a column-header row. Rows with more cells matching known header keywords score higher.
    // This skips SIS-export preambles (school name, report title, teacher info, etc.).
    static func findHeaderRowIndex(in rows: [[String]]) -> Int {
        let limit = min(10, rows.count)
        var bestIndex = 0
        var bestScore = 0
        for i in 0..<limit {
            let score = rows[i].filter { cell in
                let n = normalizeHeader(cell)
                return firstNameCandidates.contains(n)
                    || lastNameCandidates.contains(n)
                    || studentIDCandidates.contains(n)
                    || alternateIDCandidates.contains(n)
                    || combinedNameCandidates.contains(n)
                    || firstNameKeywords.contains(where: { n.contains($0) })
                    || lastNameKeywords.contains(where: { n.contains($0) })
                    || studentIDKeywords.contains(where: { n.contains($0) })
                    || (n.contains("last") && n.contains("first"))
            }.count
            if score > bestScore {
                bestScore = score
                bestIndex = i
            }
        }
        return bestIndex
    }

    // Detect columns whose header indicates a combined "Last, First [MI]" name and split
    // each such column into a "Last Name" column and a "First Name" column in place.
    // This lets the rest of the mapping/import pipeline work without special cases.
    static func expandCombinedNameColumns(headers: [String], rows: [[String]]) -> (headers: [String], rows: [[String]]) {
        var outHeaders = headers
        var outRows = rows
        var offset = 0

        for (originalIndex, header) in headers.enumerated() {
            let n = normalizeHeader(header)
            guard combinedNameCandidates.contains(n) || (n.contains("last") && n.contains("first")) else { continue }

            let i = originalIndex + offset  // adjusted index after prior expansions

            // Replace the single combined column with "Last Name" then "First Name".
            outHeaders.remove(at: i)
            outHeaders.insert("First Name", at: i)
            outHeaders.insert("Last Name", at: i)

            outRows = outRows.map { row in
                var r = row
                let combined = i < r.count ? r[i] : ""
                if i < r.count { r.remove(at: i) }

                if let commaRange = combined.range(of: ",") {
                    let last = String(combined[..<commaRange.lowerBound])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let first = String(combined[commaRange.upperBound...])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    r.insert(first, at: i)
                    r.insert(last, at: i)
                } else {
                    r.insert("", at: i)
                    r.insert(combined, at: i)
                }
                return r
            }
            offset += 1  // one column became two
        }
        return (outHeaders, outRows)
    }

    private static let combinedNameCandidates = [
        "last, first mi", "last, first", "last first mi", "last first",
        "name", "student name", "full name", "fullname",
    ]

    static func inferredMapping(from headers: [String]) -> CSVColumnMapping {
        CSVColumnMapping(
            firstNameIndex: firstMatchingIndex(
                in: headers,
                candidates: Self.firstNameCandidates,
                keywords: Self.firstNameKeywords
            ),
            lastNameIndex: firstMatchingIndex(
                in: headers,
                candidates: Self.lastNameCandidates,
                keywords: Self.lastNameKeywords
            ),
            officialStudentIDIndex: firstMatchingIndex(
                in: headers,
                candidates: Self.studentIDCandidates,
                keywords: Self.studentIDKeywords
            ),
            alternateStudentIDIndex: firstMatchingIndex(
                in: headers,
                candidates: Self.alternateIDCandidates,
                keywords: Self.alternateIDKeywords
            )
        )
    }

    // MARK: Header alias tables

    // First pass: exact normalized match. Second pass: contains-keyword match.
    // Exact match wins over keyword match to avoid false positives.
    private static let firstNameCandidates = [
        "first name", "firstname", "first", "given name", "givenname",
        "preferred name", "preferredname", "legal first name", "legal first",
        "fname", "f name", "student first name", "student first",
        "preferred first name", "student legal first name",
    ]
    private static let firstNameKeywords = ["first name", "given name"]

    private static let lastNameCandidates = [
        "last name", "lastname", "last", "surname", "family name", "familyname",
        "legal last name", "legal last", "lname", "l name",
        "student last name", "student last", "student legal last name",
    ]
    private static let lastNameKeywords = ["last name", "surname", "family name"]

    // Covers PowerSchool, Aeries, Infinite Campus, Google Classroom, Skyward, CALPADS
    private static let studentIDCandidates = [
        "student id", "studentid", "id", "student number", "number",
        "stu id", "stu no", "stu num", "stuid", "stu number",
        "student no", "student num", "student id number",
        "student identification", "student identification number",
        "pupil id", "pupil number", "pupil no",
        "local id", "local student id", "district id",
        "perm id", "permanent id", "permanent student id",
        "sis id", "state id", "ssid", "state student id",
        "id number", "id no", "id num",
        "school id", "schoolid",
    ]
    private static let studentIDKeywords = [
        "student id", "stu id", "pupil id", "student no", "student num",
        "local id", "district id", "perm id", "state id", "ssid",
    ]

    private static let alternateIDCandidates = [
        "alternate id", "alternateid", "alternate", "alt id", "alt",
        "teacher id", "teacher", "class id", "classid",
        "login", "login id", "loginid", "username", "user name",
        "display id", "display name id",
    ]
    private static let alternateIDKeywords: [String] = []

    // MARK: - Alternate ID generation

    // 5-character random suffix from a 32-char alphabet.
    // Excludes visually ambiguous characters (0/O, 1/I/L) so IDs are easy to
    // read and type on a screen. 32^5 = ~33M combinations per prefix — not
    // enumerable in a classroom setting even if a student knows the prefix.
    private static let suffixAlphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")

    private static func uniqueRandomSuffix(avoiding used: Set<String>) -> String {
        var suffix: String
        repeat {
            suffix = String((0..<5).map { _ in suffixAlphabet.randomElement()! })
        } while used.contains(suffix)
        return suffix
    }

    // Normalize a header for matching: lowercase, collapse separators, strip punctuation.
    private static func normalizeHeader(_ header: String) -> String {
        var s = header
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        s = s.replacingOccurrences(of: "_", with: " ")
        s = s.replacingOccurrences(of: "-", with: " ")
        s = s.replacingOccurrences(of: "#", with: "")
        s = s.replacingOccurrences(of: ".", with: "")
        // Collapse runs of whitespace to a single space and trim.
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        return s.trimmingCharacters(in: .whitespaces)
    }

    private static func firstMatchingIndex(in headers: [String], candidates: [String], keywords: [String]) -> Int? {
        // 1. Exact normalized match (highest confidence).
        if let index = headers.firstIndex(where: { candidates.contains(normalizeHeader($0)) }) {
            return index
        }
        // 2. Substring-keyword match (lower confidence, catches variants like "Student ID Number").
        guard !keywords.isEmpty else { return nil }
        return headers.firstIndex { header in
            let normalized = normalizeHeader(header)
            return keywords.contains(where: { normalized.contains($0) })
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
    case unreadableFile
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
            "Choose a CSV or Excel (.xlsx) file with a header row and at least one student."
        case .unreadableFile:
            "MathBoard could not read this file. Try saving it as a CSV (UTF-8) from Excel or your student information system."
        case .missingRequiredColumn:
            "Map First Name and Last Name before importing. Student ID is optional — use Generate IDs in the roster view after import."
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
