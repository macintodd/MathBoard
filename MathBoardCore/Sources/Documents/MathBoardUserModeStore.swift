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

    private let userDefaults: UserDefaults
    private let storageKey: String

    public init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "MathBoardUserMode"
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        let storedMode = userDefaults.string(forKey: storageKey).flatMap(MathBoardUserMode.init(rawValue:))
        self.mode = storedMode ?? .teacher
    }

    public func switchToTeacherMode() {
        mode = .teacher
    }

    public func switchToStudentMode() {
        mode = .student
    }
}
