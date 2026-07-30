import SwiftUI

struct TeacherAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MathBoardTeacherAuthStore.self) private var authStore
    @State private var email = ""
    @State private var password = ""
    @State private var mode: TeacherAccountMode = .signIn

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        password.count >= 6 &&
        !authStore.isWorking
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                header

                if let signedInEmail = authStore.state.email {
                    signedInContent(email: signedInEmail)
                } else {
                    signInForm
                }

                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: 520, minHeight: 420, alignment: .topLeading)
            .background(AppColors.canvasBackground.ignoresSafeArea())
            .navigationTitle("Teacher Account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Account Error", isPresented: errorAlertBinding) {
                Button("OK", role: .cancel) {
                    authStore.clearError()
                }
            } message: {
                Text(authStore.errorMessage ?? "Something went wrong.")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Teacher Sign In")
                .font(.largeTitle.weight(.bold))
            Text("Sign in with the teacher email account that will own rosters, assigned lessons, and reports.")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private var signInForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Mode", selection: $mode) {
                ForEach(TeacherAccountMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                #if os(iOS)
                .keyboardType(.emailAddress)
                #endif
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("teacherAccount.emailField")

            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("teacherAccount.passwordField")

            Button {
                submit()
            } label: {
                if authStore.isWorking {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label(mode.buttonTitle, systemImage: mode.systemImage)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSubmit)
            .accessibilityIdentifier("teacherAccount.submitButton")

            Text("Passwords must be at least 6 characters for Firebase email sign-in.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func signedInContent(email: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(email, systemImage: "checkmark.seal.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.green)

            Button(role: .destructive) {
                authStore.signOut()
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("teacherAccount.signOutButton")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { authStore.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    authStore.clearError()
                }
            }
        )
    }

    private func submit() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = password
        Task {
            switch mode {
            case .signIn:
                await authStore.signIn(email: trimmedEmail, password: password)
            case .createAccount:
                await authStore.createAccount(email: trimmedEmail, password: password)
            }
        }
    }
}

private enum TeacherAccountMode: String, CaseIterable, Identifiable {
    case signIn
    case createAccount

    var id: Self { self }

    var title: String {
        switch self {
        case .signIn:
            return "Sign In"
        case .createAccount:
            return "Create"
        }
    }

    var buttonTitle: String {
        switch self {
        case .signIn:
            return "Sign In"
        case .createAccount:
            return "Create Account"
        }
    }

    var systemImage: String {
        switch self {
        case .signIn:
            return "person.crop.circle.badge.checkmark"
        case .createAccount:
            return "person.badge.plus"
        }
    }
}

#Preview {
    TeacherAccountView()
        .environment(MathBoardTeacherAuthStore(authProvider: DisabledTeacherAuthProvider()))
}
