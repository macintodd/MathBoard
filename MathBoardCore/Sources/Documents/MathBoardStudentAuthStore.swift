import FirebaseAuth
import FirebaseCore
import Foundation

@MainActor
struct MathBoardStudentFirebaseAccessAuthorizer {
    private let authProvider: StudentFirebaseAuthenticating

    init() {
        if FirebaseApp.app() == nil {
            self.init(authProvider: DisabledStudentFirebaseAuthProvider())
        } else {
            self.init(authProvider: FirebaseStudentAuthProvider())
        }
    }

    init(authProvider: StudentFirebaseAuthenticating) {
        self.authProvider = authProvider
    }

    @discardableResult
    func ensureAuthenticatedForOnlineLessonAccess() async throws -> String {
        if let currentUserID = authProvider.currentUserID, !currentUserID.isEmpty {
            return currentUserID
        }
        return try await authProvider.signInAnonymously()
    }
}

@MainActor
protocol StudentFirebaseAuthenticating {
    var currentUserID: String? { get }
    func signInAnonymously() async throws -> String
}

@MainActor
private struct FirebaseStudentAuthProvider: StudentFirebaseAuthenticating {
    var currentUserID: String? {
        Auth.auth().currentUser?.uid
    }

    func signInAnonymously() async throws -> String {
        let result = try await Auth.auth().signInAnonymously()
        return result.user.uid
    }
}

@MainActor
private struct DisabledStudentFirebaseAuthProvider: StudentFirebaseAuthenticating {
    var currentUserID: String? { nil }

    func signInAnonymously() async throws -> String {
        throw MathBoardStudentAuthError.firebaseNotConfigured
    }
}

private enum MathBoardStudentAuthError: LocalizedError {
    case firebaseNotConfigured

    var errorDescription: String? {
        switch self {
        case .firebaseNotConfigured:
            return "Firebase is not configured. Confirm GoogleService-Info.plist is included in the MathBoard app target."
        }
    }
}
