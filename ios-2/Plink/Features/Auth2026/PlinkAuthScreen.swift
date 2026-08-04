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
                        // Верхний отступ ФИКСИРОВАННЫЙ, а разрыв ниже —
                        // растягивающийся. Два обычных Spacer'а (было 24/26)
                        // делили свободное место поровну и ставили шапку ровно
                        // в центр пустоты — самая заметная черта шаблонного
                        // экрана. Здесь знак стоит в верхней трети, а весь
                        // излишек высоты уходит в разрыв перед формой.
                        Spacer()
                            .frame(height: max(24, proxy.size.height * 0.07))

                        header

                        // Разрыв между блоком бренда и формой НАМЕРЕННО
                        // крупнее любого расстояния внутри формы (минимум 56
                        // против 12–18). Иерархия строится расстоянием: так
                        // видно два блока — «кто мы» и «что сделать», — а не
                        // восемь равноудалённых элементов.
                        //
                        // Потолка у разрыва НЕТ намеренно: с ним (пробовал 96)
                        // весь излишек высоты уходил не в разрыв, а над
                        // шапкой — стек прижимался к низу, и сверху
                        // открывалась пустая треть экрана. Пусть лишнюю высоту
                        // забирает пауза между блоками: она осмысленная.
                        Spacer(minLength: 56)

                        modeSwitch
                            .padding(.bottom, 18)

                        card

                        LegalConsentFooter()
                            .padding(.top, 22)
                            // Нижний отступ, а не 8: футер упирался в край
                            // экрана и обрезался под домашним индикатором.
                            .padding(.bottom, 26)
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
        VStack(spacing: 0) {
            // Знак совпадает с иконкой на домашнем экране — и, после
            // редизайна 04.08.2026, нейтрален к темам (см. PlinkBrandMark).
            PlinkBrandMark(size: 76)
                .padding(.bottom, 20)

            PlinkWordmark(size: 42)

            // Обещание продукта, а не описание формы: экран должен говорить
            // «смотрим вместе», а не «заполните поля».
            //
            // Разрядка 0.3 и тёплый серый: подпись под плотным вордмарком
            // должна быть заметно легче его, иначе два текста спорят.
            Text("Смотрите вместе — кадр в кадр")
                .font(.system(size: 15, weight: .medium))
                .tracking(0.3)
                .foregroundStyle(PlinkTheatre.muted)
                .multilineTextAlignment(.center)
                .padding(.top, 14)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Plink. Смотрите вместе — кадр в кадр")
    }

    // MARK: Переключатель режима

    /// Скользящая пилюля — тот же приём, что в сегментах «Друзья», чтобы вход
    /// не выглядел экраном из другого приложения.
    ///
    /// Аудит 04.08.2026: выбранная половина была ЗАЛИТА БЕЛЫМ, а дорожка —
    /// синей. Белая плашка — самый сильный контраст на тёмном экране, и она
    /// стояла на переключателе: экран кричал «Вход» вместо «Войти», спорил с
    /// главной кнопкой (тоже белой) и делал вид, будто «Вход» и «Регистрация» —
    /// главное решение экрана. Переключатель — навигация, а не действие:
    /// теперь выбранная половина лишь чуть подсвечена, а текст на ней
    /// становится белым. Единственная белая плашка на экране — кнопка.
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
                        .font(.system(size: 14.5, weight: isOn ? .bold : .semibold))
                        .foregroundStyle(isOn ? PlinkTheatre.screen : PlinkTheatre.muted)
                        .frame(maxWidth: .infinity)
                        // minHeight, а не фиксированная высота: при крупном
                        // Dynamic Type подпись иначе обрезается.
                        .frame(minHeight: 42)
                        .background {
                            if isOn {
                                Capsule(style: .continuous)
                                    .fill(PlinkTheatre.surfaceLift)
                                    .overlay {
                                        Capsule(style: .continuous)
                                            .strokeBorder(PlinkTheatre.specular, lineWidth: 0.8)
                                            .mask {
                                                // Блик только по верхней кромке.
                                                LinearGradient(
                                                    colors: [.white, .clear],
                                                    startPoint: .top,
                                                    endPoint: .bottom
                                                )
                                            }
                                    }
                                    .matchedGeometryEffect(id: "authModePill", in: modeNS)
                            }
                        }
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                // Идентификатор для UI-теста воронки: тот ищет
                // «auth.openRegistration», чтобы переключиться на регистрацию.
                // В приложении такого идентификатора не было ни на одном
                // элементе (проверено на чистом main), поэтому тест не мог
                // переключить режим и падал на «Поле имени пользователя не
                // появилось» — то есть воронка не проверялась вообще.
                .accessibilityIdentifier(
                    item == .signUp ? "auth.openRegistration" : "auth.openSignIn"
                )
                .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(4)
        // Дорожка — утопленная, без тинта: тинт темой (был синий) объявлял
        // цветом бренда одну из тем продукта.
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.34))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(PlinkTheatre.hairline, lineWidth: 1)
        )
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
                        .tint(Color(hex: 0x101013))
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
                        .foregroundStyle(focused ? PlinkTheatre.warm : PlinkTheatre.muted)
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
                .tint(PlinkTheatre.warm)

                trailing
            }
            .padding(.leading, 16)
            .padding(.trailing, 6)
            // minHeight: при крупном Dynamic Type текст в 56 pt не влезал.
            .frame(minHeight: 56)
            // ПОЛЯ — ПЛОТНЫЕ, НЕ СТЕКЛЯННЫЕ (аудит 04.08.2026).
            //
            // Здесь было стекло с синим тинтом темы. Убрано по двум причинам.
            //
            // Правило: стекло у Apple живёт на слое НАВИГАЦИИ И УПРАВЛЕНИЯ
            // (панели, тулбары, кнопки), а не на слое контента. Поле ввода —
            // контент: человек в него пишет и должен видеть, что написал.
            // Собственные экраны Apple (Настройки, App Store) дают полям
            // плотную заливку, а не размытие. Сам Apple в 26.1 был вынужден
            // добавить «Tinted»-режим, потому что стекло поверх насыщенного
            // фона мешало читать.
            //
            // И практическая: за формой теперь живая мозаика кадров. Стекло
            // пропускало бы её внутрь поля, и контраст текста зависел бы от
            // того, какой тайл под полем проплывает. Плотная подложка
            // гарантирует 4.5:1 при любом кадре фона.
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(focused ? PlinkTheatre.surfaceLift : PlinkTheatre.surface)
            )
            .overlay {
                // Блик по верхней кромке — «поверхность поймала свет».
                // Именно этой детали не хватало, чтобы плотная плашка не
                // читалась плоским прямоугольником.
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(PlinkTheatre.specular, lineWidth: 0.8)
                    .mask {
                        LinearGradient(
                            colors: [.white, .clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: focused || problem != nil ? 1.4 : 1)
            )
            // Фокус подсвечен тёплым — акцентом шелла, а не темы.
            .shadow(
                color: PlinkTheatre.warm.opacity(focused ? 0.14 : 0),
                radius: 14
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
        return focused ? PlinkTheatre.warm.opacity(0.55) : PlinkTheatre.hairline
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
