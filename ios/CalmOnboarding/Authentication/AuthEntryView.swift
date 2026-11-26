import SwiftUI

struct AuthEntryView: View {
    let title: String

    @AppStorage("hasAuthenticated") private var hasAuthenticated = false
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var canContinue: Bool {
        email.contains("@") && !password.isEmpty && !isLoading
    }

    var body: some View {
        Form {
            Section {
                TextField("Электронная почта", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                SecureField("Пароль", text: $password)
                    .textContentType(.password)
            }

            Section {
                Button(isLoading ? "Входим..." : "Войти") {
                    signIn()
                }
                .disabled(!canContinue)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Не удалось войти", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Понятно", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func signIn() {
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                let session = try await AuthAPI.login(email: email, password: password)
                guard SessionTokenStore.save(session.token) else {
                    throw AuthAPIError.server("Не удалось сохранить сессию на устройстве")
                }
                hasAuthenticated = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct RegisteredHomeView: View {
    @AppStorage("hasAuthenticated") private var hasAuthenticated = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.green)
                Text("Аккаунт создан")
                    .font(.title.bold())
                Text("Вы вошли в Calm. Основные экраны приложения добавим на следующем этапе.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Выйти") {
                    if let token = SessionTokenStore.load() {
                        Task { await AuthAPI.logout(token: token) }
                    }
                    SessionTokenStore.clear()
                    hasAuthenticated = false
                }
            }
            .padding(30)
        }
    }
}
