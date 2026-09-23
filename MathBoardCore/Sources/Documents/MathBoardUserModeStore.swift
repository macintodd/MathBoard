import Foundation
import Observation

public enum MathBoardUserMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case teacher
    case student

    public var id: Self { self }

    public var title: String {
        switch self {
        case .teacher:
            "Teacher"
        case .student:
            "Student"
        }
    }
}

@MainActor
@Observable
public final class MathBoardUserModeStore {
    public var mode: MathBoardUserMode {
        didSet {
            userDefaults.set(mode.rawValue, forKey: storageKey)
        }
    }

    /// When false the store always starts in student mode and
    /// `switchToTeacherMode()` is a no-op. Set to false for the student build.
    public let allowsTeacherMode: Bool

    private let userDefaults: UserDefaults
    private let storageKey: String

    public init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "MathBoardUserMode",
        allowsTeacherMode: Bool = true
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        self.allowsTeacherMode = allowsTeacherMode
        if allowsTeacherMode {
            let storedMode = userDefaults.string(forKey: storageKey).flatMap(MathBoardUserMode.init(rawValue:))
            self.mode = storedMode ?? .teacher
        } else {
            self.mode = .student
        }
    }

    public func switchToTeacherMode() {
        guard allowsTeacherMode else { return }
        mode = .teacher
    }

    public func switchToStudentMode() {
        mode = .student
    }
}
