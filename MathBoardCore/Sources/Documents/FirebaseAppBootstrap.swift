import FirebaseCore
import FirebaseFirestore
import Foundation

public enum MathBoardFirebaseBootstrap {
    private static let oversizedTeacherObjectQueueResetKey = "MathBoardClearedFirestoreOversizedTeacherObjectQueue20260804"

    public static func configureIfPossible() {
        guard FirebaseApp.app() == nil else { return }

        guard let optionsPath = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let options = FirebaseOptions(contentsOfFile: optionsPath) else {
            print("[MathBoardFirebaseBootstrap] GoogleService-Info.plist was not found in the app bundle.")
            return
        }

        FirebaseApp.configure(options: options)
        clearOversizedTeacherObjectPendingWritesIfNeeded()
    }

    private static func clearOversizedTeacherObjectPendingWritesIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: oversizedTeacherObjectQueueResetKey) else { return }

        Firestore.firestore().clearPersistence { error in
            if let error {
                print("[MathBoardFirebaseBootstrap] Firestore pending-write reset failed: \(error)")
                return
            }
            UserDefaults.standard.set(true, forKey: oversizedTeacherObjectQueueResetKey)
            print("[MathBoardFirebaseBootstrap] Cleared Firestore pending writes/cache after oversized teacher-object snapshot fix.")
        }
    }
}
