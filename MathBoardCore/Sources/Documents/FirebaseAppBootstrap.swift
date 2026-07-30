import FirebaseCore
import Foundation

public enum MathBoardFirebaseBootstrap {
    public static func configureIfPossible() {
        guard FirebaseApp.app() == nil else { return }

        guard let optionsPath = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let options = FirebaseOptions(contentsOfFile: optionsPath) else {
            print("[MathBoardFirebaseBootstrap] GoogleService-Info.plist was not found in the app bundle.")
            return
        }

        FirebaseApp.configure(options: options)
    }
}
