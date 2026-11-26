import SwiftUI

struct AuthEntryView: View {
    let title: String

    @State private var email = ""
    @State private var password = ""
    @State private var showBackendNotice = false

    private var canContinue: Bool {
        email.contains("@") && password.count >= 8
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
                    .textContentType(title == "Войти" ? .password : .newPassword)
            }

            Section {
                Button("Продолжить") {
                    showBackendNotice = true
                }
                .disabled(!canContinue)
            } footer: {
                Text("Проверка аккаунта станет доступна после подключения backend.")
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Backend пока не подключён", isPresented: $showBackendNotice) {
            Button("Понятно", role: .cancel) { }
        } message: {
            Text("Навигация и форма работают. Авторизацию подключим на следующем этапе.")
        }
    }
}
