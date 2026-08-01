import FirebaseFirestore
import FirebaseStorage
import Foundation
import WidgetEngine

@MainActor
struct FirebaseClassroomSyncService {
    private var teacherUserID: String?
    private var teacherEmail: String?
    private var firestore: Firestore
    private var storage: Storage

    init(
        teacherUserID: String? = nil,
        teacherEmail: String? = nil,
        firestore: Firestore = Firestore.firestore(),
        storage: Storage = Storage.storage()
    ) {
        self.teacherUserID = teacherUserID
        self.teacherEmail = teacherEmail
        self.firestore = firestore
        self.storage = storage
    }

    @discardableResult
    func publishAssignment(
        _ assignment: ClassroomAssignment,
        classroom: Classroom,
        lessonManifest: LessonPackageManifest? = nil
    ) async throws -> AssignmentSyncPacket {
        guard assignment.classroomID == classroom.id else {
            throw ClassroomAssignmentStoreError.classroomMismatch
        }
        guard let teacherUserID, !teacherUserID.isEmpty else {
            throw FirebaseClassroomSyncError.teacherNotSignedIn
        }

        let packet = assignmentPacket(for: assignment, classroom: classroom, lessonManifest: lessonManifest)
        let code = ClassroomAssignmentStore.normalizedClassLessonCode(packet.classLessonCode)
        let document = assignmentDocument(
            packet: packet,
            classroom: classroom,
            teacherUserID: teacherUserID,
            teacherEmail: teacherEmail
        )
        try await setData(document, at: codeDocument(for: code))
        return packet
    }

    func uploadLessonPackage(
        for lesson: Lesson,
        replacingPublishedVersion publishedVersion: LessonPublishedVersionMetadata? = nil
    ) async throws -> LessonPackageManifest {
        guard let teacherUserID, !teacherUserID.isEmpty else {
            throw FirebaseClassroomSyncError.teacherNotSignedIn
        }
        let archiveData = try MathBoardPackageArchiver().archivePackage(at: lesson.url)
        let checksum = MathBoardPackageArchiver.checksum(for: archiveData)
        let versionID = publishedVersion?.versionID ?? UUID()
        let publishedAt = Date()
        let versionNumber: Int
        if let publishedVersionNumber = publishedVersion?.versionNumber {
            versionNumber = publishedVersionNumber
        } else {
            versionNumber = try await nextLessonVersionNumber(forLessonID: lesson.id)
        }
        let fileName = publishedVersion?.packageFileName ?? "\(versionID.uuidString).\(MathBoardPackageArchiver.archiveExtension)"
        let storagePath = publishedVersion?.packageStoragePath
            ?? "teacherLessonPackages/\(teacherUserID)/\(lesson.id.uuidString)/versions/\(versionID.uuidString)/\(fileName)"
        let metadata = StorageMetadata()
        metadata.contentType = "application/octet-stream"
        metadata.customMetadata = [
            "lessonID": lesson.id.uuidString,
            "lessonVersionID": versionID.uuidString,
            "lessonVersionNumber": "\(versionNumber)",
            "lessonTitle": lesson.name,
            "packageFileName": lesson.url.lastPathComponent,
            "checksum": checksum
        ]

        try await putData(archiveData, metadata: metadata, at: storage.reference(withPath: storagePath))
        let manifest = LessonPackageManifest(
            id: lesson.id,
            title: lesson.name,
            versionID: versionID,
            versionNumber: versionNumber,
            packageFileName: lesson.url.lastPathComponent,
            packageStoragePath: storagePath,
            packageChecksum: checksum,
            publishedAt: publishedAt
        )
        try await publishLessonVersionManifest(manifest, teacherUserID: teacherUserID, teacherEmail: teacherEmail)
        return manifest
    }

    func assignmentHasStudentActivity(classLessonCode: String) async throws -> Bool {
        let code = ClassroomAssignmentStore.normalizedClassLessonCode(classLessonCode)
        guard !code.isEmpty else {
            throw ClassroomAssignmentStoreError.classLessonCodeNotFound
        }
        let document = codeDocument(for: code)
        let liveProgressSnapshot = try await getDocuments(from: document.collection("liveProgress").limit(to: 1))
        if !liveProgressSnapshot.documents.isEmpty {
            return true
        }
        let submissionsSnapshot = try await getDocuments(from: document.collection("submissions").limit(to: 1))
        return !submissionsSnapshot.documents.isEmpty
    }

    func downloadLessonPackageData(for manifest: LessonPackageManifest, maxSize: Int64 = 250 * 1024 * 1024) async throws -> Data {
        guard let storagePath = manifest.packageStoragePath, !storagePath.isEmpty else {
            throw FirebaseClassroomSyncError.missingLessonPackage
        }
        let data = try await getData(from: storage.reference(withPath: storagePath), maxSize: maxSize)
        if let expectedChecksum = manifest.packageChecksum {
            guard MathBoardPackageArchiver.checksum(for: data) == expectedChecksum else {
                throw FirebaseClassroomSyncError.lessonPackageChecksumMismatch
            }
        }
        return data
    }

    func resolveAssignment(classLessonCode: String) async throws -> AssignmentSyncPacket {
        let code = ClassroomAssignmentStore.normalizedClassLessonCode(classLessonCode)
        guard !code.isEmpty else {
            throw ClassroomAssignmentStoreError.classLessonCodeNotFound
        }

        let data = try await getData(from: codeDocument(for: code))
        return try assignmentPacket(from: data, fallbackCode: code)
    }

    @discardableResult
    func submitWidgetScore(_ submission: StudentSubmissionPacket) async throws -> StudentWidgetResult {
        let code = ClassroomAssignmentStore.normalizedClassLessonCode(submission.classLessonCode)
        guard !code.isEmpty else {
            throw ClassroomAssignmentStoreError.classLessonCodeNotFound
        }

        let document = codeDocument(for: code)
        let data = try await getData(from: document)
        let packet = try assignmentPacket(from: data, fallbackCode: code)
        guard packet.id == submission.assignmentID else {
            throw ClassroomAssignmentStoreError.assignmentNotFound
        }
        guard packet.classroomID == submission.classroomID else {
            throw ClassroomAssignmentStoreError.classroomMismatch
        }
        guard submission.widgetScoreRecord.status == .complete,
              submission.widgetScoreRecord.attempts > 0,
              let percent = submission.widgetScoreRecord.percent else {
            throw ClassroomAssignmentStoreError.incompleteWidgetScore
        }
        guard let widgetID = UUID(uuidString: submission.widgetScoreRecord.id) else {
            throw ClassroomAssignmentStoreError.invalidWidgetScoreRecord
        }
        guard packet.widgetSummaries.contains(where: { $0.widgetID == widgetID }) else {
            throw ClassroomAssignmentStoreError.widgetNotAssigned
        }

        let normalizedIdentifier = normalizedStudentIdentifier(submission.studentIdentifier)
        guard !normalizedIdentifier.isEmpty else {
            throw ClassroomAssignmentStoreError.studentNotFound
        }
        let result = StudentWidgetResult(
            assignmentID: packet.id,
            classroomID: packet.classroomID,
            studentID: stableStudentID(for: normalizedIdentifier),
            widgetID: widgetID,
            numberCorrectFirstTry: submission.widgetScoreRecord.numberCorrectFirstTry,
            numberCorrectAfterRetry: submission.widgetScoreRecord.numberCorrectAfterRetry,
            longestStreak: submission.widgetScoreRecord.longestStreak,
            finalPercentScore: Double(percent),
            submittedAt: submission.submittedAt
        )
        try await setData(submissionDocument(result: result, submission: submission), at: document
            .collection("submissions")
            .document(submissionDocumentID(studentIdentifier: normalizedIdentifier, widgetID: widgetID))
        )
        return result
    }

    func fetchSubmissions(classLessonCode: String) async throws -> [StudentWidgetResult] {
        let code = ClassroomAssignmentStore.normalizedClassLessonCode(classLessonCode)
        guard !code.isEmpty else {
            throw ClassroomAssignmentStoreError.classLessonCodeNotFound
        }

        let snapshot = try await getDocuments(from: codeDocument(for: code).collection("submissions"))
        return snapshot.documents.compactMap { submissionResult(from: $0.data()) }
            .sorted { $0.submittedAt < $1.submittedAt }
    }

    @discardableResult
    func publishLiveProgress(
        _ submission: StudentSubmissionPacket,
        isActiveOnStudentScreen: Bool = true
    ) async throws -> StudentWidgetLiveProgress {
        let code = ClassroomAssignmentStore.normalizedClassLessonCode(submission.classLessonCode)
        guard !code.isEmpty else {
            throw ClassroomAssignmentStoreError.classLessonCodeNotFound
        }

        let document = codeDocument(for: code)
        let data = try await getData(from: document)
        let packet = try assignmentPacket(from: data, fallbackCode: code)
        guard packet.id == submission.assignmentID else {
            throw ClassroomAssignmentStoreError.assignmentNotFound
        }
        guard packet.classroomID == submission.classroomID else {
            throw ClassroomAssignmentStoreError.classroomMismatch
        }
        guard let widgetID = UUID(uuidString: submission.widgetScoreRecord.id) else {
            throw ClassroomAssignmentStoreError.invalidWidgetScoreRecord
        }
        guard packet.widgetSummaries.contains(where: { $0.widgetID == widgetID }) else {
            throw ClassroomAssignmentStoreError.widgetNotAssigned
        }

        let normalizedIdentifier = normalizedStudentIdentifier(submission.studentIdentifier)
        guard !normalizedIdentifier.isEmpty else {
            throw ClassroomAssignmentStoreError.studentNotFound
        }
        let preferredFirstName = normalizedPreferredFirstName(submission.studentPreferredFirstName)
        let progress = StudentWidgetLiveProgress(
            assignmentID: packet.id,
            classroomID: packet.classroomID,
            studentID: stableStudentID(for: normalizedIdentifier),
            studentIdentifier: normalizedIdentifier,
            studentName: preferredFirstName ?? "Student \(normalizedIdentifier)",
            studentPreferredFirstName: preferredFirstName,
            widgetID: widgetID,
            correctCount: submission.widgetScoreRecord.score,
            attemptedCount: submission.widgetScoreRecord.attempts,
            status: submission.widgetScoreRecord.status,
            isActiveOnStudentScreen: isActiveOnStudentScreen,
            updatedAt: submission.submittedAt
        )
        try await setData(liveProgressDocument(progress), at: document
            .collection("liveProgress")
            .document(submissionDocumentID(studentIdentifier: normalizedIdentifier, widgetID: widgetID))
        )
        return progress
    }

    func fetchLiveProgress(classLessonCode: String) async throws -> [StudentWidgetLiveProgress] {
        let code = ClassroomAssignmentStore.normalizedClassLessonCode(classLessonCode)
        guard !code.isEmpty else {
            throw ClassroomAssignmentStoreError.classLessonCodeNotFound
        }

        let snapshot = try await getDocuments(from: codeDocument(for: code).collection("liveProgress"))
        return snapshot.documents.compactMap { liveProgress(from: $0.data()) }
            .sorted { first, second in
                if first.studentName == second.studentName {
                    return first.updatedAt > second.updatedAt
                }
                return first.studentName.localizedStandardCompare(second.studentName) == .orderedAscending
            }
    }

    private func codeDocument(for code: String) -> DocumentReference {
        firestore.collection("classLessonCodes").document(code)
    }

    private func lessonDocument(for lessonID: UUID) -> DocumentReference {
        firestore.collection("lessons").document(lessonID.uuidString)
    }

    private func lessonVersionDocument(for versionID: UUID) -> DocumentReference {
        firestore.collection("lessonVersions").document(versionID.uuidString)
    }

    private func nextLessonVersionNumber(forLessonID lessonID: UUID) async throws -> Int {
        do {
            let data = try await getData(from: lessonDocument(for: lessonID))
            return intValue(data["currentVersion"]) + 1
        } catch ClassroomAssignmentStoreError.classLessonCodeNotFound {
            return 1
        }
    }

    private func publishLessonVersionManifest(
        _ manifest: LessonPackageManifest,
        teacherUserID: String,
        teacherEmail: String?
    ) async throws {
        guard let versionID = manifest.versionID,
              let versionNumber = manifest.versionNumber,
              let storagePath = manifest.packageStoragePath,
              let checksum = manifest.packageChecksum else {
            throw FirebaseClassroomSyncError.malformedAssignment
        }

        var lessonDocumentData: [String: Any] = [
            "lessonID": manifest.id.uuidString,
            "ownerID": teacherUserID,
            "title": manifest.title,
            "currentVersion": versionNumber,
            "currentVersionID": versionID.uuidString,
            "updatedAt": Timestamp(date: manifest.publishedAt ?? Date())
        ]
        if let teacherEmail {
            lessonDocumentData["ownerEmail"] = teacherEmail
        }

        var versionDocumentData: [String: Any] = [
            "versionID": versionID.uuidString,
            "lessonID": manifest.id.uuidString,
            "versionNumber": versionNumber,
            "title": manifest.title,
            "storagePath": storagePath,
            "manifestHash": checksum,
            "packageChecksum": checksum,
            "createdAt": Timestamp(date: manifest.publishedAt ?? Date()),
            "ownerID": teacherUserID
        ]
        if let packageFileName = manifest.packageFileName {
            versionDocumentData["packageFileName"] = packageFileName
        }
        if let teacherEmail {
            versionDocumentData["ownerEmail"] = teacherEmail
        }

        try await setData(lessonDocumentData, at: lessonDocument(for: manifest.id))
        try await setData(versionDocumentData, at: lessonVersionDocument(for: versionID))
    }

    private func assignmentPacket(
        for assignment: ClassroomAssignment,
        classroom: Classroom,
        lessonManifest: LessonPackageManifest?
    ) -> AssignmentSyncPacket {
        AssignmentSyncPacket(
            id: assignment.id,
            teacherID: UUID(uuidString: teacherUserID ?? "") ?? UUID(),
            classroomID: assignment.classroomID,
            classroomName: classroom.name,
            lesson: lessonManifest ?? assignment.lessonPackageManifest,
            classLessonCode: ClassroomAssignmentStore.normalizedClassLessonCode(assignment.classLessonCode),
            shareURL: assignment.shareURL,
            widgetSummaries: assignment.widgetSummaries,
            assignedAt: assignment.assignedAt
        )
    }

    private func assignmentDocument(
        packet: AssignmentSyncPacket,
        classroom: Classroom,
        teacherUserID: String,
        teacherEmail: String?
    ) -> [String: Any] {
        var document: [String: Any] = [
            "assignmentID": packet.id.uuidString,
            "teacherUserID": teacherUserID,
            "classroomID": packet.classroomID.uuidString,
            "classroomName": packet.classroomName,
            "lessonID": packet.lesson.id.uuidString,
            "lessonPackageID": packet.lesson.id.uuidString,
            "lessonTitle": packet.lesson.title,
            "classLessonCode": packet.classLessonCode,
            "assignedAt": Timestamp(date: packet.assignedAt),
            "widgetSummaries": packet.widgetSummaries.map(widgetSummaryDocument)
        ]
        if let teacherEmail {
            document["teacherEmail"] = teacherEmail
        }
        if let shareURL = packet.shareURL?.absoluteString {
            document["shareURL"] = shareURL
        }
        if let versionID = packet.lesson.versionID {
            document["lessonVersionID"] = versionID.uuidString
        }
        if let versionNumber = packet.lesson.versionNumber {
            document["lessonVersionNumber"] = versionNumber
        }
        if let publishedAt = packet.lesson.publishedAt {
            document["lessonVersionPublishedAt"] = Timestamp(date: publishedAt)
        }
        if let packageFileName = packet.lesson.packageFileName {
            document["lessonPackageFileName"] = packageFileName
        }
        if let packageStoragePath = packet.lesson.packageStoragePath {
            document["lessonPackageStoragePath"] = packageStoragePath
        }
        if let packageChecksum = packet.lesson.packageChecksum {
            document["lessonPackageChecksum"] = packageChecksum
        }
        return document
    }

    private func assignmentPacket(from data: [String: Any], fallbackCode: String) throws -> AssignmentSyncPacket {
        guard let assignmentID = uuidValue(data["assignmentID"]),
              let classroomID = uuidValue(data["classroomID"]),
              let lessonID = uuidValue(data["lessonPackageID"]) ?? uuidValue(data["lessonID"]),
              let classroomName = data["classroomName"] as? String,
              let lessonTitle = data["lessonTitle"] as? String else {
            throw FirebaseClassroomSyncError.malformedAssignment
        }
        let widgetSummaries = (data["widgetSummaries"] as? [[String: Any]] ?? []).compactMap(widgetSummary)
        let assignedAt = (data["assignedAt"] as? Timestamp)?.dateValue() ?? Date()
        let shareURL = (data["shareURL"] as? String).flatMap(URL.init(string:))
        return AssignmentSyncPacket(
            id: assignmentID,
            teacherID: UUID(uuidString: data["teacherUserID"] as? String ?? "") ?? UUID(),
            classroomID: classroomID,
            classroomName: classroomName,
            lesson: LessonPackageManifest(
                id: lessonID,
                title: lessonTitle,
                versionID: uuidValue(data["lessonVersionID"]),
                versionNumber: optionalIntValue(data["lessonVersionNumber"]),
                packageFileName: data["lessonPackageFileName"] as? String,
                packageStoragePath: data["lessonPackageStoragePath"] as? String,
                packageChecksum: data["lessonPackageChecksum"] as? String,
                publishedAt: (data["lessonVersionPublishedAt"] as? Timestamp)?.dateValue()
            ),
            classLessonCode: data["classLessonCode"] as? String ?? fallbackCode,
            shareURL: shareURL,
            widgetSummaries: widgetSummaries,
            assignedAt: assignedAt
        )
    }

    private func widgetSummaryDocument(_ summary: AssignedWidgetSummary) -> [String: Any] {
        [
            "id": summary.id.uuidString,
            "widgetID": summary.widgetID.uuidString,
            "title": summary.title,
            "maxScore": summary.maxScore,
            "scoreMode": summary.scoreMode.rawValue
        ]
    }

    private func widgetSummary(from data: [String: Any]) -> AssignedWidgetSummary? {
        guard let id = uuidValue(data["id"]),
              let widgetID = uuidValue(data["widgetID"]),
              let title = data["title"] as? String else {
            return nil
        }
        let scoreMode = (data["scoreMode"] as? String).flatMap(WidgetScoreMode.init(rawValue:)) ?? .percentAverage
        return AssignedWidgetSummary(
            id: id,
            widgetID: widgetID,
            title: title,
            maxScore: data["maxScore"] as? Double ?? 0,
            scoreMode: scoreMode
        )
    }

    private func rosterStudentDocument(_ student: RosterStudent) -> [String: Any] {
        [
            "id": student.id.uuidString,
            "firstName": student.firstName,
            "lastName": student.lastName,
            "officialStudentID": student.officialStudentID,
            "alternateStudentID": student.alternateStudentID
        ]
    }

    private func rosterStudents(from data: [String: Any]) -> [RosterStudent] {
        (data["students"] as? [[String: Any]] ?? []).compactMap { studentData in
            guard let id = uuidValue(studentData["id"]) else { return nil }
            return RosterStudent(
                id: id,
                firstName: studentData["firstName"] as? String ?? "",
                lastName: studentData["lastName"] as? String ?? "",
                officialStudentID: studentData["officialStudentID"] as? String ?? "",
                alternateStudentID: studentData["alternateStudentID"] as? String ?? ""
            )
        }
    }

    private func student(matching identifier: String, in students: [RosterStudent]) throws -> RosterStudent {
        let normalizedIdentifier = normalizedStudentIdentifier(identifier)
        guard !normalizedIdentifier.isEmpty else {
            throw ClassroomAssignmentStoreError.studentNotFound
        }
        let matches = students.filter { student in
            normalizedStudentIdentifier(student.officialStudentID) == normalizedIdentifier ||
            normalizedStudentIdentifier(student.alternateStudentID) == normalizedIdentifier
        }
        guard !matches.isEmpty else {
            throw ClassroomAssignmentStoreError.studentNotFound
        }
        guard matches.count == 1, let student = matches.first else {
            throw ClassroomAssignmentStoreError.ambiguousStudentIdentifier
        }
        return student
    }

    private func submissionDocument(result: StudentWidgetResult, submission: StudentSubmissionPacket) -> [String: Any] {
        var document: [String: Any] = [
            "id": result.id.uuidString,
            "assignmentID": result.assignmentID.uuidString,
            "classroomID": result.classroomID.uuidString,
            "studentID": result.studentID.uuidString,
            "studentIdentifier": normalizedStudentIdentifier(submission.studentIdentifier),
            "widgetID": result.widgetID.uuidString,
            "numberCorrectFirstTry": result.numberCorrectFirstTry,
            "numberCorrectAfterRetry": result.numberCorrectAfterRetry,
            "longestStreak": result.longestStreak,
            "finalPercentScore": result.finalPercentScore,
            "submittedAt": Timestamp(date: result.submittedAt)
        ]
        if let preferredFirstName = normalizedPreferredFirstName(submission.studentPreferredFirstName) {
            document["studentPreferredFirstName"] = preferredFirstName
        }
        return document
    }

    private func liveProgressDocument(_ progress: StudentWidgetLiveProgress) -> [String: Any] {
        var document: [String: Any] = [
            "assignmentID": progress.assignmentID.uuidString,
            "classroomID": progress.classroomID.uuidString,
            "studentID": progress.studentID.uuidString,
            "studentIdentifier": progress.studentIdentifier,
            "studentName": progress.studentName,
            "widgetID": progress.widgetID.uuidString,
            "correctCount": progress.correctCount,
            "attemptedCount": progress.attemptedCount,
            "status": progress.status.rawValue,
            "isActiveOnStudentScreen": progress.isActiveOnStudentScreen,
            "updatedAt": Timestamp(date: progress.updatedAt)
        ]
        if let preferredFirstName = normalizedPreferredFirstName(progress.studentPreferredFirstName) {
            document["studentPreferredFirstName"] = preferredFirstName
        }
        return document
    }

    private func submissionResult(from data: [String: Any]) -> StudentWidgetResult? {
        guard let id = uuidValue(data["id"]),
              let assignmentID = uuidValue(data["assignmentID"]),
              let classroomID = uuidValue(data["classroomID"]),
              let studentID = uuidValue(data["studentID"]),
              let widgetID = uuidValue(data["widgetID"]) else {
            return nil
        }
        return StudentWidgetResult(
            id: id,
            assignmentID: assignmentID,
            classroomID: classroomID,
            studentID: studentID,
            widgetID: widgetID,
            numberCorrectFirstTry: intValue(data["numberCorrectFirstTry"]),
            numberCorrectAfterRetry: intValue(data["numberCorrectAfterRetry"]),
            longestStreak: intValue(data["longestStreak"]),
            finalPercentScore: doubleValue(data["finalPercentScore"]),
            submittedAt: timestampValue(data["submittedAt"])
        )
    }

    private func liveProgress(from data: [String: Any]) -> StudentWidgetLiveProgress? {
        guard let assignmentID = uuidValue(data["assignmentID"]),
              let classroomID = uuidValue(data["classroomID"]),
              let widgetID = uuidValue(data["widgetID"]) else {
            return nil
        }
        let studentIdentifier = normalizedStudentIdentifier(data["studentIdentifier"] as? String ?? "")
        let studentID = uuidValue(data["studentID"]) ?? stableStudentID(for: studentIdentifier)
        let status = (data["status"] as? String).flatMap(WidgetActivityScoreStatus.init(rawValue:)) ?? .inProgress
        return StudentWidgetLiveProgress(
            assignmentID: assignmentID,
            classroomID: classroomID,
            studentID: studentID,
            studentIdentifier: studentIdentifier,
            studentName: data["studentName"] as? String ?? "Unnamed Student",
            studentPreferredFirstName: normalizedPreferredFirstName(data["studentPreferredFirstName"] as? String),
            widgetID: widgetID,
            correctCount: intValue(data["correctCount"]),
            attemptedCount: intValue(data["attemptedCount"]),
            status: status,
            isActiveOnStudentScreen: data["isActiveOnStudentScreen"] as? Bool ?? false,
            updatedAt: timestampValue(data["updatedAt"])
        )
    }

    private func submissionDocumentID(studentIdentifier: String, widgetID: UUID) -> String {
        "\(safeDocumentIDComponent(studentIdentifier))_\(widgetID.uuidString)"
    }

    private func safeDocumentIDComponent(_ value: String) -> String {
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { scalar in
            allowedCharacters.contains(scalar) ? Character(scalar) : Character("-")
        }
        let component = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return component.isEmpty ? "student" : component
    }

    private func uuidValue(_ value: Any?) -> UUID? {
        if let uuid = value as? UUID {
            return uuid
        }
        if let string = value as? String {
            return UUID(uuidString: string)
        }
        return nil
    }

    private func intValue(_ value: Any?) -> Int {
        if let int = value as? Int {
            return int
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        return 0
    }

    private func optionalIntValue(_ value: Any?) -> Int? {
        if let int = value as? Int {
            return int
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        return nil
    }

    private func doubleValue(_ value: Any?) -> Double {
        if let double = value as? Double {
            return double
        }
        if let int = value as? Int {
            return Double(int)
        }
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        return 0
    }

    private func timestampValue(_ value: Any?) -> Date {
        if let timestamp = value as? Timestamp {
            return timestamp.dateValue()
        }
        if let date = value as? Date {
            return date
        }
        return Date()
    }

    private func normalizedStudentIdentifier(_ identifier: String) -> String {
        identifier.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private func normalizedPreferredFirstName(_ name: String?) -> String? {
        guard let name else { return nil }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? nil : String(trimmedName.prefix(40))
    }

    private func stableStudentID(for normalizedIdentifier: String) -> UUID {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in normalizedIdentifier.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        let hex = String(format: "%016llX%016llX", hash, hash ^ 0xA5A5A5A5A5A5A5A5)
        let uuidString = "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20).prefix(12))"
        return UUID(uuidString: uuidString) ?? UUID()
    }

    private func setData(_ data: [String: Any], at document: DocumentReference) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            document.setData(data, merge: true) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func getData(from document: DocumentReference) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String: Any], Error>) in
            document.getDocument { snapshot, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let snapshot, snapshot.exists, let data = snapshot.data() else {
                    continuation.resume(throwing: ClassroomAssignmentStoreError.classLessonCodeNotFound)
                    return
                }
                continuation.resume(returning: data)
            }
        }
    }

    private func getDocuments(from collection: CollectionReference) async throws -> QuerySnapshot {
        try await getDocuments(from: collection as Query)
    }

    private func getDocuments(from query: Query) async throws -> QuerySnapshot {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<QuerySnapshot, Error>) in
            query.getDocuments { snapshot, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let snapshot else {
                    continuation.resume(throwing: ClassroomAssignmentStoreError.assignmentNotFound)
                    return
                }
                continuation.resume(returning: snapshot)
            }
        }
    }

    private func putData(_ data: Data, metadata: StorageMetadata, at reference: StorageReference) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            reference.putData(data, metadata: metadata) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func getData(from reference: StorageReference, maxSize: Int64) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            reference.getData(maxSize: maxSize) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data else {
                    continuation.resume(throwing: FirebaseClassroomSyncError.missingLessonPackage)
                    return
                }
                continuation.resume(returning: data)
            }
        }
    }
}

private extension RosterStudent {
    var displayName: String {
        let name = [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return name.isEmpty ? "Unnamed Student" : name
    }
}

private enum FirebaseClassroomSyncError: LocalizedError {
    case teacherNotSignedIn
    case malformedAssignment
    case missingLessonPackage
    case lessonPackageChecksumMismatch

    var errorDescription: String? {
        switch self {
        case .teacherNotSignedIn:
            "Sign in with a teacher account before assigning lessons online."
        case .malformedAssignment:
            "MathBoard could not read that online lesson assignment."
        case .missingLessonPackage:
            "This online lesson does not include a downloadable MathBoard file yet."
        case .lessonPackageChecksumMismatch:
            "The downloaded MathBoard lesson did not match the teacher's uploaded file."
        }
    }
}
