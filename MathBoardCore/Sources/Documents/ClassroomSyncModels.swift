import Foundation
import LiveClassroom
import WidgetEngine

public struct TeacherSyncIdentity: Codable, Hashable, Identifiable {
    public var id: UUID
    public var displayName: String

    public init(id: UUID = UUID(), displayName: String = "Local Teacher") {
        self.id = id
        self.displayName = displayName
    }
}

public struct ClassroomSyncPacket: Codable, Hashable, Identifiable {
    public var id: UUID
    public var teacherID: UUID
    public var name: String
    public var studentCount: Int

    public init(id: UUID, teacherID: UUID, name: String, studentCount: Int) {
        self.id = id
        self.teacherID = teacherID
        self.name = name
        self.studentCount = studentCount
    }
}

public struct LessonPackageManifest: Codable, Hashable, Identifiable {
    public var id: UUID
    public var title: String
    public var versionID: UUID?
    public var versionNumber: Int?
    public var packageFileName: String?
    public var packageStoragePath: String?
    public var packageChecksum: String?
    public var publishedAt: Date?

    public init(
        id: UUID,
        title: String,
        versionID: UUID? = nil,
        versionNumber: Int? = nil,
        packageFileName: String? = nil,
        packageStoragePath: String? = nil,
        packageChecksum: String? = nil,
        publishedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.versionID = versionID
        self.versionNumber = versionNumber
        self.packageFileName = packageFileName
        self.packageStoragePath = packageStoragePath
        self.packageChecksum = packageChecksum
        self.publishedAt = publishedAt
    }
}

public struct AssignmentSyncPacket: Codable, Hashable, Identifiable {
    public var id: UUID
    public var teacherID: UUID
    public var classroomID: UUID
    public var classroomName: String
    public var lesson: LessonPackageManifest
    public var classLessonCode: String
    public var shareURL: URL?
    public var widgetSummaries: [AssignedWidgetSummary]
    public var assignedAt: Date
    public var allowedStudentIdentifierHashes: [String]

    private enum CodingKeys: String, CodingKey {
        case id
        case teacherID
        case classroomID
        case classroomName
        case lesson
        case classLessonCode
        case shareURL
        case widgetSummaries
        case assignedAt
        case allowedStudentIdentifierHashes
    }

    public init(
        id: UUID,
        teacherID: UUID,
        classroomID: UUID,
        classroomName: String,
        lesson: LessonPackageManifest,
        classLessonCode: String,
        shareURL: URL? = nil,
        widgetSummaries: [AssignedWidgetSummary],
        assignedAt: Date,
        allowedStudentIdentifierHashes: [String] = []
    ) {
        self.id = id
        self.teacherID = teacherID
        self.classroomID = classroomID
        self.classroomName = classroomName
        self.lesson = lesson
        self.classLessonCode = classLessonCode
        self.shareURL = shareURL
        self.widgetSummaries = widgetSummaries
        self.assignedAt = assignedAt
        self.allowedStudentIdentifierHashes = allowedStudentIdentifierHashes
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        teacherID = try container.decode(UUID.self, forKey: .teacherID)
        classroomID = try container.decode(UUID.self, forKey: .classroomID)
        classroomName = try container.decode(String.self, forKey: .classroomName)
        lesson = try container.decode(LessonPackageManifest.self, forKey: .lesson)
        classLessonCode = try container.decode(String.self, forKey: .classLessonCode)
        shareURL = try container.decodeIfPresent(URL.self, forKey: .shareURL)
        widgetSummaries = try container.decode([AssignedWidgetSummary].self, forKey: .widgetSummaries)
        assignedAt = try container.decode(Date.self, forKey: .assignedAt)
        allowedStudentIdentifierHashes = try container.decodeIfPresent([String].self, forKey: .allowedStudentIdentifierHashes) ?? []
    }
}

public struct StudentSubmissionPacket: Codable, Identifiable {
    public var id: UUID
    public var teacherID: UUID
    public var classroomID: UUID
    public var assignmentID: UUID
    public var classLessonCode: String
    public var studentIdentifier: String
    public var studentPreferredFirstName: String?
    public var widgetScoreRecord: WidgetActivityScoreRecord
    public var submittedAt: Date

    public init(
        id: UUID = UUID(),
        teacherID: UUID,
        classroomID: UUID,
        assignmentID: UUID,
        classLessonCode: String,
        studentIdentifier: String,
        studentPreferredFirstName: String? = nil,
        widgetScoreRecord: WidgetActivityScoreRecord,
        submittedAt: Date = Date()
    ) {
        self.id = id
        self.teacherID = teacherID
        self.classroomID = classroomID
        self.assignmentID = assignmentID
        self.classLessonCode = classLessonCode
        self.studentIdentifier = studentIdentifier
        self.studentPreferredFirstName = studentPreferredFirstName
        self.widgetScoreRecord = widgetScoreRecord
        self.submittedAt = submittedAt
    }
}

public struct StudentWidgetLiveProgress: Codable, Hashable, Identifiable {
    static let defaultActiveStaleInterval: TimeInterval = 10
    static let lessonPresenceWidgetID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    public var id: String { "\(studentID.uuidString)_\(widgetID.uuidString)" }
    public var assignmentID: UUID
    public var classroomID: UUID
    public var studentID: UUID
    public var studentIdentifier: String
    public var studentName: String
    public var studentPreferredFirstName: String?
    public var widgetID: UUID
    public var correctCount: Int
    public var attemptedCount: Int
    public var status: WidgetActivityScoreStatus
    public var isActiveOnStudentScreen: Bool
    /// Persists across Reset so the teacher always sees green "Submitted" text after a student has submitted at least once.
    public var hasEverBeenSubmitted: Bool
    public var updatedAt: Date

    public init(
        assignmentID: UUID,
        classroomID: UUID,
        studentID: UUID,
        studentIdentifier: String = "",
        studentName: String,
        studentPreferredFirstName: String? = nil,
        widgetID: UUID,
        correctCount: Int,
        attemptedCount: Int,
        status: WidgetActivityScoreStatus,
        isActiveOnStudentScreen: Bool = false,
        hasEverBeenSubmitted: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.assignmentID = assignmentID
        self.classroomID = classroomID
        self.studentID = studentID
        self.studentIdentifier = studentIdentifier
        self.studentName = studentName
        self.studentPreferredFirstName = studentPreferredFirstName
        self.widgetID = widgetID
        self.correctCount = max(0, correctCount)
        self.attemptedCount = max(0, attemptedCount)
        self.status = status
        self.isActiveOnStudentScreen = isActiveOnStudentScreen
        self.hasEverBeenSubmitted = hasEverBeenSubmitted
        self.updatedAt = updatedAt
    }

    public var percentScore: Double? {
        guard attemptedCount > 0 else { return nil }
        return Double(correctCount) / Double(attemptedCount) * 100
    }

    func indicatorState(
        now: Date = Date(),
        staleInterval: TimeInterval = Self.defaultActiveStaleInterval,
        lessonPresence: StudentWidgetLiveProgress? = nil
    ) -> LiveProgressIndicatorState {
        let presenceIsFresh = lessonPresence.map {
            now.timeIntervalSince($0.updatedAt) <= staleInterval
        } ?? false

        if status == .complete {
            // Green only while the student has a fresh presence (currently in the lesson).
            // When they exit, the presence doc is deleted and the dot turns gray.
            return presenceIsFresh ? .submitted : .submittedOffline
        }

        if now.timeIntervalSince(updatedAt) > staleInterval {
            // Widget doc is stale. If the student has a fresh presence they re-entered the
            // lesson and the loop hasn't refreshed this widget doc yet — show blue instead
            // of red so the dot doesn't stay red while the student is actively in the lesson.
            return presenceIsFresh ? .inactive : .offline
        }

        return isActiveOnStudentScreen ? .active : .inactive
    }
}

enum LiveProgressIndicatorState: Equatable {
    case notStarted
    case inactive
    case active
    case submitted
    case submittedOffline
    case offline

    var displayName: String {
        switch self {
        case .notStarted:
            "Not logged in"
        case .inactive:
            "Logged in"
        case .active:
            "On widget"
        case .submitted, .submittedOffline:
            "Submitted"
        case .offline:
            "Offline"
        }
    }
}

extension Optional where Wrapped == StudentWidgetLiveProgress {
    func indicatorState(
        now: Date = Date(),
        staleInterval: TimeInterval = StudentWidgetLiveProgress.defaultActiveStaleInterval,
        lessonPresence: StudentWidgetLiveProgress? = nil
    ) -> LiveProgressIndicatorState {
        guard let progress = self else { return .notStarted }
        return progress.indicatorState(now: now, staleInterval: staleInterval, lessonPresence: lessonPresence)
    }

    func liveProgressIndicatorState(
        now: Date = Date(),
        staleInterval: TimeInterval = StudentWidgetLiveProgress.defaultActiveStaleInterval
    ) -> LiveProgressIndicatorState {
        indicatorState(now: now, staleInterval: staleInterval)
    }
}

@MainActor
protocol ClassroomSyncService {
    func classroomPacket(for classroom: Classroom) -> ClassroomSyncPacket
    func publishAssignment(_ assignment: ClassroomAssignment, classroom: Classroom) throws -> AssignmentSyncPacket
    func resolveAssignment(classLessonCode: String) throws -> AssignmentSyncPacket

    @discardableResult
    func submitWidgetScore(_ submission: StudentSubmissionPacket) throws -> StudentWidgetResult

    func fetchSubmissions(assignmentID: UUID) throws -> [StudentWidgetResult]
    func publishTeacherInkChunk(_ chunk: TeacherInkStrokeChunk) throws
    func fetchTeacherInkChunks(classLessonCode: String) throws -> [TeacherInkStrokeChunk]
    func publishTeacherInkDrawingSnapshot(_ snapshot: TeacherInkDrawingSnapshot) throws
    func fetchTeacherInkDrawingSnapshots(classLessonCode: String) throws -> [TeacherInkDrawingSnapshot]
}

@MainActor
struct LocalClassroomSyncService: ClassroomSyncService {
    var teacherIdentity: TeacherSyncIdentity
    var rosterStore: ClassroomRosterStore
    var assignmentStore: ClassroomAssignmentStore

    init(
        teacherIdentity: TeacherSyncIdentity = TeacherSyncIdentity(),
        rosterStore: ClassroomRosterStore,
        assignmentStore: ClassroomAssignmentStore
    ) {
        self.teacherIdentity = teacherIdentity
        self.rosterStore = rosterStore
        self.assignmentStore = assignmentStore
    }

    func classroomPacket(for classroom: Classroom) -> ClassroomSyncPacket {
        ClassroomSyncPacket(
            id: classroom.id,
            teacherID: teacherIdentity.id,
            name: classroom.name,
            studentCount: classroom.students.count
        )
    }

    func publishAssignment(_ assignment: ClassroomAssignment, classroom: Classroom) throws -> AssignmentSyncPacket {
        guard assignment.classroomID == classroom.id else {
            throw ClassroomAssignmentStoreError.classroomMismatch
        }

        return assignmentPacket(for: assignment, classroom: classroom)
    }

    func resolveAssignment(classLessonCode: String) throws -> AssignmentSyncPacket {
        guard let assignment = assignmentStore.assignment(matchingClassLessonCode: classLessonCode) else {
            throw ClassroomAssignmentStoreError.classLessonCodeNotFound
        }
        guard let classroom = rosterStore.classrooms.first(where: { $0.id == assignment.classroomID }) else {
            throw ClassroomAssignmentStoreError.classroomMismatch
        }

        return assignmentPacket(for: assignment, classroom: classroom)
    }

    @discardableResult
    func submitWidgetScore(_ submission: StudentSubmissionPacket) throws -> StudentWidgetResult {
        guard let assignment = assignmentStore.assignment(matchingClassLessonCode: submission.classLessonCode) else {
            throw ClassroomAssignmentStoreError.classLessonCodeNotFound
        }
        guard assignment.id == submission.assignmentID else {
            throw ClassroomAssignmentStoreError.assignmentNotFound
        }
        guard assignment.classroomID == submission.classroomID,
              let classroom = rosterStore.classrooms.first(where: { $0.id == submission.classroomID }) else {
            throw ClassroomAssignmentStoreError.classroomMismatch
        }

        return try assignmentStore.recordWidgetScore(
            submission.widgetScoreRecord,
            classLessonCode: submission.classLessonCode,
            studentIdentifier: submission.studentIdentifier,
            classroom: classroom,
            submittedAt: submission.submittedAt
        )
    }

    func fetchSubmissions(assignmentID: UUID) throws -> [StudentWidgetResult] {
        guard assignmentStore.assignments.contains(where: { $0.id == assignmentID }) else {
            throw ClassroomAssignmentStoreError.assignmentNotFound
        }

        return assignmentStore.widgetResults
            .filter { $0.assignmentID == assignmentID }
            .sorted { $0.submittedAt < $1.submittedAt }
    }

    func publishTeacherInkChunk(_ chunk: TeacherInkStrokeChunk) throws {
        guard assignmentStore.assignment(matchingClassLessonCode: chunk.lessonCode) != nil else {
            throw ClassroomAssignmentStoreError.classLessonCodeNotFound
        }
    }

    func fetchTeacherInkChunks(classLessonCode: String) throws -> [TeacherInkStrokeChunk] {
        guard assignmentStore.assignment(matchingClassLessonCode: classLessonCode) != nil else {
            throw ClassroomAssignmentStoreError.classLessonCodeNotFound
        }
        return []
    }

    func publishTeacherInkDrawingSnapshot(_ snapshot: TeacherInkDrawingSnapshot) throws {
        guard assignmentStore.assignment(matchingClassLessonCode: snapshot.lessonCode) != nil else {
            throw ClassroomAssignmentStoreError.classLessonCodeNotFound
        }
    }

    func fetchTeacherInkDrawingSnapshots(classLessonCode: String) throws -> [TeacherInkDrawingSnapshot] {
        guard assignmentStore.assignment(matchingClassLessonCode: classLessonCode) != nil else {
            throw ClassroomAssignmentStoreError.classLessonCodeNotFound
        }
        return []
    }

    private func assignmentPacket(
        for assignment: ClassroomAssignment,
        classroom: Classroom
    ) -> AssignmentSyncPacket {
        AssignmentSyncPacket(
            id: assignment.id,
            teacherID: teacherIdentity.id,
            classroomID: assignment.classroomID,
            classroomName: classroom.name,
            lesson: assignment.lessonPackageManifest,
            classLessonCode: ClassroomAssignmentStore.normalizedClassLessonCode(assignment.classLessonCode),
            shareURL: assignment.shareURL,
            widgetSummaries: assignment.widgetSummaries,
            assignedAt: assignment.assignedAt
        )
    }
}
