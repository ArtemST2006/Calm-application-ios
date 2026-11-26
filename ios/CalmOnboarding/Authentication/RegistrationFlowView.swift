import SwiftUI

private enum RegistrationStage: Equatable {
    case details, password, verification, complete
}

private enum RegistrationFocus: Hashable {
    case firstName, lastName, email, password, confirmation, code
}

private enum RegistrationStyle {
    static let ink = Color("TextPrimary")
    static let muted = Color(red: 146 / 255, green: 143 / 255, blue: 150 / 255)
    static let field = Color(red: 246 / 255, green: 246 / 255, blue: 248 / 255)
    static let accent = Color(red: 183 / 255, green: 175 / 255, blue: 236 / 255)
    static let error = Color(red: 1, green: 56 / 255, blue: 60 / 255)
    static let success = Color(red: 26 / 255, green: 160 / 255, blue: 69 / 255)
    static let background = LinearGradient(
        stops: [
            .init(color: Color(red: 219 / 255, green: 215 / 255, blue: 242 / 255), location: 0),
            .init(color: Color(red: 238 / 255, green: 231 / 255, blue: 248 / 255), location: 0.42),
            .init(color: Color(red: 248 / 255, green: 245 / 255, blue: 251 / 255), location: 1),
        ],
        startPoint: .top,
        endPoint: .bottom
    )
    static let completeBackground = LinearGradient(
        stops: [
            .init(color: Color(red: 174 / 255, green: 164 / 255, blue: 238 / 255), location: 0.125),
            .init(color: Color(red: 240 / 255, green: 228 / 255, blue: 255 / 255), location: 0.809),
        ],
        startPoint: UnitPoint(x: 0.61, y: 0),
        endPoint: UnitPoint(x: 0.39, y: 1)
    )
}

struct RegistrationFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasAuthenticated") private var hasAuthenticated = false
    @FocusState private var focus: RegistrationFocus?
    @State private var stage: RegistrationStage = .details
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var code = ""
    @State private var showPassword = false
    @State private var showConfirmation = false
    @State private var isLoading = false
    @State private var emailError: String?
    @State private var codeError: String?
    @State private var alertMessage: String?
    @State private var debugCode: String?
    @State private var canResend = false

    private let subtitle = "Если вы здесь впервые — введите ваше имя, фамилию и почту"

    private var passwordChecks: [(String, Bool)] {
        [
            ("Минимум 8 символов", password.count >= 8),
            ("Прописные и строчные буквы", password.contains { $0.isUppercase } && password.contains { $0.isLowercase }),
            ("Цифры", password.contains { $0.isNumber }),
            ("Специальные символы", password.contains { !$0.isLetter && !$0.isNumber && !$0.isWhitespace }),
        ]
    }

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / 402, geometry.size.height / 874)
            let left = (geometry.size.width - 402 * scale) / 2
            let top = (geometry.size.height - 874 * scale) / 2

            ZStack(alignment: .topLeading) {
                Group {
                    if stage == .complete {
                        RegistrationStyle.completeBackground
                    } else {
                        RegistrationStyle.background
                    }
                }
                .ignoresSafeArea()

                if stage == .complete {
                    completeContent(scale: scale, left: left, top: top)
                } else {
                    formContent(scale: scale, left: left, top: top)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Готово") { focus = nil }
            }
        }
        .alert("Регистрация", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("Понятно", role: .cancel) { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    @ViewBuilder
    private func formContent(scale s: CGFloat, left: CGFloat, top: CGFloat) -> some View {
        Button {
            focus = nil
            switch stage {
            case .details: dismiss()
            case .password: stage = .details
            case .verification: stage = .password
            case .complete: break
            }
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 20 * s, weight: .medium))
                .foregroundStyle(RegistrationStyle.ink)
                .frame(width: 40 * s, height: 40 * s)
                .background(.white.opacity(0.55), in: Circle())
        }
        .buttonStyle(.plain)
        .position(x: left + 53 * s, y: top + 84 * s)
        .accessibilityLabel("Назад")

        if stage == .verification {
            Text("Регистрация почти\nзавершена")
                .font(.system(size: 32 * s, weight: .medium))
                .lineSpacing(-3 * s)
                .foregroundStyle(RegistrationStyle.ink)
                .frame(width: 342 * s, height: 58 * s, alignment: .topLeading)
                .position(x: left + 201 * s, y: top + 164 * s)

            Text("Отправили вам на почту\nпроверочный код введите его в поле")
                .font(.system(size: 18 * s, weight: .medium))
                .foregroundStyle(RegistrationStyle.muted)
                .frame(width: 342 * s, height: 45 * s, alignment: .topLeading)
                .position(x: left + 201 * s, y: top + 221 * s)

            verificationBoxes(scale: s)
                .position(x: left + 201 * s, y: top + 311 * s)

            if let codeError {
                Text(codeError)
                    .font(.system(size: 14 * s, weight: .medium))
                    .foregroundStyle(RegistrationStyle.error)
                    .frame(width: 342 * s, alignment: .trailing)
                    .position(x: left + 201 * s, y: top + 379 * s)
            }
            if let debugCode {
                Text("Тестовый код: \(debugCode)")
                    .font(.system(size: 14 * s, weight: .medium))
                    .foregroundStyle(RegistrationStyle.muted)
                    .position(x: left + 201 * s, y: top + 414 * s)
            }
            if canResend {
                Button("Отправить код ещё раз") { resendCode() }
                    .font(.system(size: 16 * s, weight: .medium))
                    .foregroundStyle(RegistrationStyle.ink)
                    .position(x: left + 201 * s, y: top + 462 * s)
            }
        } else {
            Text("Создайте аккаунт")
                .font(.system(size: 32 * s, weight: .medium))
                .foregroundStyle(RegistrationStyle.ink)
                .frame(width: 342 * s, height: 40 * s, alignment: .topLeading)
                .position(x: left + 201 * s, y: top + 145 * s)

            Text(subtitle)
                .font(.system(size: 18 * s, weight: .medium))
                .foregroundStyle(RegistrationStyle.muted)
                .frame(width: 342 * s, height: 44 * s, alignment: .topLeading)
                .position(x: left + 201 * s, y: top + 183 * s)

            if stage == .details {
                detailsFields(scale: s, left: left, top: top)
            } else {
                passwordFields(scale: s, left: left, top: top)
            }
        }

        actionButton(width: stage == .verification ? 391 : 342, scale: s) {
            switch stage {
            case .details: advanceDetails()
            case .password: register()
            case .verification: verifyCode()
            case .complete: break
            }
        }
        .position(x: left + 201 * s, y: top + 775 * s)
    }

    @ViewBuilder
    private func detailsFields(scale s: CGFloat, left: CGFloat, top: CGFloat) -> some View {
        field(scale: s) {
            TextField("Имя", text: $firstName)
                .textContentType(.givenName)
                .textInputAutocapitalization(.words)
                .focused($focus, equals: .firstName)
        }
        .position(x: left + 201 * s, y: top + 253 * s)

        field(scale: s) {
            TextField("Фамилия (необязательно)", text: $lastName)
                .textContentType(.familyName)
                .textInputAutocapitalization(.words)
                .focused($focus, equals: .lastName)
        }
        .position(x: left + 201 * s, y: top + 321 * s)

        field(scale: s) {
            TextField("Почта", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focus, equals: .email)
                .onChange(of: email) { _, _ in emailError = nil }
        }
        .position(x: left + 201 * s, y: top + 389 * s)

        if let emailError {
            Text(emailError)
                .font(.system(size: 14 * s, weight: .medium))
                .foregroundStyle(RegistrationStyle.error)
                .frame(width: 342 * s, alignment: .trailing)
                .position(x: left + 201 * s, y: top + 437 * s)
        }
    }

    @ViewBuilder
    private func passwordFields(scale s: CGFloat, left: CGFloat, top: CGFloat) -> some View {
        passwordField("Введите пароль", text: $password, visible: $showPassword, focusField: .password, scale: s)
            .position(x: left + 201 * s, y: top + 253 * s)
        passwordField("Введите пароль еще раз", text: $confirmation, visible: $showConfirmation, focusField: .confirmation, scale: s)
            .position(x: left + 201 * s, y: top + 321 * s)

        VStack(alignment: .leading, spacing: 3 * s) {
            ForEach(passwordChecks.indices, id: \.self) { index in
                Text("•  \(passwordChecks[index].0)")
                    .font(.system(size: 16 * s, weight: .medium))
                    .foregroundStyle(passwordChecks[index].1 ? RegistrationStyle.success : RegistrationStyle.muted)
            }
        }
        .frame(width: 322 * s, alignment: .leading)
        .position(x: left + 201 * s, y: top + 430 * s)
    }

    private func field<Content: View>(scale s: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        content()
            .font(.system(size: 18 * s, weight: .medium))
            .foregroundStyle(RegistrationStyle.ink)
            .tint(RegistrationStyle.accent)
            .padding(.horizontal, 20 * s)
            .frame(width: 342 * s, height: 56 * s)
            .background(RegistrationStyle.field, in: RoundedRectangle(cornerRadius: 8 * s))
    }

    private func passwordField(
        _ prompt: String,
        text: Binding<String>,
        visible: Binding<Bool>,
        focusField: RegistrationFocus,
        scale s: CGFloat
    ) -> some View {
        field(scale: s) {
            HStack(spacing: 8) {
                if visible.wrappedValue {
                    TextField(prompt, text: text)
                        .textContentType(.newPassword)
                        .focused($focus, equals: focusField)
                } else {
                    SecureField(prompt, text: text)
                        .textContentType(.newPassword)
                        .focused($focus, equals: focusField)
                }
                Button { visible.wrappedValue.toggle() } label: {
                    Image(systemName: visible.wrappedValue ? "eye.slash" : "eye")
                        .foregroundStyle(RegistrationStyle.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(visible.wrappedValue ? "Скрыть пароль" : "Показать пароль")
            }
        }
    }

    private func verificationBoxes(scale s: CGFloat) -> some View {
        ZStack {
            HStack(spacing: 7 * s) {
                ForEach(0..<4, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 8 * s)
                        .fill(RegistrationStyle.field)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8 * s)
                                .stroke(codeError == nil ? RegistrationStyle.accent : RegistrationStyle.error, lineWidth: 1)
                        }
                        .overlay {
                            if code.count > index {
                                Circle()
                                    .fill(codeError == nil ? RegistrationStyle.muted : RegistrationStyle.error)
                                    .frame(width: 10 * s, height: 10 * s)
                            }
                        }
                        .frame(width: 80 * s, height: 90 * s)
                }
            }
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focus, equals: .code)
                .opacity(0.02)
                .frame(width: 341 * s, height: 90 * s)
                .onChange(of: code) { _, newValue in
                    code = String(newValue.filter { $0.isNumber }.prefix(4))
                    codeError = nil
                }
        }
        .contentShape(Rectangle())
        .onTapGesture { focus = .code }
    }

    private func completeContent(scale s: CGFloat, left: CGFloat, top: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Image("OnboardingHero3")
                .resizable()
                .frame(width: 424.67 * s, height: 260.67 * s)
                .position(x: left + 201.33 * s, y: top + 427.33 * s)
                .accessibilityHidden(true)
            actionButton(width: 391, scale: s) {
                hasAuthenticated = true
            }
            .position(x: left + 201 * s, y: top + 777 * s)
        }
    }

    private func actionButton(width: CGFloat, scale s: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(isLoading ? "Подождите..." : "Продолжить")
                .font(.system(size: 20 * s, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: width * s, height: (width == 391 ? 62 : 58) * s)
                .background(RegistrationStyle.ink, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    private func advanceDetails() {
        guard !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            focus = .firstName
            alertMessage = "Укажите имя"
            return
        }
        guard email.contains("@"), email.split(separator: "@").last?.contains(".") == true else {
            focus = .email
            emailError = "неверный формат почты"
            return
        }
        emailError = nil
        focus = nil
        stage = .password
    }

    private func register() {
        guard passwordChecks.allSatisfy({ $0.1 }), password == confirmation else {
            alertMessage = password == confirmation ? "Пароль не соответствует требованиям" : "Пароли не совпадают"
            return
        }
        focus = nil
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                let pending = try await AuthAPI.register(firstName: firstName, lastName: lastName, email: email, password: password)
                debugCode = pending.debugCode
                canResend = false
                stage = .verification
                focus = .code
                scheduleResend()
            } catch {
                alertMessage = error.localizedDescription
            }
        }
    }

    private func verifyCode() {
        guard code.count == 4 else {
            codeError = "Введите код"
            return
        }
        focus = nil
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                let session = try await AuthAPI.verify(email: email, code: code)
                guard SessionTokenStore.save(session.token) else {
                    throw AuthAPIError.server("Не удалось сохранить сессию на устройстве")
                }
                stage = .complete
            } catch {
                codeError = "Неверный код"
                alertMessage = error.localizedDescription
            }
        }
    }

    private func resendCode() {
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                let pending = try await AuthAPI.resend(email: email)
                debugCode = pending.debugCode
                code = ""
                codeError = nil
                focus = .code
                canResend = false
                scheduleResend()
            } catch {
                alertMessage = error.localizedDescription
            }
        }
    }

    private func scheduleResend() {
        Task {
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            canResend = true
        }
    }
}
