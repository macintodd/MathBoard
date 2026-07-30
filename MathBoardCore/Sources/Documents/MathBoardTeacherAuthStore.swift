import FirebaseAuth
import FirebaseCore
import Foundation
import Observation

public enum MathBoardTeacherAuthState: Equatable {
    case signedOut
    case signedIn(userID: String, email: String)

    public var isSignedIn: Bool {
        if case .signedIn = self {
            return true
        }
        return false
    }

    public var email: String? {
        if case let .signedIn(_, email) = self {
            return email
        }
        return nil
    }

    public var userID: String? {
        if case let .signedIn(userID, _) = self {
            return userID
        }
        return nil
    }
}

@MainActor
@Observable
public final class MathBoardTeacherAuthStore {
    public private(set) var state: MathBoardTeacherAuthState = .signedOut
    public private(set) var isWorking = false
    public private(set) var errorMessage: String?

    private let authProvider: TeacherAuthenticating

    public convenience init() {
        if FirebaseApp.app() == nil {
            self.init(authProvider: DisabledTeacherAuthProvider())
        } else {
            self.init(authProvider: FirebaseTeacherAuthProvider())
        }
    }

    init(authProvider: TeacherAuthenticating) {
        self.authProvider = authProvider
        refresh()
    }

    public func refresh() {
        if let currentUserID = authProvider.currentUserID, let currentEmail = authProvider.currentEmail {
            state = .signedIn(userID: currentUserID, email: currentEmail)
        } else {
            state = .signedOut
        }
    }

    public func clearError() {
        errorMessage = nil
    }

    public func signIn(email: String, password: String) async {
        await performAuthAction {
            try await authProvider.signIn(email: email, password: password)
        }
    }

    public func createAccount(email: String, password: String) async {
        await performAuthAction {
            try await authProvider.createAccount(email: email, password: password)
        }
    }

    public func signOut() {
        do {
            try authProvider.signOut()
            refresh()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    private func performAuthAction(_ action: () async throws -> Void) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            try await action()
            refresh()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    private static func message(for error: Error) -> String {
        let nsError = error as NSError
        if let reason = nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String, !reason.isEmpty {
            return reason
        }
        return nsError.localizedDescription
    }
}

@MainActor
protocol TeacherAuthenticating {
    var currentUserID: String? { get }
    var currentEmail: String? { get }
    func signIn(email: String, password: String) async throws
    func createAccount(email: String, password: String) async throws
    func signOut() throws
}

@MainActor
private struct FirebaseTeacherAuthProvider: TeacherAuthenticating {
    var currentUserID: String? {
        Auth.auth().currentUser?.uid
    }

    var currentEmail: String? {
        Auth.auth().currentUser?.email
    }

    func signIn(email: String, password: String) async throws {
        _ = try await Auth.auth().signIn(withEmail: email, password: password)
    }

    func createAccount(email: String, password: String) async throws {
        _ = try await Auth.auth().createUser(withEmail: email, password: password)
    }

    func signOut() throws {
        try Auth.auth().signOut()
    }
}

@MainActor
struct DisabledTeacherAuthProvider: TeacherAuthenticating {
    var currentUserID: String? { nil }
    var currentEmail: String? { nil }

    func signIn(email: String, password: String) async throws {
        throw MathBoardTeacherAuthError.firebaseNotConfigured
    }

    func createAccount(email: String, password: String) async throws {
        throw MathBoardTeacherAuthError.firebaseNotConfigured
    }

    func signOut() throws {}
}

private enum MathBoardTeacherAuthError: LocalizedError {
    case firebaseNotConfigured

    var errorDescription: String? {
        switch self {
        case .firebaseNotConfigured:
            return "Firebase is not configured. Confirm GoogleService-Info.plist is included in the MathBoard app target."
        }
    }
}
