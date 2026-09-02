import Foundation
import Observation
import Slides
import WidgetEngine

public struct AssignedWidgetSummary: Identifiable, Codable, Hashable {
    public var id: UUID
    public var widgetID: UUID
    public var title: String
    public var maxScore: Double
    public var scoreMode: WidgetScoreMode
    public var builtInKind: BuiltInInteractiveKind?

    public init(
        id: UUID = UUID(),
        widgetID: UUID,
        title: String,
        maxScore: Double,
        scoreMode: WidgetScoreMode = .percentAverage,
        builtInKind: BuiltInInteractiveKind? = nil
    ) {
        self.id = id
        self.widgetID = widgetID
        self.title = title
        self.maxScore = max(0, maxScore)
        self.scoreMode = scoreMode
        self.builtInKind = builtInKind
    }
}

public enum WidgetScoreMode: String, Codable, Hashable {
    case percentAverage
}

public struct ClassroomAssignment: Identifiable, Codable, Hashable {
    public var id: UUID
    public var classroomID: UUID
    public var lessonID: UUID
    public var lessonTitle: String
    public var lessonVersionID: UUID?
    public var lessonVersionNumber: Int?
    public var lessonVersionPublishedAt: Date?
    public var lessonPackageFileName: String?
    public var lessonPackageStoragePath: String?
    public var lessonPackageChecksum: String?
    public var assignedAt: Date
    public var classLessonCode: String
    public var shareURL: URL?
    public var widgetSummaries: [AssignedWidgetSummary]

    public init(
        id: UUID = UUID(),
        classroomID: UUID,
        lessonID: UUID,
        lessonTitle: String,
        lessonVersionID: UUID? = nil,
        lessonVersionNumber: Int? = nil,
        lessonVersionPublishedAt: Date? = nil,
        lessonPackageFileName: String? = nil,
        lessonPackageStoragePath: String? = nil,
        lessonPackageChecksum: String? = nil,
        assignedAt: Date = Date(),
        classLessonCode: String,
        shareURL: URL? = nil,
        widgetSummaries: [AssignedWidgetSummary]
    ) {
        self.id = id
        self.classroomID = classroomID
        self.lessonID = lessonID
        self.lessonTitle = lessonTitle
        self.lessonVersionID = lessonVersionID
        self.lessonVersionNumber = lessonVersionNumber
        self.lessonVersionPublishedAt = lessonVersionPublishedAt
        self.lessonPackageFileName = lessonPackageFileName
        self.lessonPackageStoragePath = lessonPackageStoragePath
        self.lessonPackageChecksum = lessonPackageChecksum
        self.assignedAt = assignedAt
        self.classLessonCode = classLessonCode
        self.shareURL = shareURL
        self.widgetSummaries = widgetSummaries
    }

    public var versionDisplayName: String {
        guard let lessonVersionNumber else { return "Unversioned" }
        return "v\(lessonVersionNumber)"
    }

    var lessonPackageManifest: LessonPackageManifest {
        LessonPackageManifest(
            id: lessonID,
            title: lessonTitle,
            versionID: lessonVersionID,
            versionNumber: lessonVersionNumber,
            packageFileName: lessonPackageFileName,
            packageStoragePath: lessonPackageStoragePath,
            packageChecksum: lessonPackageChecksum,
            publishedAt: lessonVersionPublishedAt
        )
    }
}

public struct StudentWidgetResult: Identifiable, Codable, Hashable {
    public var id: UUID
    public var assignmentID: UUID
    public var classroomID: UUID
    public var studentID: UUID
    public var widgetID: UUID
    public var numberCorrectFirstTry: Int
    public var numberCorrectAfterRetry: Int
    public var longestStreak: Int
    public var finalPercentScore: Double
    public var submittedAt: Date

    public init(
        id: UUID = UUID(),
        assignmentID: UUID,
        classroomID: UUID,
        studentID: UUID,
        widgetID: UUID,
        numberCorrectFirstTry: Int,
        numberCorrectAfterRetry: Int,
        longestStreak: Int,
        finalPercentScore: Double,
        submittedAt: Date = Date()
    ) {
        self.id = id
        self.assignmentID = assignmentID
        self.classroomID = classroomID
        self.studentID = studentID
        self.widgetID = widgetID
        self.numberCorrectFirstTry = max(0, numberCorrectFirstTry)
        self.numberCorrectAfterRetry = max(0, numberCorrectAfterRetry)
        self.longestStreak = max(0, longestStreak)
        self.finalPercentScore = Self.clampedPercent(finalPercentScore)
        self.submittedAt = submittedAt
    }

    fileprivate func replacingID(_ id: UUID) -> StudentWidgetResult {
        StudentWidgetResult(
            id: id,
            assignmentID: assignmentID,
            classroomID: classroomID,
            studentID: studentID,
            widgetID: widgetID,
            numberCorrectFirstTry: numberCorrectFirstTry,
            numberCorrectAfterRetry: numberCorrectAfterRetry,
            longestStreak: longestStreak,
            finalPercentScore: finalPercentScore,
            submittedAt: submittedAt
        )
    }

    private static func clampedPercent(_ score: Double) -> Double {
        min(100, max(0, score))
    }
}

public struct TeacherLocalWidgetScore: Identifiable, Codable, Hashable {
    public var id: UUID
    public var assignmentID: UUID
    public var classroomID: UUID
    public var studentID: UUID
    public var widgetID: UUID
    public var points: Int
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        assignmentID: UUID,
        classroomID: UUID,
        studentID: UUID,
        widgetID: UUID,
        points: Int,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.assignmentID = assignmentID
        self.classroomID = classroomID
        self.studentID = studentID
        self.widgetID = widgetID
        self.points = max(0, points)
        self.updatedAt = updatedAt
    }

    fileprivate func replacing(id: UUID, points: Int, updatedAt: Date = Date()) -> TeacherLocalWidgetScore {
        TeacherLocalWidgetScore(
            id: id,
            assignmentID: assignmentID,
            classroomID: classroomID,
            studentID: studentID,
            widgetID: widgetID,
            points: points,
            updatedAt: updatedAt
        )
    }
}

public struct StudentLessonReport: Identifiable, Hashable {
    public var id: UUID { studentID }
    public var studentID: UUID
    public var firstName: String
    public var lastName: String
    public var officialStudentID: String
    public var alternateStudentID: String
    public var widgetResults: [StudentWidgetResult]

    public var studentName: String {
        [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    public var averagePercentScore: Double? {
        guard !widgetResults.isEmpty else { return nil }
        let total = widgetResults.reduce(0) { $0 + $1.finalPercentScore }
        return total / Double(widgetResults.count)
    }
}

public struct ClassroomAssignmentReport: Identifiable, Hashable {
    public var id: UUID { assignment.id }
    public var assignment: ClassroomAssignment
    public var studentReports: [StudentLessonReport]

    public var classAveragePercentScore: Double? {
        let completedScores = studentReports.compactMap(\.averagePercentScore)
        guard !completedScores.isEmpty else { return nil }
        return completedScores.reduce(0, +) / Double(completedScores.count)
    }
}

public enum ClassroomAssignmentStoreError: LocalizedError, Equatable {
    case noWritableDocumentDirectory
    case emptyClassroomSelection
    case assignmentNotFound
    case classroomMismatch
    case widgetNotAssigned
    case classLessonCodeNotFound
    case studentNotFound
    case ambiguousStudentIdentifier
    case invalidWidgetScoreRecord
    case incompleteWidgetScore
    case couldNotGenerateUniqueCode

    public var errorDescription: String? {
        switch self {
        case .noWritableDocumentDirectory:
            "MathBoard could not find a writable Documents folder."
        case .emptyClassroomSelection:
            "Choose at least one class before assigning a lesson."
        case .assignmentNotFound:
            "MathBoard could not find that assignment."
        case .classroomMismatch:
            "That result does not belong to the assignment's class."
        case .widgetNotAssigned:
            "That widget is not part of the assigned lesson."
        case .classLessonCodeNotFound:
            "MathBoard could not find an assignment for that lesson code."
        case .studentNotFound:
            "MathBoard could not match that student ID to the assigned class roster."
        case .ambiguousStudentIdentifier:
            "That student ID matches more than one student in this class roster."
        case .invalidWidgetScoreRecord:
            "That widget score record does not identify a MathBoard widget."
        case .incompleteWidgetScore:
            "Only completed widget scores can be submitted to reports."
        case .couldNotGenerateUniqueCode:
            "MathBoard could not create a unique class lesson code."
        }
    }
}

@MainActor
@Observable
public final class ClassroomAssignmentStore {
    public private(set) var assignments: [ClassroomAssignment] = []
    public private(set) var widgetResults: [StudentWidgetResult] = []
    public private(set) var localWidgetScores: [TeacherLocalWidgetScore] = []

    private let rootURL: URL?
    private let fileManager: FileManager
    private let codeGenerator: () -> String

    private var storeDirectoryURL: URL? {
        rootURL?.appendingPathComponent("Class Rosters", isDirectory: true)
    }

    private var storeURL: URL? {
        storeDirectoryURL?.appendingPathComponent("assignments.json")
    }

    public convenience init() {
        let documentsURL = try? FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        self.init(rootURL: documentsURL)
    }

    init(
        rootURL: URL?,
        fileManager: FileManager = .default,
        codeGenerator: @escaping () -> String = { ClassroomAssignmentStore.randomAssignmentCode() }
    ) {
        self.rootURL = rootURL
        self.fileManager = fileManager
        self.codeGenerator = codeGenerator
        reload()
    }

    @discardableResult
    func createAssignments(
        for lesson: Lesson,
        classroomIDs: [UUID],
        widgetSummaries: [AssignedWidgetSummary],
        lessonManifest: LessonPackageManifest? = nil,
        shareURL: URL? = nil
    ) throws -> [ClassroomAssignment] {
        var seenClassroomIDs = Set<UUID>()
        let uniqueClassroomIDs = classroomIDs.filter { seenClassroomIDs.insert($0).inserted }
        guard !uniqueClassroomIDs.isEmpty else { throw ClassroomAssignmentStoreError.emptyClassroomSelection }

        var usedCodes = Set(assignments.map(\.classLessonCode))
        let newAssignments = try uniqueClassroomIDs.map { classroomID in
            let code = try nextUniqueAssignmentCode(usedCodes: usedCodes)
            usedCodes.insert(code)
            return ClassroomAssignment(
                classroomID: classroomID,
                lessonID: lesson.id,
                lessonTitle: lesson.name,
                lessonVersionID: lessonManifest?.versionID,
                lessonVersionNumber: lessonManifest?.versionNumber,
                lessonVersionPublishedAt: lessonManifest?.publishedAt,
                lessonPackageFileName: lessonManifest?.packageFileName,
                lessonPackageStoragePath: lessonManifest?.packageStoragePath,
                lessonPackageChecksum: lessonManifest?.packageChecksum,
                classLessonCode: code,
                shareURL: shareURL,
                widgetSummaries: widgetSummaries
            )
        }

        assignments.append(contentsOf: newAssignments)
        save()
        return newAssignments
    }

    @discardableResult
    func createAssignments(
        for lesson: Lesson,
        classroomIDs: [UUID],
        shareURL: URL? = nil
    ) throws -> [ClassroomAssignment] {
        try createAssignments(
            for: lesson,
            classroomIDs: classroomIDs,
            widgetSummaries: widgetSummaries(for: lesson),
            lessonManifest: nil,
            shareURL: shareURL
        )
    }

    func assignments(for lessonID: UUID) -> [ClassroomAssignment] {
        assignments
            .filter { $0.lessonID == lessonID }
            .sorted { $0.assignedAt > $1.assignedAt }
    }

    func assignments(forClassroomID classroomID: UUID) -> [ClassroomAssignment] {
        assignments
            .filter { $0.classroomID == classroomID }
            .sorted { first, second in
                if first.assignedAt == second.assignedAt {
                    return first.lessonTitle.localizedStandardCompare(second.lessonTitle) == .orderedAscending
                }
                return first.assignedAt > second.assignedAt
            }
    }

    func assignment(matchingClassLessonCode classLessonCode: String) -> ClassroomAssignment? {
        let normalizedCode = Self.normalizedClassLessonCode(classLessonCode)
        guard !normalizedCode.isEmpty else { return nil }
        return assignments.first { $0.classLessonCode == normalizedCode }
    }

    func assignment(for lessonID: UUID, classroomID: UUID) -> ClassroomAssignment? {
        assignments.first {
            $0.lessonID == lessonID && $0.classroomID == classroomID
        }
    }

    func assignmentHasLocalActivity(_ assignment: ClassroomAssignment) -> Bool {
        widgetResults.contains { $0.assignmentID == assignment.id }
            || localWidgetScores.contains { $0.assignmentID == assignment.id }
    }

    @discardableResult
    func updateAssignment(
        _ assignment: ClassroomAssignment,
        lesson: Lesson,
        widgetSummaries: [AssignedWidgetSummary],
        lessonManifest: LessonPackageManifest,
        assignedAt: Date = Date()
    ) throws -> ClassroomAssignment {
        guard let index = assignments.firstIndex(where: { $0.id == assignment.id }) else {
            throw ClassroomAssignmentStoreError.assignmentNotFound
        }
        var updated = assignment
        updated.lessonTitle = lesson.name
        updated.lessonVersionID = lessonManifest.versionID
        updated.lessonVersionNumber = lessonManifest.versionNumber
        updated.lessonVersionPublishedAt = lessonManifest.publishedAt
        updated.lessonPackageFileName = lessonManifest.packageFileName
        updated.lessonPackageStoragePath = lessonManifest.packageStoragePath
        updated.lessonPackageChecksum = lessonManifest.packageChecksum
        updated.assignedAt = assignedAt
        updated.widgetSummaries = widgetSummaries
        assignments[index] = updated
        save()
        return updated
    }

    func widgetSummaries(for lesson: Lesson) -> [AssignedWidgetSummary] {
        let slideStore = SlideStore(lessonURL: lesson.url)
        return slideStore.slides.flatMap { slide in
            let drawingURL = slideStore.drawingURL(for: slide)
            return WidgetObject.load(from: WidgetObject.sidecarURL(forDrawingURL: drawingURL))
                .map { widget in
                    let scoreRecord = widget.activityScoreRecord
                    return AssignedWidgetSummary(
                        widgetID: widget.id,
                        title: scoreRecord?.title ?? widget.displayTitle,
                        maxScore: Double(scoreRecord?.pointsPossible ?? 0),
                        builtInKind: widget.builtInInteractiveKind
                    )
                }
        }
    }

    public func recordWidgetResult(_ result: StudentWidgetResult) throws {
        guard let assignment = assignments.first(where: { $0.id == result.assignmentID }) else {
            throw ClassroomAssignmentStoreError.assignmentNotFound
        }
        try recordWidgetResult(result, for: assignment)
    }

    func localWidgetScore(
        assignmentID: UUID,
        widgetID: UUID,
        studentID: UUID
    ) -> TeacherLocalWidgetScore? {
        localWidgetScores.first {
            $0.assignmentID == assignmentID &&
            $0.widgetID == widgetID &&
            $0.studentID == studentID
        }
    }

    func localWidgetScores(
        assignmentID: UUID,
        widgetID: UUID
    ) -> [TeacherLocalWidgetScore] {
        localWidgetScores.filter {
            $0.assignmentID == assignmentID &&
            $0.widgetID == widgetID
        }
    }

    func updateLocalWidgetScore(
        assignment: ClassroomAssignment,
        classroom: Classroom,
        widgetID: UUID,
        studentID: UUID,
        delta: Int
    ) throws {
        guard assignment.classroomID == classroom.id else {
            throw ClassroomAssignmentStoreError.classroomMismatch
        }
        guard classroom.students.contains(where: { $0.id == studentID }) else {
            throw ClassroomAssignmentStoreError.studentNotFound
        }
        guard assignment.widgetSummaries.contains(where: { $0.widgetID == widgetID }) else {
            throw ClassroomAssignmentStoreError.widgetNotAssigned
        }

        if let existingIndex = localWidgetScores.firstIndex(where: {
            $0.assignmentID == assignment.id &&
            $0.widgetID == widgetID &&
            $0.studentID == studentID
        }) {
            let existing = localWidgetScores[existingIndex]
            localWidgetScores[existingIndex] = existing.replacing(
                id: existing.id,
                points: max(0, existing.points + delta)
            )
        } else {
            localWidgetScores.append(
                TeacherLocalWidgetScore(
                    assignmentID: assignment.id,
                    classroomID: classroom.id,
                    studentID: studentID,
                    widgetID: widgetID,
                    points: max(0, delta)
                )
            )
        }
        save()
    }

    @discardableResult
    func recordWidgetScore(
        _ scoreRecord: WidgetActivityScoreRecord,
        classLessonCode: String,
        studentIdentifier: String,
        classroom: Classroom,
        submittedAt: Date = Date()
    ) throws -> StudentWidgetResult {
        let normalizedCode = Self.normalizedClassLessonCode(classLessonCode)
        guard let assignment = assignments.first(where: { $0.classLessonCode == normalizedCode }) else {
            throw ClassroomAssignmentStoreError.classLessonCodeNotFound
        }
        guard assignment.classroomID == classroom.id else {
            throw ClassroomAssignmentStoreError.classroomMismatch
        }
        guard scoreRecord.status == .complete, scoreRecord.attempts > 0, let percent = scoreRecord.percent else {
            throw ClassroomAssignmentStoreError.incompleteWidgetScore
        }
        guard let widgetID = UUID(uuidString: scoreRecord.id) else {
            throw ClassroomAssignmentStoreError.invalidWidgetScoreRecord
        }
        guard assignment.widgetSummaries.contains(where: { $0.widgetID == widgetID }) else {
            throw ClassroomAssignmentStoreError.widgetNotAssigned
        }

        let student = try student(matching: studentIdentifier, in: classroom)
        let result = StudentWidgetResult(
            assignmentID: assignment.id,
            classroomID: classroom.id,
            studentID: student.id,
            widgetID: widgetID,
            numberCorrectFirstTry: scoreRecord.numberCorrectFirstTry,
            numberCorrectAfterRetry: scoreRecord.numberCorrectAfterRetry,
            longestStreak: scoreRecord.longestStreak,
            finalPercentScore: Double(percent),
            submittedAt: submittedAt
        )
        try recordWidgetResult(result, for: assignment)
        return result
    }

    func report(
        for assignmentID: UUID,
        classroom: Classroom,
        selectedStudentIDs: Set<UUID>? = nil
    ) throws -> ClassroomAssignmentReport {
        guard let assignment = assignments.first(where: { $0.id == assignmentID }) else {
            throw ClassroomAssignmentStoreError.assignmentNotFound
        }
        guard assignment.classroomID == classroom.id else {
            throw ClassroomAssignmentStoreError.classroomMismatch
        }

        let selectedStudents = classroom.students.filter { student in
            guard let selectedStudentIDs, !selectedStudentIDs.isEmpty else { return true }
            return selectedStudentIDs.contains(student.id)
        }

        let reports = selectedStudents.map { student in
            StudentLessonReport(
                studentID: student.id,
                firstName: student.firstName,
                lastName: student.lastName,
                officialStudentID: student.officialStudentID,
                alternateStudentID: student.alternateStudentID,
                widgetResults: widgetResults
                    .filter { result in
                        result.assignmentID == assignmentID && result.studentID == student.id
                    }
                    .sorted { $0.submittedAt < $1.submittedAt }
            )
        }

        return ClassroomAssignmentReport(assignment: assignment, studentReports: reports)
    }

    public func averagePercentScore(for assignmentID: UUID, studentID: UUID) -> Double? {
        let matchingResults = widgetResults.filter {
            $0.assignmentID == assignmentID && $0.studentID == studentID
        }
        guard !matchingResults.isEmpty else { return nil }
        return matchingResults.reduce(0) { $0 + $1.finalPercentScore } / Double(matchingResults.count)
    }

    public func reload() {
        guard let storeURL, fileManager.fileExists(atPath: storeURL.path) else {
            assignments = []
            widgetResults = []
            localWidgetScores = []
            return
        }

        do {
            let data = try Data(contentsOf: storeURL)
            let snapshot = try Self.jsonDecoder.decode(ClassroomAssignmentStoreSnapshot.self, from: data)
            assignments = snapshot.assignments
            widgetResults = snapshot.widgetResults
            localWidgetScores = snapshot.localWidgetScores
        } catch {
            assignments = []
            widgetResults = []
            localWidgetScores = []
        }
    }

    private func recordWidgetResult(_ result: StudentWidgetResult, for assignment: ClassroomAssignment) throws {
        guard assignment.classroomID == result.classroomID else {
            throw ClassroomAssignmentStoreError.classroomMismatch
        }
        guard assignment.widgetSummaries.contains(where: { $0.widgetID == result.widgetID }) else {
            throw ClassroomAssignmentStoreError.widgetNotAssigned
        }

        if let existingIndex = widgetResults.firstIndex(where: {
            $0.assignmentID == result.assignmentID &&
            $0.studentID == result.studentID &&
            $0.widgetID == result.widgetID
        }) {
            widgetResults[existingIndex] = result.replacingID(widgetResults[existingIndex].id)
        } else {
            widgetResults.append(result)
        }
        save()
    }

    private func student(matching identifier: String, in classroom: Classroom) throws -> RosterStudent {
        let normalizedIdentifier = Self.normalizedStudentIdentifier(identifier)
        guard !normalizedIdentifier.isEmpty else {
            throw ClassroomAssignmentStoreError.studentNotFound
        }

        let matches = classroom.students.filter { student in
            Self.normalizedStudentIdentifier(student.officialStudentID) == normalizedIdentifier ||
            Self.normalizedStudentIdentifier(student.alternateStudentID) == normalizedIdentifier
        }
        guard !matches.isEmpty else {
            throw ClassroomAssignmentStoreError.studentNotFound
        }
        guard matches.count == 1, let student = matches.first else {
            throw ClassroomAssignmentStoreError.ambiguousStudentIdentifier
        }
        return student
    }

    private func save() {
        guard let storeDirectoryURL, let storeURL else { return }

        do {
            try fileManager.createDirectory(at: storeDirectoryURL, withIntermediateDirectories: true)
            let snapshot = ClassroomAssignmentStoreSnapshot(
                assignments: assignments,
                widgetResults: widgetResults,
                localWidgetScores: localWidgetScores
            )
            let data = try Self.jsonEncoder.encode(snapshot)
            try data.write(to: storeURL, options: [.atomic])
        } catch {
            assertionFailure("Unable to save classroom assignments: \(error)")
        }
    }

    private func nextUniqueAssignmentCode(usedCodes: Set<String>) throws -> String {
        for _ in 0..<50 {
            let code = Self.normalizedAssignmentCode(codeGenerator())
            if !code.isEmpty && !usedCodes.contains(code) {
                return code
            }
        }
        throw ClassroomAssignmentStoreError.couldNotGenerateUniqueCode
    }

    private static func normalizedAssignmentCode(_ rawCode: String) -> String {
        String(rawCode.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(8))
    }

    static func normalizedClassLessonCode(_ rawCode: String) -> String {
        normalizedAssignmentCode(rawCode)
    }

    private static func normalizedStudentIdentifier(_ rawIdentifier: String) -> String {
        rawIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static func randomAssignmentCode() -> String {
        String(normalizedAssignmentCode(UUID().uuidString).prefix(generatedAssignmentCodeLength))
    }

    private static let generatedAssignmentCodeLength = 6

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

private struct ClassroomAssignmentStoreSnapshot: Codable {
    var assignments: [ClassroomAssignment]
    var widgetResults: [StudentWidgetResult]
    var localWidgetScores: [TeacherLocalWidgetScore]

    init(
        assignments: [ClassroomAssignment],
        widgetResults: [StudentWidgetResult],
        localWidgetScores: [TeacherLocalWidgetScore] = []
    ) {
        self.assignments = assignments
        self.widgetResults = widgetResults
        self.localWidgetScores = localWidgetScores
    }

    private enum CodingKeys: String, CodingKey {
        case assignments
        case widgetResults
        case localWidgetScores
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        assignments = try container.decode([ClassroomAssignment].self, forKey: .assignments)
        widgetResults = try container.decode([StudentWidgetResult].self, forKey: .widgetResults)
        localWidgetScores = try container.decodeIfPresent(
            [TeacherLocalWidgetScore].self,
            forKey: .localWidgetScores
        ) ?? []
    }
}

private extension WidgetObject {
    var displayTitle: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            return trimmedName
        }
        return builtInInteractiveKind?.displayName ?? activityKind.displayName
    }
}
