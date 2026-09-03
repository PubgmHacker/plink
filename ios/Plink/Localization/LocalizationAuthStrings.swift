import Foundation

// Auth, session, error and onboarding copy. It lives in its own file so that
// LocalizationManager.swift stays inside the SwiftLint file/type budget; the
// two dictionaries are merged into `L10n.table`, which is the only lookup the
// app uses. Add new auth/onboarding keys to `L10n.Key` and to this table.
extension L10n {
    static let authTable: [Key: [AppLanguage: String]] = [
        .authModeSignIn: [
            .russian: "Вход",
            .english: "Sign in",
            .chinese: "登录"
        ],
        .authModeSignUp: [
            .russian: "Регистрация",
            .english: "Sign up",
            .chinese: "注册"
        ],
        .authActionSignIn: [
            .russian: "Войти",
            .english: "Sign in",
            .chinese: "登录"
        ],
        .authMethodEmail: [
            .russian: "Почта",
            .english: "Email",
            .chinese: "邮箱"
        ],
        .authHeroA11y: [
            .russian: "Plink. Смотрите вместе — кадр в кадр",
            .english: "Plink. Watch together, frame for frame",
            .chinese: "Plink。一起观看，同步每一帧"
        ],
        .authMethodPickerA11y: [
            .russian: "Способ входа",
            .english: "Sign-in method",
            .chinese: "登录方式"
        ],
        .authEmailTypo: [
            .russian: "Похоже, в адресе опечатка",
            .english: "That address looks mistyped",
            .chinese: "邮箱地址似乎有误"
        ],
        .authUsernameTitle: [
            .russian: "Имя пользователя",
            .english: "Username",
            .chinese: "用户名"
        ],
        .authUsernameHint: [
            .russian: "5–32 символа: латиница, цифры и _, первая — буква",
            .english: "5–32 characters: Latin letters, digits and _, starting with a letter",
            .chinese: "5–32 个字符：拉丁字母、数字和下划线，首位为字母"
        ],
        .authPasswordTitle: [
            .russian: "Пароль",
            .english: "Password",
            .chinese: "密码"
        ],
        .authPasswordMin: [
            .russian: "Не меньше 6 символов",
            .english: "At least 6 characters",
            .chinese: "至少 6 个字符"
        ],
        .authHidePassword: [
            .russian: "Скрыть пароль",
            .english: "Hide password",
            .chinese: "隐藏密码"
        ],
        .authShowPassword: [
            .russian: "Показать пароль",
            .english: "Show password",
            .chinese: "显示密码"
        ],
        .authForgotPassword: [
            .russian: "Забыли пароль?",
            .english: "Forgot password?",
            .chinese: "忘记密码？"
        ],
        .authForgotPasswordA11y: [
            .russian: "Забыли пароль",
            .english: "Forgot password",
            .chinese: "忘记密码"
        ],
        .authInProgress: [
            .russian: "Выполняется",
            .english: "In progress",
            .chinese: "处理中"
        ],
        .authErrEmail: [
            .russian: "Проверьте адрес электронной почты",
            .english: "Check the email address",
            .chinese: "请检查邮箱地址"
        ],
        .authErrUsername: [
            .russian: "Имя пользователя: 5–32 символа, латиница, цифры и _, первая — буква",
            .english: "Username: 5–32 characters, Latin letters, digits and _, starting with a letter",
            .chinese: "用户名：5–32 个字符，拉丁字母、数字和下划线，首位为字母"
        ],
        .authErrPassword: [
            .russian: "Пароль должен содержать не меньше 6 символов",
            .english: "Password must be at least 6 characters",
            .chinese: "密码至少需要 6 个字符"
        ],
        .resetIntroEmail: [
            .russian: "Пришлём код на почту. Если аккаунта нет — письмо не придёт, так и задумано.",
            .english: "We'll email you a code. If there is no account, no email arrives — that's by design.",
            .chinese: "我们会把验证码发送到您的邮箱。如果账号不存在则不会收到邮件，这是有意为之。"
        ],
        .resetIntroCode: [
            .russian: "Введите код из письма и новый пароль.",
            .english: "Enter the code from the email and a new password.",
            .chinese: "请输入邮件中的验证码和新密码。"
        ],
        .resetCodeTitle: [
            .russian: "Код из письма",
            .english: "Code from the email",
            .chinese: "邮件验证码"
        ],
        .resetNewPassword: [
            .russian: "Новый пароль",
            .english: "New password",
            .chinese: "新密码"
        ],
        .resetSendCode: [
            .russian: "Отправить код",
            .english: "Send code",
            .chinese: "发送验证码"
        ],
        .resetChangePassword: [
            .russian: "Сменить пароль",
            .english: "Change password",
            .chinese: "更改密码"
        ],
        .resetResend: [
            .russian: "Отправить код ещё раз",
            .english: "Send the code again",
            .chinese: "重新发送验证码"
        ],
        .resetSent: [
            .russian: "Если аккаунт есть, код уже на почте. Проверьте входящие и спам.",
            .english: "If the account exists, the code is in your inbox. Check spam too.",
            .chinese: "如果账号存在，验证码已发送到您的邮箱。请同时检查垃圾邮件。"
        ],
        .authAppleSigningIn: [
            .russian: "Входим…",
            .english: "Signing in…",
            .chinese: "正在登录…"
        ],
        .authAppleButton: [
            .russian: "Войти через Apple",
            .english: "Sign in with Apple",
            .chinese: "通过 Apple 登录"
        ],
        .authAppleNoToken: [
            .russian: "Apple не вернул identity token",
            .english: "Apple did not return an identity token",
            .chinese: "Apple 未返回身份令牌"
        ],
        .authConsentPrefix: [
            .russian: "Продолжая, вы принимаете",
            .english: "By continuing, you accept",
            .chinese: "继续即表示您接受"
        ],
        .sessionExpiredSecure: [
            .russian: "Сессия истекла. Войдите заново — это защищает ваш аккаунт.",
            .english: "Your session expired. Sign in again — this protects your account.",
            .chinese: "会话已过期。请重新登录，这是为了保护您的账号。"
        ],
        .sessionExpiredKept: [
            .russian: "Сессия истекла. Войдите заново — мы сохранили ваши локальные настройки.",
            .english: "Your session expired. Sign in again — your local settings are kept.",
            .chinese: "会话已过期。请重新登录，您的本地设置已保留。"
        ],
        .launchA11y: [
            .russian: "Plink. Смотрим вместе. Загрузка",
            .english: "Plink. Watching together. Loading",
            .chinese: "Plink。一起观看。正在加载"
        ],
        .errBadCredentials: [
            .russian: "Неверная почта или пароль",
            .english: "Wrong email or password",
            .chinese: "邮箱或密码错误"
        ],
        .errAccountExists: [
            .russian: "Аккаунт с такими данными уже существует",
            .english: "An account with these details already exists",
            .chinese: "该账号信息已被注册"
        ],
        .errSessionEnded: [
            .russian: "Сессия завершена. Войдите снова",
            .english: "Session ended. Sign in again",
            .chinese: "会话已结束，请重新登录"
        ],
        .errNotFound: [
            .russian: "Не удалось найти нужные данные",
            .english: "Couldn't find the requested data",
            .chinese: "未找到所需数据"
        ],
        .errPlusOnly: [
            .russian: "Эта возможность доступна в Плинк+",
            .english: "This feature is available in Plink+",
            .chinese: "此功能仅在 Plink+ 中可用"
        ],
        .errComingSoon: [
            .russian: "Функция скоро появится",
            .english: "This feature is coming soon",
            .chinese: "此功能即将推出"
        ],
        .errUnavailable: [
            .russian: "Plink сейчас недоступен. Попробуйте ещё раз чуть позже",
            .english: "Plink is unavailable right now. Try again a little later",
            .chinese: "Plink 暂时不可用，请稍后再试"
        ],
        .errOffline: [
            .russian: "Нет подключения к интернету",
            .english: "No internet connection",
            .chinese: "没有网络连接"
        ],
        .errTimeout: [
            .russian: "Сервис отвечает слишком долго. Попробуйте ещё раз",
            .english: "The service is taking too long. Try again",
            .chinese: "服务响应超时，请重试"
        ],
        .errConnect: [
            .russian: "Не удалось подключиться к Plink. Проверьте интернет и повторите",
            .english: "Couldn't connect to Plink. Check your connection and retry",
            .chinese: "无法连接到 Plink。请检查网络后重试"
        ],
        .errGeneric: [
            .russian: "Не удалось выполнить действие. Попробуйте ещё раз",
            .english: "Couldn't complete the action. Try again",
            .chinese: "操作未能完成，请重试"
        ],
        .onbNow: [
            .russian: "сейчас",
            .english: "now",
            .chinese: "刚刚"
        ],
        .onbInvitePreview: [
            .russian: "Аня зовёт смотреть вместе — комната уже открыта",
            .english: "Anya invites you to watch together — the room is already open",
            .chinese: "Anya 邀请你一起观看，房间已经打开"
        ],
        .onbStepA11y: [
            .russian: "Шаг %d из %d",
            .english: "Step %d of %d",
            .chinese: "第 %d 步，共 %d 步"
        ],
        .onbAllowStart: [
            .russian: "Разрешить и начать",
            .english: "Allow and start",
            .chinese: "允许并开始"
        ],
        .onbNext: [
            .russian: "Далее",
            .english: "Next",
            .chinese: "下一步"
        ],
        .onbAllowStartA11y: [
            .russian: "Разрешить уведомления и начать",
            .english: "Allow notifications and start",
            .chinese: "允许通知并开始"
        ],
        .onbNotNow: [
            .russian: "Не сейчас",
            .english: "Not now",
            .chinese: "暂不"
        ],
        .onbSkip: [
            .russian: "Пропустить",
            .english: "Skip",
            .chinese: "跳过"
        ],
        .onbStartWithout: [
            .russian: "Начать без уведомлений",
            .english: "Start without notifications",
            .chinese: "不开启通知直接开始"
        ],
        .onbSkipTourA11y: [
            .russian: "Пропустить знакомство",
            .english: "Skip the tour",
            .chinese: "跳过介绍"
        ],
        .onbEyebrowCatalog: [
            .russian: "Один таймкод на всех",
            .english: "One timecode for everyone",
            .chinese: "所有人同一时间轴"
        ],
        .onbEyebrowRooms: [
            .russian: "Комнаты",
            .english: "Rooms",
            .chinese: "房间"
        ],
        .onbEyebrowChats: [
            .russian: "Общение",
            .english: "Chat",
            .chinese: "交流"
        ],
        .onbTitleCatalog: [
            .russian: "Смотрим вместе",
            .english: "Watch together",
            .chinese: "一起观看"
        ],
        .onbTitleRooms: [
            .russian: "Комната за секунду",
            .english: "A room in a second",
            .chinese: "一秒创建房间"
        ],
        .onbTitleChats: [
            .russian: "Друзья зовут смотреть",
            .english: "Friends invite you to watch",
            .chinese: "朋友邀你一起看"
        ],
        .onbBodyCatalog: [
            .russian: "Кино и сериалы из каталога — в одной комнате с друзьями. Один плеер на всех: пауза у одного — пауза у каждого.",
            .english: "Films and series from the catalogue, in one room with friends. One player for everyone: when one pauses, everyone pauses.",
            .chinese: "目录中的电影和剧集，与朋友同在一个房间。所有人共用一个播放器：一人暂停，所有人暂停。"
        ],
        .onbBodyRooms: [
            .russian: "Создайте комнату или войдите по коду из шести символов. Кадр в кадр, где бы ни были друзья.",
            .english: "Create a room or join with a six-character code. Frame for frame, wherever your friends are.",
            .chinese: "创建房间，或用六位代码加入。无论朋友在哪里，画面帧帧同步。"
        ],
        .onbBodyChats: [
            .russian: "Чаты, заявки в друзья и приглашения в комнаты приходят уведомлениями — вы не пропустите вечер, когда вас позвали.",
            .english: "Chats, friend requests and room invites arrive as notifications — you won't miss the night you were invited to.",
            .chinese: "聊天、好友请求和房间邀请都会以通知送达，不会错过朋友邀你的夜晚。"
        ],
        .profileTerms: [
            .russian: "Условия использования",
            .english: "Terms of Use",
            .chinese: "使用条款"
        ],
        .biometricReason: [
            .russian: "Подтвердите вход для этого действия",
            .english: "Confirm it's you to continue",
            .chinese: "请验证身份以继续"
        ],
    ]
}
