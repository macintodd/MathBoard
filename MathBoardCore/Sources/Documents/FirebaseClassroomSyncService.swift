import Canvas
import CryptoKit
import FirebaseFirestore
import FirebaseStorage
import Foundation
import LiveClassroom
import WidgetEngine

@MainActor
struct FirebaseClassroomSyncService {
    private var teacherUserID: String?
    private var teacherEmail: String?
    private var firestore: Firestore
    private var storage: Storage
    private static let inlineTeacherObjectSnapshotLimit = 700_000
    private static let teacherObjectSnapshotStorageMaxSize: Int64 = 75 * 1024 * 1024

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
        try await publishStudentAssignmentAccessDocuments(
            packet: packet,
            classroom: classroom,
            teacherUserID: teacherUserID,
            teacherEmail: teacherEmail
        )
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

    func resolveAssignment(classLessonCode: String, studentIdentifier: String) async throws -> AssignmentSyncPacket {
        let code = ClassroomAssignmentStore.normalizedClassLessonCode(classLessonCode)
        let normalizedIdentifier = normalizedStudentIdentifier(studentIdentifier)
        guard !code.isEmpty, !normalizedIdentifier.isEmpty else {
            throw ClassroomAssignmentStoreError.classLessonCodeNotFound
        }
        let identifierHash = studentIdentifierHash(forNormalizedIdentifier: normalizedIdentifier)
        return try await resolveAssignmentForValidatedStudent(code: code, studentIdentifierHash: identifierHash)
    }

    private func resolveAssignmentForValidatedStudent(code: String, studentIdentifierHash: String) async throws -> AssignmentSyncPacket {
        do {
            let data = try await getData(from: studentAccessDocument(forCode: code, studentIdentifierHash: studentIdentifierHash))
            let packet = try assignmentPacket(from: data, fallbackCode: code)
            try validateStudentIdentifierHash(studentIdentifierHash, isAllowedFor: packet)
            return packet
        } catch ClassroomAssignmentStoreError.classLessonCodeNotFound {
            let packet = try await resolveAssignment(classLessonCode: code)
            try validateStudentIdentifierHash(studentIdentifierHash, isAllowedFor: packet)
            return packet
        }
    }

    @discardableResult
    func submitWidgetScore(_ submission: StudentSubmissionPacket) async throws -> StudentWidgetResult {
        let code = ClassroomAssignmentStore.normalizedClassLessonCode(submission.classLessonCode)
        guard !code.isEmpty else {
            throw ClassroomAssignmentStoreError.classLessonCodeNotFound
        }

        let normalizedIdentifier = normalizedStudentIdentifier(submission.studentIdentifier)
        guard !normalizedIdentifier.isEmpty else {
            throw ClassroomAssignmentStoreError.studentNotFound
        }
        let identifierHash = studentIdentifierHash(forNormalizedIdentifier: normalizedIdentifier)
        let document = codeDocument(for: code)
        let packet = try await resolveAssignmentForValidatedStudent(
            code: code,
            studentIdentifierHash: identifierHash
        )
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
    func publishLessonPresence(
        assignmentPacket: AssignmentSyncPacket,
        studentIdentifier: String,
        studentPreferredFirstName: String?
    ) async throws -> StudentWidgetLiveProgress {
        let code = ClassroomAssignmentStore.normalizedClassLessonCode(assignmentPacket.classLessonCode)
        guard !code.isEmpty else {
            throw ClassroomAssignmentStoreError.classLessonCodeNotFound
        }

        let normalizedIdentifier = normalizedStudentIdentifier(studentIdentifier)
        guard !normalizedIdentifier.isEmpty else {
            throw ClassroomAssignmentStoreError.studentNotFound
        }
        let identifierHash = studentIdentifierHash(forNormalizedIdentifier: normalizedIdentifier)
        let packet = try await resolveAssignmentForValidatedStudent(
            code: code,
            studentIdentifierHash: identifierHash
        )
        guard packet.id == assignmentPacket.id else {
            throw ClassroomAssignmentStoreError.assignmentNotFound
        }
        guard packet.classroomID == assignmentPacket.classroomID else {
            throw ClassroomAssignmentStoreError.classroomMismatch
        }

        let preferredFirstName = normalizedPreferredFirstName(studentPreferredFirstName)
        let presence = StudentWidgetLiveProgress(
            assignmentID: packet.id,
            classroomID: packet.classroomID,
            studentID: stableStudentID(for: normalizedIdentifier),
            studentIdentifier: normalizedIdentifier,
            studentName: preferredFirstName ?? "Student \(normalizedIdentifier)",
            studentPreferredFirstName: preferredFirstName,
            widgetID: StudentWidgetLiveProgress.lessonPresenceWidgetID,
            correctCount: 0,
            attemptedCount: 0,
            status: .inProgress,
            isActiveOnStudentScreen: false,
            updatedAt: Date()
        )
        try await setData(
            liveProgressDocument(
                presence,
                classLessonCode: code,
                studentIdentifierHash: identifierHash
            ),
            at: codeDocument(for: code)
                .collection("liveProgress")
                .document(submissionDocumentID(studentIdentifier: normalizedIdentifier, widgetID: StudentWidgetLiveProgress.lessonPresenceWidgetID))
        )
        return presence
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

        let normalizedIdentifier = normalizedStudentIdentifier(submission.studentIdentifier)
        guard !normalizedIdentifier.isEmpty else {
            throw ClassroomAssignmentStoreError.studentNotFound
        }
        let identifierHash = studentIdentifierHash(forNormalizedIdentifier: normalizedIdentifier)
        let document = codeDocument(for: code)
        let packet = try await resolveAssignmentForValidatedStudent(
            code: code,
            studentIdentifierHash: identifierHash
        )
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
        try await setData(
            liveProgressDocument(
                progress,
                classLessonCode: code,
                studentIdentifierHash: identifierHash
            ),
            at: document
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

    func publishTeacherInkChunk(_ chunk: TeacherInkStrokeChunk) async throws {
        let code = ClassroomAssignmentStore.normalizedClassLessonCode(chunk.lessonCode)
        guard !code.isEmpty else {
            throw ClassroomAssignmentStoreError.classLessonCodeNotFound
        }
        guard chunk.isFinalChunk else { return }
        guard let teacherUserID, !teacherUserID.isEmpty else {
            throw FirebaseClassroomSyncError.teacherNotSignedIn
        }
        let assignmentData = try await getData(from: codeDocument(for: code))
        guard assignmentData["teacherUserID"] as? String == teacherUserID else {
            throw FirebaseClassroomSyncError.teacherNotSignedIn
        }

        try await setData(
            teacherInkDocument(chunk, teacherUserID: teacherUserID),
            at: codeDocument(for: code)
                .collection("teacherInk")
                .document(chunk.strokeID.uuidString)
        )
    }

    func fetchTeacherInkChunks(classLessonCode: String) async throws -> [TeacherInkStrokeChunk] {
        let code = ClassroomAssignmentStore.normalizedClassLessonCode(classLessonCode)
        guard !code.isEmpty else {
            throw ClassroomAssignmentStoreError.classLessonCodeNotFound
        }

        let snapshot = try await getDocuments(
            from: codeDocument(for: code)
                .collection("teacherInk")
                .order(by: "sentAt")
        )
        return snapshot.documents.compactMap { teacherInkChunk(from: $0.data(), fallbackCode: code) }
            .filter(\.isFinalChunk)
            .sorted { first, second in
                if first.sentAt == second.sentAt {
                    return first.sequence < second.sequence
                }
                return first.sentAt < second.sentAt
            }
    }

    func publishTeacherInkDrawingSnapshot(_ snapshot: TeacherInkDrawingSnapshot) async throws {
        let code = ClassroomAssignmentStore.normalizedClassLessonCode(snapshot.lessonCode)
        guard !code.isEmpty else {
            throw ClassroomAssignmentStoreError.classLessonCodeNotFound
        }
        guard let teacherUserID, !teacherUserID.isEmpty else {
            throw FirebaseClassroomSyncError.teacherNotSignedIn
        }
        let assignmentData = try await getData(from: codeDocument(for: code))
        guard assignmentData["teacherUserID"] as? String == teacherUserID else {
            throw FirebaseClassroomSyncError.teacherNotSignedIn
        }

        let document = codeDocument(for: code)
            .collection("teacherInkSnapshots")
            .document(snapshot.slideID.uuidString)
        guard try await shouldWriteRevision(snapshot.revision, to: document) else { return }

        try await setData(
            teacherInkDrawingSnapshotDocument(snapshot, teacherUserID: teacherUserID),
            at: document
        )
    }

    func fetchTeacherInkDrawingSnapshots(classLessonCode: String) async throws -> [TeacherInkDrawingSnapshot] {
        let code = ClassroomAssignmentStore.normalizedClassLessonCode(classLessonCode)
        guard !code.isEmpty else {
            throw ClassroomAssignmentStoreError.classLessonCodeNotFound
        }

        let snapshot = try await getDocuments(from: codeDocument(for: code).collection("teacherInkSnapshots"))
        return snapshot.documents.compactMap { teacherInkDrawingSnapshot(from: $0.data(), fallbackCode: code) }
            .sorted { first, second in
                if first.slideID == second.slideID {
                    return first.revision < second.revision
                }
                return first.sentAt < second.sentAt
            }
    }

    func publishTeacherObjectSnapshot(_ snapshot: TeacherObjectSnapshot) async throws {
        let code = ClassroomAssignmentStore.normalizedClassLessonCode(snapshot.lessonCode)
        guard !code.isEmpty else {
            throw ClassroomAssignmentStoreError.classLessonCodeNotFound
        }
        guard let teacherUserID, !teacherUserID.isEmpty else {
            throw FirebaseClassroomSyncError.teacherNotSignedIn
        }
        let assignmentData = try await getData(from: codeDocument(for: code))
        guard assignmentData["teacherUserID"] as? String == teacherUserID else {
            throw FirebaseClassroomSyncError.teacherNotSignedIn
        }

        let document = codeDocument(for: code)
            .collection("teacherObjects")
            .document(snapshot.slideID.uuidString)
        guard try await shouldWriteRevision(snapshot.revision, to: document) else { return }

        let snapshotDocument = try await storageBackedTeacherObjectSnapshotDocumentIfNeeded(
            snapshot,
            code: code,
            teacherUserID: teacherUserID
        )
        try await setData(
            snapshotDocument,
            at: document
        )
    }

    func fetchTeacherObjectSnapshots(classLessonCode: String) async throws -> [TeacherObjectSnapshot] {
        let code = ClassroomAssignmentStore.normalizedClassLessonCode(classLessonCode)
        guard !code.isEmpty else {
            throw ClassroomAssignmentStoreError.classLessonCodeNotFound
        }

        let snapshot = try await getDocuments(from: codeDocument(for: code).collection("teacherObjects"))
        var objectSnapshots: [TeacherObjectSnapshot] = []
        for document in snapshot.documents {
            if let objectSnapshot = try await teacherObjectSnapshot(from: document.data(), fallbackCode: code) {
                objectSnapshots.append(objectSnapshot)
            }
        }
        return sortedTeacherObjectSnapshots(objectSnapshots)
    }

    func listenToTeacherObjectSnapshots(
        classLessonCode: String,
        onChange: @escaping @MainActor ([TeacherObjectSnapshot]) -> Void
    ) -> ListenerRegistration? {
        let code = ClassroomAssignmentStore.normalizedClassLessonCode(classLessonCode)
        guard !code.isEmpty else { return nil }

        return codeDocument(for: code)
            .collection("teacherObjects")
            .addSnapshotListener { snapshot, error in
                Task { @MainActor in
                    if let error {
                        print("[StudentMode] durable teacher object listener error: \(error)")
                        return
                    }
                    guard let snapshot else { return }
                    do {
                        var objectSnapshots: [TeacherObjectSnapshot] = []
                        for document in snapshot.documents {
                            if let objectSnapshot = try await teacherObjectSnapshot(from: document.data(), fallbackCode: code) {
                                objectSnapshots.append(objectSnapshot)
                            }
                        }
                        objectSnapshots = sortedTeacherObjectSnapshots(objectSnapshots)
                        print("[StudentMode] durable teacher object listener received snapshots=\(objectSnapshots.count)")
                        onChange(objectSnapshots)
                    } catch {
                        print("[StudentMode] durable teacher object listener hydration error: \(error)")
                    }
                }
            }
    }

    func publishTeacherSlideManifestSnapshot(_ snapshot: TeacherSlideManifestSnapshot) async throws {
        let code = ClassroomAssignmentStore.normalizedClassLessonCode(snapshot.lessonCode)
        guard !code.isEmpty else {
            throw ClassroomAssignmentStoreError.classLessonCodeNotFound
        }
        guard let teacherUserID, !teacherUserID.isEmpty else {
            throw FirebaseClassroomSyncError.teacherNotSignedIn
        }
        let assignmentData = try await getData(from: codeDocument(for: code))
        guard assignmentData["teacherUserID"] as? String == teacherUserID else {
            throw FirebaseClassroomSyncError.teacherNotSignedIn
        }

        let document = codeDocument(for: code)
            .collection("teacherSlides")
            .document("current")
        guard try await shouldWriteRevision(snapshot.revision, to: document) else { return }

        let storageBackedSnapshot = try await snapshotWithUploadedSlideBackgroundAssets(snapshot, code: code)
        guard try await shouldWriteRevision(storageBackedSnapshot.revision, to: document) else { return }

        try await setData(
            teacherSlideManifestSnapshotDocument(storageBackedSnapshot, teacherUserID: teacherUserID),
            at: document
        )
    }

    func fetchTeacherSlideManifestSnapshot(classLessonCode: String) async throws -> TeacherSlideManifestSnapshot? {
        let code = ClassroomAssignmentStore.normalizedClassLessonCode(classLessonCode)
        guard !code.isEmpty else {
            throw ClassroomAssignmentStoreError.classLessonCodeNotFound
        }

        do {
            let data = try await getData(
                from: codeDocument(for: code)
                    .collection("teacherSlides")
                    .document("current")
            )
            guard let snapshot = teacherSlideManifestSnapshot(from: data, fallbackCode: code) else { return nil }
            return try await snapshotWithDownloadedSlideBackgroundAssets(snapshot)
        } catch ClassroomAssignmentStoreError.classLessonCodeNotFound {
            return nil
        }
    }

    func listenToTeacherSlideManifestSnapshot(
        classLessonCode: String,
        onChange: @escaping @MainActor (TeacherSlideManifestSnapshot) -> Void
    ) -> ListenerRegistration? {
        let code = ClassroomAssignmentStore.normalizedClassLessonCode(classLessonCode)
        guard !code.isEmpty else { return nil }
        let document = codeDocument(for: code)
            .collection("teacherSlides")
            .document("current")

        return document.addSnapshotListener { snapshot, error in
            Task { @MainActor in
                if let error {
                    print("[StudentMode] durable teacher slide manifest listener error: \(error)")
                    return
                }
                guard let data = snapshot?.data(),
                      let snapshot = teacherSlideManifestSnapshot(from: data, fallbackCode: code) else {
                    return
                }

                do {
                    let hydratedSnapshot = try await snapshotWithDownloadedSlideBackgroundAssets(snapshot)
                    print("[StudentMode] durable teacher slide manifest listener received revision=\(hydratedSnapshot.revision) slides=\(hydratedSnapshot.slides.count)")
                    onChange(hydratedSnapshot)
                } catch {
                    print("[StudentMode] durable teacher slide manifest listener hydration error: \(error)")
                }
            }
        }
    }

    private func codeDocument(for code: String) -> DocumentReference {
        firestore.collection("classLessonCodes").document(code)
    }

    private func studentAccessDocument(forCode code: String, studentIdentifierHash: String) -> DocumentReference {
        firestore.collection("studentAssignmentAccess").document(studentAccessDocumentID(forCode: code, studentIdentifierHash: studentIdentifierHash))
    }

    private func studentAccessDocumentID(forCode code: String, studentIdentifierHash: String) -> String {
        "\(ClassroomAssignmentStore.normalizedClassLessonCode(code))_\(studentIdentifierHash)"
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
            assignedAt: assignment.assignedAt,
            allowedStudentIdentifierHashes: allowedStudentIdentifierHashes(for: classroom)
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
            "widgetSummaries": packet.widgetSummaries.map(widgetSummaryDocument),
            "allowedStudentIdentifierHashes": allowedStudentIdentifierHashes(for: classroom)
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

    private func publishStudentAssignmentAccessDocuments(
        packet: AssignmentSyncPacket,
        classroom: Classroom,
        teacherUserID: String,
        teacherEmail: String?
    ) async throws {
        let code = ClassroomAssignmentStore.normalizedClassLessonCode(packet.classLessonCode)
        let hashes = allowedStudentIdentifierHashes(for: classroom)
        guard !code.isEmpty, !hashes.isEmpty else { return }

        for hash in hashes {
            try await setData(
                studentAssignmentAccessDocument(
                    packet: packet,
                    studentIdentifierHash: hash,
                    teacherUserID: teacherUserID,
                    teacherEmail: teacherEmail
                ),
                at: studentAccessDocument(forCode: code, studentIdentifierHash: hash)
            )
        }
    }

    private func studentAssignmentAccessDocument(
        packet: AssignmentSyncPacket,
        studentIdentifierHash: String,
        teacherUserID: String,
        teacherEmail: String?
    ) -> [String: Any] {
        var document = assignmentDocument(
            packet: packet,
            classroom: Classroom(id: packet.classroomID, name: packet.classroomName),
            teacherUserID: teacherUserID,
            teacherEmail: teacherEmail
        )
        document["studentIdentifierHash"] = studentIdentifierHash
        document["accessDocumentID"] = studentAccessDocumentID(
            forCode: packet.classLessonCode,
            studentIdentifierHash: studentIdentifierHash
        )
        document["allowedStudentIdentifierHashes"] = [studentIdentifierHash]
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
            assignedAt: assignedAt,
            allowedStudentIdentifierHashes: data["allowedStudentIdentifierHashes"] as? [String] ?? []
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

    private func validateStudentIdentifier(_ identifier: String, isAllowedFor packet: AssignmentSyncPacket) throws {
        let normalizedIdentifier = normalizedStudentIdentifier(identifier)
        guard !normalizedIdentifier.isEmpty else {
            throw ClassroomAssignmentStoreError.studentNotFound
        }
        try validateStudentIdentifierHash(
            studentIdentifierHash(forNormalizedIdentifier: normalizedIdentifier),
            isAllowedFor: packet
        )
    }

    private func validateStudentIdentifierHash(_ identifierHash: String, isAllowedFor packet: AssignmentSyncPacket) throws {
        let allowedHashes = Set(packet.allowedStudentIdentifierHashes)
        guard !allowedHashes.isEmpty else { return }
        guard allowedHashes.contains(identifierHash) else {
            throw ClassroomAssignmentStoreError.studentNotFound
        }
    }

    private func allowedStudentIdentifierHashes(for classroom: Classroom) -> [String] {
        let identifiers = classroom.students.flatMap { student in
            [student.officialStudentID, student.alternateStudentID]
        }
        let hashes = identifiers.compactMap { identifier -> String? in
            let normalizedIdentifier = normalizedStudentIdentifier(identifier)
            guard !normalizedIdentifier.isEmpty else { return nil }
            return studentIdentifierHash(forNormalizedIdentifier: normalizedIdentifier)
        }
        return Array(Set(hashes)).sorted()
    }

    private func studentIdentifierHash(forNormalizedIdentifier normalizedIdentifier: String) -> String {
        let digest = SHA256.hash(data: Data(normalizedIdentifier.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func submissionDocument(result: StudentWidgetResult, submission: StudentSubmissionPacket) -> [String: Any] {
        var document: [String: Any] = [
            "id": result.id.uuidString,
            "assignmentID": result.assignmentID.uuidString,
            "classroomID": result.classroomID.uuidString,
            "studentID": result.studentID.uuidString,
            "studentIdentifier": normalizedStudentIdentifier(submission.studentIdentifier),
            "studentIdentifierHash": studentIdentifierHash(
                forNormalizedIdentifier: normalizedStudentIdentifier(submission.studentIdentifier)
            ),
            "studentAccessDocumentID": studentAccessDocumentID(
                forCode: submission.classLessonCode,
                studentIdentifierHash: studentIdentifierHash(
                    forNormalizedIdentifier: normalizedStudentIdentifier(submission.studentIdentifier)
                )
            ),
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

    private func liveProgressDocument(
        _ progress: StudentWidgetLiveProgress,
        classLessonCode: String,
        studentIdentifierHash: String
    ) -> [String: Any] {
        var document: [String: Any] = [
            "assignmentID": progress.assignmentID.uuidString,
            "classroomID": progress.classroomID.uuidString,
            "studentID": progress.studentID.uuidString,
            "studentIdentifier": progress.studentIdentifier,
            "studentIdentifierHash": studentIdentifierHash,
            "studentAccessDocumentID": studentAccessDocumentID(
                forCode: classLessonCode,
                studentIdentifierHash: studentIdentifierHash
            ),
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

    private func teacherInkDocument(_ chunk: TeacherInkStrokeChunk, teacherUserID: String) -> [String: Any] {
        [
            "id": chunk.id.uuidString,
            "lessonCode": ClassroomAssignmentStore.normalizedClassLessonCode(chunk.lessonCode),
            "teacherUserID": teacherUserID,
            "slideID": chunk.slideID.uuidString,
            "strokeID": chunk.strokeID.uuidString,
            "sequence": chunk.sequence,
            "isFinalChunk": chunk.isFinalChunk,
            "colorHex": chunk.colorHex,
            "alpha": chunk.alpha,
            "width": chunk.width,
            "points": chunk.points.map(teacherInkPointDocument),
            "sentAt": Timestamp(date: chunk.sentAt)
        ]
    }

    private func teacherInkPointDocument(_ point: TeacherInkPoint) -> [String: Any] {
        var document: [String: Any] = [
            "x": point.x,
            "y": point.y,
            "timestampOffset": point.timestampOffset
        ]
        if let force = point.force {
            document["force"] = force
        }
        return document
    }

    private func teacherInkChunk(from data: [String: Any], fallbackCode: String) -> TeacherInkStrokeChunk? {
        guard let id = uuidValue(data["id"]),
              let slideID = uuidValue(data["slideID"]),
              let strokeID = uuidValue(data["strokeID"]),
              let colorHex = data["colorHex"] as? String else {
            return nil
        }
        let points = (data["points"] as? [[String: Any]] ?? []).compactMap(teacherInkPoint)
        guard !points.isEmpty else { return nil }
        return TeacherInkStrokeChunk(
            id: id,
            lessonCode: data["lessonCode"] as? String ?? fallbackCode,
            slideID: slideID,
            strokeID: strokeID,
            sequence: intValue(data["sequence"]),
            isFinalChunk: data["isFinalChunk"] as? Bool ?? true,
            colorHex: colorHex,
            alpha: doubleValue(data["alpha"]),
            width: doubleValue(data["width"]),
            points: points,
            sentAt: timestampValue(data["sentAt"])
        )
    }

    private func teacherInkPoint(from data: [String: Any]) -> TeacherInkPoint? {
        guard let x = optionalDoubleValue(data["x"]),
              let y = optionalDoubleValue(data["y"]) else {
            return nil
        }
        return TeacherInkPoint(
            x: x,
            y: y,
            force: optionalDoubleValue(data["force"]),
            timestampOffset: optionalDoubleValue(data["timestampOffset"]) ?? 0
        )
    }

    private func teacherInkDrawingSnapshotDocument(_ snapshot: TeacherInkDrawingSnapshot, teacherUserID: String) -> [String: Any] {
        [
            "id": snapshot.id.uuidString,
            "lessonCode": ClassroomAssignmentStore.normalizedClassLessonCode(snapshot.lessonCode),
            "teacherUserID": teacherUserID,
            "slideID": snapshot.slideID.uuidString,
            "revision": snapshot.revision,
            "drawingDataBase64": snapshot.drawingDataBase64,
            "sentAt": Timestamp(date: snapshot.sentAt)
        ]
    }

    private func teacherInkDrawingSnapshot(from data: [String: Any], fallbackCode: String) -> TeacherInkDrawingSnapshot? {
        guard let id = uuidValue(data["id"]),
              let slideID = uuidValue(data["slideID"]),
              let drawingDataBase64 = data["drawingDataBase64"] as? String else {
            return nil
        }
        return TeacherInkDrawingSnapshot(
            id: id,
            lessonCode: data["lessonCode"] as? String ?? fallbackCode,
            slideID: slideID,
            revision: intValue(data["revision"]),
            drawingDataBase64: drawingDataBase64,
            sentAt: timestampValue(data["sentAt"])
        )
    }

    private func storageBackedTeacherObjectSnapshotDocumentIfNeeded(
        _ snapshot: TeacherObjectSnapshot,
        code: String,
        teacherUserID: String
    ) async throws -> [String: Any] {
        let inlineDocument = teacherObjectSnapshotDocument(snapshot, teacherUserID: teacherUserID)
        guard estimatedFirestorePayloadSize(inlineDocument) > Self.inlineTeacherObjectSnapshotLimit else {
            return inlineDocument
        }

        let storagePath = "classLessonAssets/\(code)/teacherObjects/\(snapshot.slideID.uuidString).json"
        let snapshotData = try JSONEncoder().encode(snapshot)
        let metadata = StorageMetadata()
        metadata.contentType = "application/json"
        metadata.customMetadata = [
            "classLessonCode": code,
            "slideID": snapshot.slideID.uuidString,
            "revision": "\(snapshot.revision)"
        ]
        try await putData(snapshotData, metadata: metadata, at: storage.reference(withPath: storagePath))

        print("[FirebaseSync] stored teacher object snapshot in Storage slide=\(snapshot.slideID) revision=\(snapshot.revision) bytes=\(snapshotData.count)")
        return teacherObjectSnapshotReferenceDocument(
            snapshot,
            teacherUserID: teacherUserID,
            storagePath: storagePath
        )
    }

    private func teacherObjectSnapshotDocument(_ snapshot: TeacherObjectSnapshot, teacherUserID: String) -> [String: Any] {
        [
            "id": snapshot.id.uuidString,
            "lessonCode": ClassroomAssignmentStore.normalizedClassLessonCode(snapshot.lessonCode),
            "teacherUserID": teacherUserID,
            "slideID": snapshot.slideID.uuidString,
            "revision": snapshot.revision,
            "capturedAt": Timestamp(date: snapshot.snapshot.capturedAt),
            "sentAt": Timestamp(date: snapshot.sentAt),
            "sidecarFiles": snapshot.snapshot.sidecarFiles.map(canvasObjectSnapshotFileDocument),
            "imageAssetFiles": snapshot.snapshot.imageAssetFiles.map(canvasObjectSnapshotFileDocument)
        ]
    }

    private func teacherObjectSnapshotReferenceDocument(
        _ snapshot: TeacherObjectSnapshot,
        teacherUserID: String,
        storagePath: String
    ) -> [String: Any] {
        [
            "id": snapshot.id.uuidString,
            "lessonCode": ClassroomAssignmentStore.normalizedClassLessonCode(snapshot.lessonCode),
            "teacherUserID": teacherUserID,
            "slideID": snapshot.slideID.uuidString,
            "revision": snapshot.revision,
            "capturedAt": Timestamp(date: snapshot.snapshot.capturedAt),
            "sentAt": Timestamp(date: snapshot.sentAt),
            "objectSnapshotStoragePath": storagePath
        ]
    }

    private func canvasObjectSnapshotFileDocument(_ file: CanvasObjectSnapshotFile) -> [String: Any] {
        [
            "name": file.name,
            "base64Data": file.base64Data
        ]
    }

    private func teacherObjectSnapshot(from data: [String: Any], fallbackCode: String) async throws -> TeacherObjectSnapshot? {
        if let storagePath = data["objectSnapshotStoragePath"] as? String,
           !storagePath.isEmpty {
            let snapshotData = try await getData(
                from: storage.reference(withPath: storagePath),
                maxSize: Self.teacherObjectSnapshotStorageMaxSize
            )
            return try JSONDecoder().decode(TeacherObjectSnapshot.self, from: snapshotData)
        }

        guard let id = uuidValue(data["id"]),
              let slideID = uuidValue(data["slideID"]) else {
            return nil
        }
        let sidecarFiles = (data["sidecarFiles"] as? [[String: Any]] ?? []).compactMap(canvasObjectSnapshotFile)
        let imageAssetFiles = (data["imageAssetFiles"] as? [[String: Any]] ?? []).compactMap(canvasObjectSnapshotFile)
        let snapshot = CanvasObjectSnapshot(
            slideID: slideID,
            revision: intValue(data["revision"]),
            capturedAt: timestampValue(data["capturedAt"]),
            sidecarFiles: sidecarFiles,
            imageAssetFiles: imageAssetFiles
        )
        return TeacherObjectSnapshot(
            id: id,
            lessonCode: data["lessonCode"] as? String ?? fallbackCode,
            slideID: slideID,
            revision: intValue(data["revision"]),
            snapshot: snapshot,
            sentAt: timestampValue(data["sentAt"])
        )
    }

    private func canvasObjectSnapshotFile(from data: [String: Any]) -> CanvasObjectSnapshotFile? {
        guard let name = data["name"] as? String,
              let base64Data = data["base64Data"] as? String else {
            return nil
        }
        return CanvasObjectSnapshotFile(name: name, base64Data: base64Data)
    }

    private func sortedTeacherObjectSnapshots(_ snapshots: [TeacherObjectSnapshot]) -> [TeacherObjectSnapshot] {
        snapshots.sorted { first, second in
            if first.slideID == second.slideID {
                return first.revision < second.revision
            }
            return first.sentAt < second.sentAt
        }
    }

    private func estimatedFirestorePayloadSize(_ value: Any) -> Int {
        switch value {
        case let string as String:
            return string.utf8.count
        case let array as [Any]:
            return array.reduce(0) { $0 + estimatedFirestorePayloadSize($1) }
        case let dictionary as [String: Any]:
            return dictionary.reduce(0) { total, item in
                total + item.key.utf8.count + estimatedFirestorePayloadSize(item.value)
            }
        default:
            return 32
        }
    }

    private func teacherSlideManifestSnapshotDocument(
        _ snapshot: TeacherSlideManifestSnapshot,
        teacherUserID: String
    ) -> [String: Any] {
        var document: [String: Any] = [
            "id": snapshot.id.uuidString,
            "lessonCode": ClassroomAssignmentStore.normalizedClassLessonCode(snapshot.lessonCode),
            "teacherUserID": teacherUserID,
            "revision": snapshot.revision,
            "slides": snapshot.slides.map(teacherSlideDocument),
            "sentAt": Timestamp(date: snapshot.sentAt)
        ]
        if let activeSlideID = snapshot.activeSlideID {
            document["activeSlideID"] = activeSlideID.uuidString
        }
        return document
    }

    private func teacherSlideDocument(_ slide: TeacherSlideMetadata) -> [String: Any] {
        var document: [String: Any] = [
            "id": slide.id.uuidString,
            "createdAt": Timestamp(date: slide.createdAt)
        ]
        if let viewport = slide.viewport {
            document["viewport"] = teacherSlideViewportDocument(viewport)
        }
        if let background = slide.background {
            document["background"] = teacherSlideBackgroundDocument(background)
        }
        return document
    }

    private func teacherSlideViewportDocument(_ viewport: TeacherSlideViewport) -> [String: Any] {
        var document: [String: Any] = [
            "zoomScale": viewport.zoomScale,
            "contentOffsetX": viewport.contentOffsetX,
            "contentOffsetY": viewport.contentOffsetY
        ]
        if let platform = viewport.platform {
            document["platform"] = platform
        }
        return document
    }

    private func snapshotWithUploadedSlideBackgroundAssets(
        _ snapshot: TeacherSlideManifestSnapshot,
        code: String
    ) async throws -> TeacherSlideManifestSnapshot {
        var slides = snapshot.slides
        for index in slides.indices {
            guard var background = slides[index].background,
                  let assetBase64Data = background.assetBase64Data,
                  let assetData = Data(base64Encoded: assetBase64Data) else {
                continue
            }

            let storagePath = background.assetStoragePath
                ?? "classLessonAssets/\(code)/backgrounds/\(background.assetFileName)"
            let metadata = StorageMetadata()
            metadata.contentType = "application/octet-stream"
            metadata.customMetadata = [
                "classLessonCode": code,
                "assetFileName": background.assetFileName,
                "kind": background.kind
            ]
            try await putData(assetData, metadata: metadata, at: storage.reference(withPath: storagePath))
            background.assetStoragePath = storagePath
            background.assetBase64Data = nil
            slides[index].background = background
        }

        return TeacherSlideManifestSnapshot(
            id: snapshot.id,
            lessonCode: snapshot.lessonCode,
            revision: snapshot.revision,
            slides: slides,
            activeSlideID: snapshot.activeSlideID,
            sentAt: snapshot.sentAt
        )
    }

    private func snapshotWithDownloadedSlideBackgroundAssets(
        _ snapshot: TeacherSlideManifestSnapshot
    ) async throws -> TeacherSlideManifestSnapshot {
        var slides = snapshot.slides
        for index in slides.indices {
            guard var background = slides[index].background,
                  background.assetBase64Data == nil,
                  let storagePath = background.assetStoragePath,
                  !storagePath.isEmpty else {
                continue
            }

            let assetData = try await getData(from: storage.reference(withPath: storagePath), maxSize: 75 * 1024 * 1024)
            background.assetBase64Data = assetData.base64EncodedString()
            slides[index].background = background
        }

        return TeacherSlideManifestSnapshot(
            id: snapshot.id,
            lessonCode: snapshot.lessonCode,
            revision: snapshot.revision,
            slides: slides,
            activeSlideID: snapshot.activeSlideID,
            sentAt: snapshot.sentAt
        )
    }

    private func teacherSlideBackgroundDocument(_ background: TeacherSlideBackground) -> [String: Any] {
        var document: [String: Any] = [
            "kind": background.kind,
            "assetFileName": background.assetFileName,
            "pageIndex": background.pageIndex
        ]
        if let assetBase64Data = background.assetBase64Data {
            document["assetBase64Data"] = assetBase64Data
        }
        if let assetStoragePath = background.assetStoragePath {
            document["assetStoragePath"] = assetStoragePath
        }
        return document
    }

    private func teacherSlideManifestSnapshot(
        from data: [String: Any],
        fallbackCode: String
    ) -> TeacherSlideManifestSnapshot? {
        guard let id = uuidValue(data["id"]) else { return nil }
        let slides = (data["slides"] as? [[String: Any]] ?? []).compactMap(teacherSlide)
        guard !slides.isEmpty else { return nil }
        return TeacherSlideManifestSnapshot(
            id: id,
            lessonCode: data["lessonCode"] as? String ?? fallbackCode,
            revision: intValue(data["revision"]),
            slides: slides,
            activeSlideID: uuidValue(data["activeSlideID"]),
            sentAt: timestampValue(data["sentAt"])
        )
    }

    private func teacherSlide(from data: [String: Any]) -> TeacherSlideMetadata? {
        guard let id = uuidValue(data["id"]) else { return nil }
        return TeacherSlideMetadata(
            id: id,
            createdAt: timestampValue(data["createdAt"]),
            viewport: (data["viewport"] as? [String: Any]).flatMap(teacherSlideViewport),
            background: (data["background"] as? [String: Any]).flatMap(teacherSlideBackground)
        )
    }

    private func teacherSlideViewport(from data: [String: Any]) -> TeacherSlideViewport? {
        guard let zoomScale = optionalDoubleValue(data["zoomScale"]),
              let contentOffsetX = optionalDoubleValue(data["contentOffsetX"]),
              let contentOffsetY = optionalDoubleValue(data["contentOffsetY"]) else {
            return nil
        }
        return TeacherSlideViewport(
            zoomScale: zoomScale,
            contentOffsetX: contentOffsetX,
            contentOffsetY: contentOffsetY,
            platform: data["platform"] as? String
        )
    }

    private func teacherSlideBackground(from data: [String: Any]) -> TeacherSlideBackground? {
        guard let kind = data["kind"] as? String,
              let assetFileName = data["assetFileName"] as? String else {
            return nil
        }
        return TeacherSlideBackground(
            kind: kind,
            assetFileName: assetFileName,
            pageIndex: intValue(data["pageIndex"]),
            assetBase64Data: data["assetBase64Data"] as? String,
            assetStoragePath: data["assetStoragePath"] as? String
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
        optionalDoubleValue(value) ?? 0
    }

    private func optionalDoubleValue(_ value: Any?) -> Double? {
        if let double = value as? Double {
            return double
        }
        if let int = value as? Int {
            return Double(int)
        }
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        return nil
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

    private func shouldWriteRevision(_ revision: Int, to document: DocumentReference) async throws -> Bool {
        do {
            let existingData = try await getData(from: document)
            return intValue(existingData["revision"]) <= revision
        } catch ClassroomAssignmentStoreError.classLessonCodeNotFound {
            return true
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
