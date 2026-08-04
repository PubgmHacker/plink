// Plink/Features/Auth2026/PlinkAuthScreen.swift
//
// Единый экран входа. Раньше это были два несвязанных экрана
// (LoginView2026 + RegistrationView2026): переход между ними менял всю
// страницу, бренд-блок и фон перерисовывались, и это читалось как перезагрузка.
//
// Здесь вход и регистрация — два режима ОДНОГО экрана. Шапка, фон и кнопка
// остаются на месте, меняются только поля: пилюля переключателя скользит,
// поля появляются высотой и прозрачностью. Никакой смены страницы.
//
// Что осознанно НЕ сделано:
//
//   • Вход через Apple. В проекте нет ни Sign in with Apple, ни серверного
//     эндпоинта под него (backend-3/src/routes/auth.ts знает только
//     /auth/signup, /auth/signin, /auth/refresh). Кнопка, которая ничего не
//     делает, хуже отсутствующей: она выглядит как самый быстрый путь и
//     упирается в тупик. Чтобы включить — нужен POST /auth/apple, который
//     проверяет identityToken у Apple и выдаёт нашу пару токенов.
//
//   • Поля для кода из шести боксов (OTP). Кода в продукте нет: регистрация
//     не подтверждается ни почтой, ни телефоном. Единственный OTP на сервере —
//     TOTP для входа админа в панель, к обычному входу он не относится.
//
// Поля сведены к минимуму, который реально требует сервер (zod-схема
// signupBody): email, пароль, имя пользователя. Экранное имя убрано с
// регистрации — его спрашивали четвёртым полем, хотя сервер его при
// регистрации даже не принимает, и оно всё равно дописывалось отдельным
// PATCH users/me. Теперь профиль заполняется после входа.

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Режим

enum PlinkAuthMode: String, CaseIterable, Identifiable {
    case signIn
    case signUp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .signIn: return "Вход"
        case .signUp: return "Регистрация"
        }
    }

    /// Подпись главной кнопки. Глагол, а не существительное: кнопка говорит,
    /// что произойдёт.
    var action: String {
        switch self {
        case .signIn: return "Войти"
        case .signUp: return "Создать аккаунт"
        }
    }
}

// MARK: - Экран

struct PlinkAuthScreen: View {
    /// Сообщение от гейта: истёкшая сессия, принудительный выход.
    var sessionMessage: String? = nil
    /// Режим при открытии. Пользователь всегда попадает на «Вход» — параметр
    /// нужен рендеру кадров для аудита, чтобы снять оба состояния экрана.
    var initialMode: PlinkAuthMode = .signIn
    /// Предзаполненные поля — только для рендера кадров: судить о контрасте
    /// активной кнопки по пустой форме нельзя, а нажать в офскрин-рендере
    /// некому.
    var prefilledEmail: String? = nil
    var prefilledPassword: String? = nil
    let onAuthenticated: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var mode: PlinkAuthMode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var username = ""
    @State private var showPassword = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    /// Показывать ли подсказки под полями. Включается после первой попытки
    /// отправки: подсвечивать «неверно» в поле, которое ещё не дописали, —
    /// это ругаться на пользователя за то, что он печатает.
    @State private var didAttempt = false
    @State private var appeared = false

    @FocusState private var focus: Field?
    @Namespace private var modeNS

    private enum Field: Hashable { case email, username, password }

    // MARK: Валидация

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Имя пользователя без ведущей «@»: её печатают по привычке, и ронять
    /// из-за неё регистрацию незачем.
    private var cleanUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
    }

    /// Совпадает с серверной схемой: `^[A-Za-z][A-Za-z0-9_]{4,31}$`.
    private var usernameIsValid: Bool {
        cleanUsername.count >= 5 && cleanUsername.count <= 32 &&
        cleanUsername.first.map { $0.isASCII && $0.isLetter } == true &&
        cleanUsername.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
    }

    private var emailIsValid: Bool {
        // Точка после «@» — минимум, который отсеивает опечатки вида «me@gmail».
        guard let at = trimmedEmail.firstIndex(of: "@") else { return false }
        let domain = trimmedEmail[trimmedEmail.index(after: at)...]
        return !trimmedEmail[trimmedEmail.startIndex..<at].isEmpty
            && domain.contains(".")
            && !domain.hasSuffix(".")
    }

    private var passwordIsValid: Bool { password.count >= 6 }

    private var canSubmit: Bool {
        guard !isLoading, emailIsValid, passwordIsValid else { return false }
        return mode == .signIn || usernameIsValid
    }

    // MARK: Тело

    var body: some View {
        ZStack {
            ProjectorBeamBackground()
                .ignoresSafeArea()

            // Форма прижата к низу, а не центрирована: главная кнопка должна
            // попадать в зону большого пальца. Шапка занимает свободный верх.
            // Прокрутка нужна не для «длинного» экрана, а для клавиатуры и
            // крупного Dynamic Type.
            GeometryReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Spacer(minLength: 24)

                        header

                        Spacer(minLength: 26)

                        modeSwitch
                            .padding(.bottom, 18)

                        card

                        LegalConsentFooter()
                            .padding(.top, 20)
                            // Нижний отступ, а не 8: футер упирался в край
                            // экрана и обрезался под домашним индикатором.
                            .padding(.bottom, 28)
                    }
                    .frame(maxWidth: 430)
                    .padding(.horizontal, 22)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .bottom)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 14)
                }
                // Клавиатура: контент поднимается, свайп по форме её убирает,
                // главная кнопка остаётся в пределах досягаемости.
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            guard !appeared else { return }
            mode = initialMode
            if let prefilledEmail { email = prefilledEmail }
            if let prefilledPassword { password = prefilledPassword }
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.spring(response: 0.62, dampingFraction: 0.88).delay(0.06)) {
                    appeared = true
                }
            }
        }
    }

    // MARK: Шапка

    private var header: some View {
        VStack(spacing: 16) {
            // Знак совпадает с иконкой на домашнем экране. Прежний
            // PlinkFrameMark — серый стеклянный квадрат с play-треугольником —
            // не совпадал ни с иконкой, ни с акцентом приложения.
            PlinkBrandMark(size: 72)

            // Начертание вместо .rounded с разрядкой 6: скруглённый гротеск
            // вразрядку — шрифт по умолчанию у любого шаблона, отсюда и
            // ощущение «сгенерированного» логотипа. Плотный узкий заголовок
            // с отрицательным трекингом читается как вордмарк, а не как
            // системный текст.
            Text("PLINK")
                .font(.system(size: 40, weight: .black, design: .default))
                .tracking(-1.2)
                .foregroundStyle(PlinkTheatre.screen)

            // Обещание продукта, а не описание формы: экран должен говорить
            // «смотрим вместе», а не «заполните поля».
            Text("Смотрите вместе — кадр в кадр")
                .font(.system(size: 15.5, weight: .medium))
                .foregroundStyle(PlinkTheatre.muted)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Plink. Смотрите вместе — кадр в кадр")
    }

    // MARK: Переключатель режима

    /// Скользящая пилюля на стекле — тот же приём, что в сегментах «Друзья»,
    /// чтобы вход не выглядел экраном из другого приложения.
    private var modeSwitch: some View {
        HStack(spacing: 4) {
            ForEach(PlinkAuthMode.allCases) { item in
                let isOn = item == mode
                Button {
                    guard item != mode else { return }
                    HapticManager.selection()
                    // didAttempt сбрасываем: претензии к незаполненному полю
                    // не должны переезжать в другой режим.
                    didAttempt = false
                    errorMessage = nil
                    withAnimation(
                        reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.82)
                    ) {
                        mode = item
                    }
                    focus = nil
                } label: {
                    Text(item.title)
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundStyle(isOn ? PlinkBrand.blueInk : PlinkTheatre.muted)
                        .frame(maxWidth: .infinity)
                        // minHeight, а не фиксированная высота: при крупном
                        // Dynamic Type подпись иначе обрезается.
                        .frame(minHeight: 44)
                        .background {
                            if isOn {
                                Capsule(style: .continuous)
                                    .fill(PlinkTheatre.screen)
                                    .matchedGeometryEffect(id: "authModePill", in: modeNS)
                            }
                        }
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(4)
        // Тинт синим бренда, а не нейтральное стекло: белое с прозрачностью на
        // почти чёрном фоне даёт серый, из-за которого экран и выглядел мутным.
        .plinkGlass(.control, in: Capsule(style: .continuous), tint: PlinkBrand.glassTint)
    }

    // MARK: Форма

    private var card: some View {
        VStack(spacing: 12) {
            if let sessionMessage, mode == .signIn {
                AuthInlineNotice(text: sessionMessage, icon: "clock.arrow.circlepath")
            }
            if let errorMessage {
                AuthInlineNotice(text: errorMessage)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            AuthField(
                title: "Email",
                text: $email,
                icon: .mail,
                keyboard: .emailAddress,
                contentType: .emailAddress,
                submitLabel: .next,
                // Ошибку показываем, только когда поле уже непустое и
                // пользователь ушёл дальше или нажал кнопку.
                problem: showEmailProblem ? "Похоже, в адресе опечатка" : nil,
                onSubmit: { focus = mode == .signUp ? .username : .password }
            )
            .focused($focus, equals: .email)

            // Имя пользователя — только в регистрации. Появляется высотой,
            // а не подменой экрана.
            if mode == .signUp {
                AuthField(
                    title: "Имя пользователя",
                    text: $username,
                    icon: .person,
                    contentType: .username,
                    submitLabel: .next,
                    problem: showUsernameProblem
                        ? "5–32 символа: латиница, цифры и _, первая — буква"
                        : nil,
                    onSubmit: { focus = .password }
                )
                .focused($focus, equals: .username)
                .transition(.asymmetric(
                    insertion: .push(from: .top).combined(with: .opacity),
                    removal: .opacity
                ))
            }

            AuthField(
                title: "Пароль",
                text: $password,
                icon: .lock,
                contentType: mode == .signUp ? .newPassword : .password,
                secure: !showPassword,
                submitLabel: .go,
                problem: showPasswordProblem ? "Не меньше 6 символов" : nil,
                // Глаз в самом поле: иначе пароль не проверить, не стирая его.
                trailing: {
                    Button {
                        showPassword.toggle()
                        HapticManager.selection()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(PlinkTheatre.muted)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showPassword ? "Скрыть пароль" : "Показать пароль")
                },
                onSubmit: { Task { await submit() } }
            )
            .focused($focus, equals: .password)

            submitButton
                .padding(.top, 6)
        }
    }

    private var showEmailProblem: Bool {
        !emailIsValid && !trimmedEmail.isEmpty && (didAttempt || focus != .email)
    }

    private var showUsernameProblem: Bool {
        mode == .signUp && !usernameIsValid && !cleanUsername.isEmpty
            && (didAttempt || focus != .username)
    }

    private var showPasswordProblem: Bool {
        !passwordIsValid && !password.isEmpty && (didAttempt || focus != .password)
    }

    // MARK: Главная кнопка

    /// Ширина кнопки не меняется при загрузке: подпись прячется под спиннер,
    /// а не заменяется им — иначе кнопка «прыгает» в момент нажатия.
    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            ZStack {
                Text(mode.action)
                    .opacity(isLoading ? 0 : 1)
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(PlinkTheatre.velvetDeep)
                }
            }
        }
        .buttonStyle(AuthPrimaryButtonStyle())
        .disabled(!canSubmit)
        .animation(.easeOut(duration: 0.18), value: isLoading)
        .accessibilityLabel(mode.action)
        .accessibilityHint(isLoading ? "Выполняется" : "")
    }

    // MARK: Отправка

    private func submit() async {
        guard !isLoading else { return }
        didAttempt = true

        // Локальная проверка — до сети: незачем ждать ответ сервера, чтобы
        // узнать про опечатку в адресе.
        guard emailIsValid else {
            focus = .email
            fail("Проверьте адрес электронной почты")
            return
        }
        if mode == .signUp, !usernameIsValid {
            focus = .username
            fail("Имя пользователя: 5–32 символа, латиница, цифры и _, первая — буква")
            return
        }
        guard passwordIsValid else {
            focus = .password
            fail("Пароль должен содержать не меньше 6 символов")
            return
        }

        focus = nil
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            switch mode {
            case .signIn:
                _ = try await AuthService.shared.signIn(
                    email: trimmedEmail,
                    password: password
                )
            case .signUp:
                _ = try await AuthService.shared.signUp(
                    email: trimmedEmail,
                    password: password,
                    username: cleanUsername
                )
            }
            HapticManager.notification(.success)
            onAuthenticated()
        } catch {
            HapticManager.errorOccurred()
            // Человеческий русский текст на каждую ошибку — сырой ответ
            // сервера на экран не попадает (см. AuthErrorCopy).
            errorMessage = AuthErrorCopy.message(for: error)
        }
    }

    private func fail(_ message: String) {
        errorMessage = message
        HapticManager.errorOccurred()
    }
}

// MARK: - Поле ввода

/// Поле с инлайн-подсказкой об ошибке и произвольным хвостом (глаз пароля).
///
/// Отдельный тип, а не `CompactAuthField`: тому нужны были подсказка под
/// полем и слот справа, а дописывать их в общий компонент значило бы менять
/// его для всех остальных мест.
private struct AuthField<Trailing: View>: View {
    let title: String
    @Binding var text: String
    var icon: V4Glyph? = nil
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType? = nil
    var secure: Bool = false
    var submitLabel: SubmitLabel = .next
    /// Текст ошибки под полем. nil — поле в порядке.
    var problem: String? = nil
    @ViewBuilder var trailing: Trailing
    var onSubmit: (() -> Void)? = nil

    @FocusState private var focused: Bool

    /// UI-тесты: системный шит «Надёжный пароль?» от .newPassword перехватывает
    /// ввод в симуляторе и делает воронку непроходимой для XCUITest. Флаг
    /// выключает ТОЛЬКО autofill-подсказку, поведение живого приложения то же.
    private var uiTestMode: Bool {
        ProcessInfo.processInfo.arguments.contains("-plink.uitest")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                if let icon {
                    V4GlyphIcon(glyph: icon, size: 16, weight: .regular)
                        .foregroundStyle(focused ? PlinkTheatre.tealDeep : PlinkTheatre.muted)
                        .frame(width: 20)
                }

                Group {
                    if secure {
                        SecureField("", text: $text, prompt: prompt)
                    } else {
                        TextField("", text: $text, prompt: prompt)
                            .keyboardType(keyboard)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
                .textContentType(uiTestMode ? nil : contentType)
                .submitLabel(submitLabel)
                .onSubmit { onSubmit?() }
                .focused($focused)
                .foregroundStyle(PlinkTheatre.screen)
                .tint(PlinkTheatre.tealDeep)

                trailing
            }
            .padding(.leading, 16)
            .padding(.trailing, 6)
            // minHeight: при крупном Dynamic Type текст в 56 pt не влезал.
            .frame(minHeight: 56)
            // Тинт синим бренда: нейтральное стекло на почти чёрном фоне
            // читалось серым, и весь экран выглядел выцветшим.
            .plinkGlass(.control, cornerRadius: 18, tint: PlinkBrand.glassTint)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: focused || problem != nil ? 1.3 : 1)
            )
            .animation(.easeOut(duration: 0.18), value: focused)
            .animation(.easeOut(duration: 0.18), value: problem != nil)

            if let problem {
                Text(problem)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(PlinkTheatre.amber)
                    .padding(.leading, 4)
                    .transition(.opacity)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityValue(problem ?? "")
    }

    private var borderColor: Color {
        if problem != nil { return PlinkTheatre.amber.opacity(0.72) }
        return focused ? PlinkTheatre.tealDeep.opacity(0.78) : PlinkTheatre.hairline
    }

    private var prompt: Text {
        Text(title).foregroundStyle(PlinkTheatre.muted.opacity(0.85))
    }
}

extension AuthField where Trailing == EmptyView {
    init(
        title: String,
        text: Binding<String>,
        icon: V4Glyph? = nil,
        keyboard: UIKeyboardType = .default,
        contentType: UITextContentType? = nil,
        secure: Bool = false,
        submitLabel: SubmitLabel = .next,
        problem: String? = nil,
        onSubmit: (() -> Void)? = nil
    ) {
        self.init(
            title: title,
            text: text,
            icon: icon,
            keyboard: keyboard,
            contentType: contentType,
            secure: secure,
            submitLabel: submitLabel,
            problem: problem,
            trailing: { EmptyView() },
            onSubmit: onSubmit
        )
    }
}
