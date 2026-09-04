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
// Методы входа — ОДИН СТОЛБИК, не вкладки (правка 04.09.2026).
//
// Было два сегментированных переключателя друг над другом: «Почта | Apple»
// и под ним «Вход | Регистрация». Человек видел два одинаковых элемента
// управления и не мог сказать, какой из них главный; Apple при этом жил
// вкладкой с яблочным глифом 15 pt.
//
// Так нельзя по двум причинам. Первая — продуктовая: почта и Apple не
// «режимы экрана», а два действия, и оба должны быть видны сразу, иначе
// половина людей не узнаёт, что вход через Apple вообще есть. Вторая —
// формальная: HIG «Sign in with Apple» требует кнопку официального вида,
// не менее заметную, чем остальные способы входа; вкладка этому не
// соответствует и её снимают на ревью.
//
// Теперь на экране: форма почты → разделитель «или» → полноширинная кнопка
// Apple. Единственный переключатель — «Вход | Регистрация».
//   • Почта — единственный полностью рабочий путь (signin/signup).
//   • Apple — кнопка + POST /auth/apple; нужен entitlement Apple Developer.
//
// Что осознанно НЕ сделано:
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
        case .signIn: return L10n.text(.authModeSignIn)
        case .signUp: return L10n.text(.authModeSignUp)
        }
    }

    /// Подпись главной кнопки. Глагол, а не существительное: кнопка говорит,
    /// что произойдёт.
    var action: String {
        switch self {
        case .signIn: return L10n.text(.authActionSignIn)
        case .signUp: return L10n.text(.loginCreateAccount)
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
    /// Показать пароль открытым текстом. Только для рендера кадров:
    /// SecureField офскрином не рисует точки (нет первого респондера), и на
    /// снимке заполненное поле выглядело пустым — судить по такому кадру
    /// нельзя. В приложении это делает кнопка-глаз.
    var revealPassword: Bool = false
    var prefilledUsername: String? = nil
    let onAuthenticated: () -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    /// Рендер кадров аудита: проявление экрана выключено, чтобы снимок не
    /// поймал середину анимации (см. PlinkFreezeAnimationsKey).
    @Environment(\.plinkFreezeAnimations) private var freezeAnimations

    private var reduceMotion: Bool { systemReduceMotion || freezeAnimations }

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
    @State private var showForgotPassword = false

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

    // MARK: Тело

    var body: some View {
        ZStack {
            PlinkShellBackground()
                .ignoresSafeArea()

            // Форма прижата к низу, а не центрирована: главная кнопка должна
            // попадать в зону большого пальца. Шапка занимает свободный верх.
            // Прокрутка нужна не для «длинного» экрана, а для клавиатуры и
            // крупного Dynamic Type.
            GeometryReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // РАСПРЕДЕЛЕНИЕ ИЗЛИШКА ВЫСОТЫ (правка 04.09.2026).
                        //
                        // Было: верхний отступ фиксированный, разрыв перед
                        // формой без потолка — весь излишек уходил в него. На
                        // 6,3" это дало 160 pt пустоты между теглайном и
                        // первым элементом управления (замер по кадру
                        // 10-auth-signin): пятая часть экрана — дыра, и она
                        // читалась «экран не догрузился».
                        //
                        // Теперь наоборот: разрыв перед формой ОГРАНИЧЕН 68 pt
                        // (всё ещё вчетверо больше расстояний внутри формы, то
                        // есть иерархия блоков сохраняется), а излишек забирает
                        // ВЕРХНИЙ отступ — он растягивающийся с полом 20 pt.
                        // Лок-ап опускается к центру верхней половины, форма
                        // остаётся у большого пальца, дыры между ними нет.
                        Spacer()
                            .frame(minHeight: max(20, proxy.size.height * 0.045))

                        header

                        // Разрыв между блоком бренда и формой НАМЕРЕННО
                        // крупнее любого расстояния внутри формы (минимум 56
                        // против 12–18). Иерархия строится расстоянием: так
                        // видно два блока — «кто мы» и «что сделать», — а не
                        // восемь равноудалённых элементов.
                        //
                        // Минимум снижен 56 → 30: форма выросла на кнопку
                        // Apple и разделитель (замер: +91 pt).
                        Spacer(minLength: 30)
                            .frame(maxHeight: 68)

                        modeSwitch
                            .padding(.bottom, 16)

                        card

                        LegalConsentFooter()
                            .padding(.top, 18)
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
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordSheet(prefilledEmail: trimmedEmail)
                .preferredColorScheme(.dark)
        }
        .onAppear {
            guard !appeared else { return }
            mode = initialMode
            if let prefilledEmail { email = prefilledEmail }
            if let prefilledPassword { password = prefilledPassword }
            if let prefilledUsername { username = prefilledUsername }
            if revealPassword { showPassword = true }
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
            // Гнездо: тот же приём, что на сплэше. Здесь знак стоит ровно в
            // ярчайшей точке сияния шелла (glowCenter y 0,28) и без черноты
            // под собой давал по хвосту 1,22:1 — знак растворялся в фиолетовом.
            // Радиус 230 — это 300 сплэша, пересчитанные на знак 76 вместо 96.
            PlinkBrandMark(size: 76)
                .plinkLockupNest(radius: 230)
                .padding(.bottom, 20)

            PlinkWordmark(size: 42)

            // Теглайн эталонного лок-апа (brand/source/reference.png): шапка
            // входа — тот же знак, вордмарк и подпись, что на иконке и сплэше.
            PlinkTagline(size: 12)
                .padding(.top, 14)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.text(.authHeroA11y))
    }

    // MARK: Переключатель режима

    /// Скользящая пилюля — тот же приём, что в сегментах «Друзья», чтобы вход
    /// не выглядел экраном из другого приложения.
    ///
    /// Выбранная половина была ЗАЛИТА БЕЛЫМ, а дорожка —
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
                        .authFont(14.5, weight: isOn ? .bold : .semibold)
                        .foregroundStyle(isOn ? PlinkShell.text : PlinkShell.muted)
                        .frame(maxWidth: .infinity)
                        // minHeight, а не фиксированная высота: при крупном
                        // Dynamic Type подпись иначе обрезается.
                        .frame(minHeight: 42)
                        .background {
                            if isOn {
                                Capsule(style: .continuous)
                                    .fill(PlinkShell.surfaceLift)
                                    .overlay {
                                        Capsule(style: .continuous)
                                            .strokeBorder(PlinkShell.specular, lineWidth: 0.8)
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
                .strokeBorder(PlinkShell.hairline, lineWidth: 1)
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

            emailFields

            orDivider
                .padding(.top, 6)

            AppleSignInButton(
                title: mode == .signUp
                    ? L10n.text(.authAppleSignUpButton)
                    : L10n.text(.authAppleButton),
                onSuccess: onAuthenticated,
                onError: { errorMessage = $0 }
            )
        }
        .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.86), value: mode)
    }

    /// Разделитель «или» — полоса с подписью, а не сегменты. Почта и Apple
    /// стоят друг под другом: это два действия, а не выбор из двух вкладок.
    private var orDivider: some View {
        HStack(spacing: 12) {
            dividerLine
            Text(L10n.text(.authOrDivider))
                .authFont(12, weight: .semibold)
                .foregroundStyle(PlinkShell.muted)
                .fixedSize()
            dividerLine
        }
        .accessibilityHidden(true)
    }

    private var dividerLine: some View {
        Rectangle()
            .fill(PlinkShell.hairline)
            .frame(height: 1)
    }

    private var emailFields: some View {
        VStack(spacing: 12) {
            AuthField(
                title: "Email",
                text: $email,
                icon: .mail,
                keyboard: .emailAddress,
                contentType: .emailAddress,
                submitLabel: .next,
                problem: showEmailProblem ? L10n.text(.authEmailTypo) : nil,
                onSubmit: { focus = mode == .signUp ? .username : .password }
            )
            .focused($focus, equals: .email)

            if mode == .signUp {
                AuthField(
                    title: L10n.text(.authUsernameTitle),
                    text: $username,
                    icon: .person,
                    contentType: .username,
                    submitLabel: .next,
                    problem: showUsernameProblem
                        ? L10n.text(.authUsernameHint)
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
                title: L10n.text(.authPasswordTitle),
                text: $password,
                icon: .lock,
                contentType: mode == .signUp ? .newPassword : .password,
                secure: !showPassword,
                submitLabel: .go,
                // На регистрации требование показано СРАЗУ и живёт правилом,
                // а не ошибкой: человек видит «не меньше 6 символов» до того,
                // как ошибётся, и галочка подтверждает, что он уже прошёл.
                // На входе правило не нужно — пароль там уже существует.
                problem: mode == .signIn && showPasswordProblem
                    ? L10n.text(.authPasswordMin)
                    : nil,
                rule: mode == .signUp ? L10n.text(.authPasswordMin) : nil,
                ruleMet: passwordIsValid,
                trailing: {
                    Button {
                        showPassword.toggle()
                        HapticManager.selection()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .authFont(15, weight: .regular)
                            .foregroundStyle(PlinkShell.muted)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showPassword ? L10n.text(.authHidePassword) : L10n.text(.authShowPassword))
                },
                onSubmit: { Task { await submit() } }
            )
            .focused($focus, equals: .password)

            if mode == .signIn {
                Button {
                    HapticManager.selection()
                    showForgotPassword = true
                } label: {
                    // ССЫЛКА ПРИГЛУШЕНА (правка 04.09.2026).
                    //
                    // Была PlinkShell.accentSoft — и на пустом экране это был
                    // ЕДИНСТВЕННЫЙ цветной элемент: восстановление пароля
                    // светилось ярче, чем «Войти». Иерархия наоборот.
                    // Восстановление — путь для меньшинства, ему хватает
                    // приглушённого текста рядом с полем пароля.
                    Text(L10n.text(.authForgotPassword))
                        .authFont(13, weight: .semibold)
                        .foregroundStyle(PlinkShell.muted)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text(.authForgotPasswordA11y))
            }

            submitButton
                .padding(.top, mode == .signIn ? 0 : 6)
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
    ///
    /// КНОПКА НЕ ГАСНЕТ НА ПУСТОЙ ФОРМЕ (правка 04.09.2026).
    ///
    /// Было `.disabled(!canSubmit)`, а выключенный вид в AuthPrimaryButtonStyle —
    /// это PlinkShell.surface с волосяной рамкой и радиусом 16, то есть
    /// ровно то же, что у поля ввода. На первом кадре экрана (форма пуста)
    /// «Войти» выглядела третьим полем, и у экрана не было главного действия
    /// вообще: единственным цветным элементом оставалось «Забыли пароль?».
    ///
    /// Теперь кнопка всегда залита градиентом и всегда нажимается, а
    /// проверка живёт в submit(): она ставит курсор в проблемное поле и
    /// говорит, что именно не так. Это и есть поведение Google, Spotify,
    /// Netflix и Duolingo — «нажми и узнай», а не «угадай, почему серая».
    /// Выключение осталось только на время запроса.
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
                        .tint(PlinkShell.text)
                }
            }
        }
        .buttonStyle(AuthPrimaryButtonStyle())
        .disabled(isLoading)
        .animation(.easeOut(duration: 0.18), value: isLoading)
        .accessibilityLabel(mode.action)
        .accessibilityHint(isLoading ? L10n.text(.authInProgress) : "")
    }

    // MARK: Отправка

    private func submit() async {
        guard !isLoading else { return }
        didAttempt = true

        // Локальная проверка — до сети: незачем ждать ответ сервера, чтобы
        // узнать про опечатку в адресе.
        guard emailIsValid else {
            focus = .email
            fail(L10n.text(.authErrEmail))
            return
        }
        if mode == .signUp, !usernameIsValid {
            focus = .username
            fail(L10n.text(.authErrUsername))
            return
        }
        guard passwordIsValid else {
            focus = .password
            fail(L10n.text(.authErrPassword))
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
    /// Живое правило под полем («Не меньше 6 символов»). Показывается вместо
    /// ошибки: требование, которое видно ДО первой попытки, снимает саму
    /// ошибку — человек не угадывает правила, он их читает.
    var rule: String? = nil
    var ruleMet: Bool = false
    @ViewBuilder var trailing: Trailing
    var onSubmit: (() -> Void)? = nil

    @FocusState private var focused: Bool

    /// Раздвижка ярлыка и значения при поднятом ярлыке — ScaledMetric, а не
    /// константы. При крупном Dynamic Type кегли растут (11 → ~15, 15 → ~20),
    /// и фиксированные −12/+9 склеили бы ярлык со значением в одну кашу.
    /// Иконка по той же причине: рядом с 20-пунктовым текстом 16 pt глиф
    /// читается как случайный мусор.
    @ScaledMetric(relativeTo: .body) private var labelLift: CGFloat = 12
    @ScaledMetric(relativeTo: .body) private var valueDrop: CGFloat = 9
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 16

    /// Ярлык поднят: поле в фокусе или уже с текстом. Пока поле пустое и не в
    /// фокусе — ярлык стоит на месте текста и работает подсказкой.
    private var labelFloats: Bool { focused || !text.isEmpty }

    /// UI-тесты: системный шит «Надёжный пароль?» от .newPassword перехватывает
    /// ввод в симуляторе и делает воронку непроходимой для XCUITest. Флаг
    /// выключает ТОЛЬКО autofill-подсказку, поведение живого приложения то же.
    private var uiTestMode: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-plink.uitest")
        #else
        false
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                if let icon {
                    V4GlyphIcon(glyph: icon, size: iconSize, weight: .regular)
                        .foregroundStyle(focused ? PlinkShell.accentSoft : PlinkShell.muted)
                        .frame(width: iconSize + 4)
                }

                // ПЛАВАЮЩИЙ ЯРЛЫК, А НЕ PLACEHOLDER-AS-LABEL.
                //
                // Было: название поля жило в prompt. Как только человек
                // начинал печатать, оно исчезало — и заполненная форма
                // превращалась в четыре безымянные плашки. На проверке перед
                // отправкой (а её делают все) приходилось вспоминать, что где.
                // Это давно известный дефект: подсказка-вместо-ярлыка не
                // выдерживает ни правки, ни автозаполнения.
                //
                // Ярлык теперь не исчезает: он уезжает вверх и мельчает
                // (15 → 11 pt, y −labelLift), текст опускается под него
                // (y +valueDrop); обе величины масштабируются Dynamic Type.
                // Так делают Material 3, Stripe и Revolut.
                ZStack(alignment: .leading) {
                    Text(title)
                        .authFont(
                            labelFloats ? 11 : 15,
                            weight: labelFloats ? .semibold : .regular
                        )
                        .foregroundStyle(labelColor)
                        .lineLimit(1)
                        .offset(y: labelFloats ? -labelLift : 0)
                        .allowsHitTesting(false)

                    Group {
                        if secure {
                            SecureField("", text: $text)
                        } else {
                            TextField("", text: $text)
                                .keyboardType(keyboard)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    }
                    .textContentType(uiTestMode ? nil : contentType)
                    .submitLabel(submitLabel)
                    .onSubmit { onSubmit?() }
                    .focused($focused)
                    .foregroundStyle(PlinkShell.text)
                    .tint(PlinkShell.accentSoft)
                    .authFont(15)
                    .offset(y: labelFloats ? valueDrop : 0)
                }
                .animation(.easeOut(duration: 0.16), value: labelFloats)
                // Тап по плашке ставит курсор: сама зона ярлыка иначе была
                // мёртвой, и по ней приходилось попадать в тонкую строку.
                // Жест висит на ZStack, а не на всём ряду, — иначе он спорил
                // бы с кнопкой глаза справа.
                .contentShape(Rectangle())
                .onTapGesture { focused = true }

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
            // И практическая: за формой дышит фиолетовое сияние шелла. Стекло
            // пропускало бы его внутрь поля, и контраст текста зависел бы от
            // фазы сияния под полем. Плотная подложка гарантирует 4.5:1 в
            // любой момент.
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(focused ? PlinkShell.surfaceLift : PlinkShell.surface)
            )
            .overlay {
                // Блик по верхней кромке — «поверхность поймала свет».
                // Именно этой детали не хватало, чтобы плотная плашка не
                // читалась плоским прямоугольником.
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(PlinkShell.specular, lineWidth: 0.8)
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
                color: PlinkShell.accentSoft.opacity(focused ? 0.14 : 0),
                radius: 14
            )
            .animation(.easeOut(duration: 0.18), value: focused)
            .animation(.easeOut(duration: 0.18), value: problem != nil)

            if let problem {
                Text(problem)
                    .authFont(12, weight: .medium)
                    .foregroundStyle(PlinkShell.warning)
                    .padding(.leading, 4)
                    .transition(.opacity)
            } else if let rule {
                HStack(spacing: 5) {
                    Image(systemName: ruleMet ? "checkmark.circle.fill" : "circle")
                        .authFont(11, weight: .semibold)
                    Text(rule)
                        .authFont(12, weight: .medium)
                }
                .foregroundStyle(ruleMet ? PlinkShell.ok : PlinkShell.muted)
                .padding(.leading, 4)
                .animation(.easeOut(duration: 0.16), value: ruleMet)
                .transition(.opacity)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityValue(problem ?? (rule.map { ruleMet ? "\($0) — выполнено" : $0 } ?? ""))
    }

    private var borderColor: Color {
        if problem != nil { return PlinkShell.warning.opacity(0.72) }
        return focused ? PlinkShell.accentSoft.opacity(0.55) : PlinkShell.hairline
    }

    /// Поднятый ярлык в фокусе — акцентом: он теперь несёт роль «активное
    /// поле», которую раньше приходилось угадывать по рамке.
    private var labelColor: Color {
        if problem != nil { return PlinkShell.warning }
        if labelFloats { return focused ? PlinkShell.accentSoft : PlinkShell.muted }
        return PlinkShell.muted.opacity(0.85)
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
        rule: String? = nil,
        ruleMet: Bool = false,
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
            rule: rule,
            ruleMet: ruleMet,
            trailing: { EmptyView() },
            onSubmit: onSubmit
        )
    }
}

// MARK: - Сброс пароля

private struct ForgotPasswordSheet: View {
    var prefilledEmail: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Step { case email, code }

    @State private var step: Step = .email
    @State private var email = ""
    @State private var code = ""
    @State private var newPassword = ""
    @State private var showPassword = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var infoMessage: String?
    @FocusState private var focus: Field?

    private enum Field: Hashable { case email, code, password }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var emailIsValid: Bool {
        guard let at = trimmedEmail.firstIndex(of: "@") else { return false }
        let domain = trimmedEmail[trimmedEmail.index(after: at)...]
        return !trimmedEmail[trimmedEmail.startIndex..<at].isEmpty
            && domain.contains(".")
            && !domain.hasSuffix(".")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PlinkShellBackground().ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(step == .email
                             ? L10n.text(.resetIntroEmail)
                             : L10n.text(.resetIntroCode))
                            .authFont(14, weight: .medium)
                            .foregroundStyle(PlinkShell.muted)
                            .padding(.top, 8)

                        if let errorMessage {
                            AuthInlineNotice(text: errorMessage)
                        }
                        if let infoMessage {
                            AuthInlineNotice(text: infoMessage, icon: "envelope.fill")
                        }

                        if step == .email {
                            AuthField(
                                title: "Email",
                                text: $email,
                                icon: .mail,
                                keyboard: .emailAddress,
                                contentType: .emailAddress,
                                submitLabel: .go,
                                onSubmit: { Task { await sendCode() } }
                            )
                            .focused($focus, equals: .email)
                        } else {
                            AuthField(
                                title: L10n.text(.resetCodeTitle),
                                text: $code,
                                icon: .lock,
                                keyboard: .numberPad,
                                contentType: .oneTimeCode,
                                submitLabel: .next,
                                onSubmit: { focus = .password }
                            )
                            .focused($focus, equals: .code)
                            .onChange(of: code) { _, new in
                                code = String(new.filter(\.isNumber).prefix(6))
                            }

                            AuthField(
                                title: L10n.text(.resetNewPassword),
                                text: $newPassword,
                                icon: .lock,
                                contentType: .newPassword,
                                secure: !showPassword,
                                submitLabel: .go,
                                problem: newPassword.isEmpty || newPassword.count >= 6
                                    ? nil : L10n.text(.authPasswordMin),
                                trailing: {
                                    Button {
                                        showPassword.toggle()
                                    } label: {
                                        Image(systemName: showPassword ? "eye.slash" : "eye")
                                            .authFont(15, weight: .regular)
                                            .foregroundStyle(PlinkShell.muted)
                                            .frame(width: 44, height: 44)
                                    }
                                    .buttonStyle(.plain)
                                },
                                onSubmit: { Task { await confirm() } }
                            )
                            .focused($focus, equals: .password)
                        }

                        Button {
                            Task {
                                if step == .email {
                                    await sendCode()
                                } else {
                                    await confirm()
                                }
                            }
                        } label: {
                            ZStack {
                                Text(step == .email ? L10n.text(.resetSendCode) : L10n.text(.resetChangePassword))
                                    .opacity(isLoading ? 0 : 1)
                                if isLoading {
                                    ProgressView().tint(PlinkShell.text)
                                }
                            }
                        }
                        .buttonStyle(AuthPrimaryButtonStyle())
                        .disabled(isLoading || (step == .email ? !emailIsValid : (code.count != 6 || newPassword.count < 6)))

                        if step == .code {
                            Button(L10n.text(.resetResend)) {
                                Task { await sendCode() }
                            }
                            .authFont(13, weight: .semibold)
                            .foregroundStyle(PlinkShell.accentSoft)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                            .disabled(isLoading)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle(L10n.text(.resetNewPassword))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                V4SheetCloseToolbarItem { dismiss() }
            }
            .onAppear {
                if email.isEmpty { email = prefilledEmail }
                focus = step == .email ? .email : .code
            }
        }
    }

    private func sendCode() async {
        guard emailIsValid else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await AuthService.shared.requestPasswordReset(email: trimmedEmail)
            infoMessage = L10n.text(.resetSent)
            step = .code
            focus = .code
        } catch {
            errorMessage = AuthErrorCopy.message(for: error)
        }
    }

    private func confirm() async {
        guard code.count == 6, newPassword.count >= 6 else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await AuthService.shared.confirmPasswordReset(
                email: trimmedEmail,
                code: code,
                newPassword: newPassword
            )
            HapticManager.notification(.success)
            dismiss()
        } catch {
            errorMessage = AuthErrorCopy.message(for: error)
        }
    }
}
