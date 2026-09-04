// Full-screen story viewer for the Friends tab — Telegram's viewer, film
// posters instead of photos. Tap the right third to advance, the left to go
// back, hold to pause, drag down to close. Owners chain: the last slide of one
// person leads into the next person, the last person closes the viewer.
import SwiftUI

struct PlinkStoryViewer: View {
    let theme: V4Theme
    let presentation: PlinkStoryPresentation
    /// The viewer's own id — own stories get "edit status" instead of a CTA.
    var myUserId: String?
    var onWatchTogether: (FriendStoryOwner) -> Void = { _ in }
    var onMessage: (FriendStoryOwner) -> Void = { _ in }
    var onProfile: (FriendStoryOwner) -> Void = { _ in }
    var onEditStatus: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var ownerIndex: Int
    @State private var slideIndex = 0
    @State private var progress: Double = 0
    /// PLINK_STORY_HOLD=1 (симулятор/скриншоты) — держит первый слайд без автопрокрутки.
    @State private var paused = ProcessInfo.processInfo.environment["PLINK_STORY_HOLD"] == "1"
    @State private var dragY: CGFloat = 0
    @State private var closing = false

    private let slideDuration: Double = 6

    init(
        theme: V4Theme,
        presentation: PlinkStoryPresentation,
        myUserId: String? = nil,
        onWatchTogether: @escaping (FriendStoryOwner) -> Void = { _ in },
        onMessage: @escaping (FriendStoryOwner) -> Void = { _ in },
        onProfile: @escaping (FriendStoryOwner) -> Void = { _ in },
        onEditStatus: @escaping () -> Void = {}
    ) {
        self.theme = theme
        self.presentation = presentation
        self.myUserId = myUserId
        self.onWatchTogether = onWatchTogether
        self.onMessage = onMessage
        self.onProfile = onProfile
        self.onEditStatus = onEditStatus
        _ownerIndex = State(initialValue: min(max(presentation.start, 0), max(presentation.owners.count - 1, 0)))
    }

    enum Slide: Hashable {
        case status(String)
        case watch(FriendStorySlide)
    }

    private var owner: FriendStoryOwner? {
        presentation.owners.indices.contains(ownerIndex) ? presentation.owners[ownerIndex] : nil
    }

    private var isMine: Bool { owner?.id == myUserId }

    private func slides(of owner: FriendStoryOwner) -> [Slide] {
        var list: [Slide] = []
        if let status = owner.trimmedStatus { list.append(.status(status)) }
        list.append(contentsOf: owner.slides.map(Slide.watch))
        return list
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                if let owner {
                    let all = slides(of: owner)
                    let slide = all.indices.contains(slideIndex) ? all[slideIndex] : nil
                    card(owner: owner, slides: all, slide: slide, size: geo.size)
                        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                        .padding(.horizontal, dragY > 0 ? 8 : 0)
                        .scaleEffect(max(0.86, 1 - dragY / 900), anchor: .top)
                        .offset(y: max(0, dragY))
                        .opacity(closing ? 0 : 1)
                        .id(owner.id)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                        .gesture(dismissDrag)
                        .task(id: "\(owner.id)-\(slideIndex)") { await runTimer() }
                        .onAppear { PlinkStorySeenLedger.shared.markSeen(owner) }
                        .onChange(of: ownerIndex) { _, _ in
                            if let owner = self.owner { PlinkStorySeenLedger.shared.markSeen(owner) }
                        }
                }
            }
            .background(Color.black)
        }
        .statusBarHidden(true)
        .preferredColorScheme(.dark)
    }

    // MARK: - Card

    private func card(owner: FriendStoryOwner, slides: [Slide], slide: Slide?, size: CGSize) -> some View {
        ZStack {
            slideBackdrop(slide)
            // Tap zones: left third back, the rest forward.
            HStack(spacing: 0) {
                Color.clear.contentShape(Rectangle())
                    .frame(width: size.width * 0.33)
                    .onTapGesture { step(-1, slideCount: slides.count) }
                Color.clear.contentShape(Rectangle())
                    .onTapGesture { step(1, slideCount: slides.count) }
            }
            .onLongPressGesture(minimumDuration: 0.18, pressing: { paused = $0 }, perform: {})

            VStack(spacing: 0) {
                progressBars(count: slides.count)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                header(owner)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                Spacer(minLength: 0)
                if let slide {
                    slideBody(slide, owner: owner)
                        .padding(.horizontal, 22)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        .id(slideKey(slide))
                }
                Spacer(minLength: 0)
                footer(owner, slide: slide)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 18)
            }
            .allowsHitTesting(true)
        }
        .animation(.easeInOut(duration: 0.22), value: slideIndex)
    }

    private func slideKey(_ slide: Slide) -> String {
        switch slide {
        case .status(let text): return "status-\(text.hashValue)"
        case .watch(let entry): return "watch-\(entry.id)"
        }
    }

    private func slideBackdrop(_ slide: Slide?) -> some View {
        ZStack {
            LinearGradient(
                colors: [theme.accentColor.opacity(0.55), Color.black.opacity(0.92), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            if case .watch(let entry)? = slide, let url = entry.thumbURL {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                            .blur(radius: 46)
                            .saturation(1.25)
                            .opacity(0.75)
                            .transition(.opacity)
                    }
                }
                .allowsHitTesting(false)
            }
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.55), location: 0),
                    .init(color: .clear, location: 0.22),
                    .init(color: .clear, location: 0.62),
                    .init(color: .black.opacity(0.78), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }

    private func progressBars(count: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<max(count, 1), id: \.self) { i in
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.28))
                        Capsule()
                            .fill(.white)
                            .frame(width: g.size.width * fill(for: i))
                    }
                }
                .frame(height: 2.5)
            }
        }
    }

    private func fill(for index: Int) -> CGFloat {
        if index < slideIndex { return 1 }
        if index > slideIndex { return 0 }
        return CGFloat(min(max(progress, 0), 1))
    }

    private func header(_ owner: FriendStoryOwner) -> some View {
        HStack(spacing: 10) {
            Button {
                guard !isMine else { return }
                HapticManager.impact(.light)
                close { onProfile(owner) }
            } label: {
                HStack(spacing: 10) {
                    PlinkStableAvatar(
                        url: PlinkAvatarURL.stable(userId: owner.id, stored: owner.avatarURL),
                        letter: owner.initials,
                        size: 34,
                        userId: owner.id
                    )
                    .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(isMine ? LocalizationManager.shared.string(.frMyStory) : owner.displayTitle)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(headerCaption(owner))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Button {
                close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.14), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    private func headerCaption(_ owner: FriendStoryOwner) -> String {
        if let at = owner.latestWatchedAt {
            return at.formatted(.relative(presentation: .named))
        }
        return owner.isOnline ? "online" : LocalizationManager.shared.string(.frStoryStatus)
    }

    // MARK: - Slide bodies

    @ViewBuilder
    private func slideBody(_ slide: Slide, owner: FriendStoryOwner) -> some View {
        switch slide {
        case .status(let text):
            VStack(spacing: 18) {
                Image(systemName: "quote.opening")
                    .font(.system(size: 30, weight: .black))
                    .foregroundStyle(.white.opacity(0.55))
                Text(text)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                    .lineLimit(6)
                Text(LocalizationManager.shared.string(.frStoryStatus).uppercased())
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.6))
            }
        case .watch(let entry):
            VStack(spacing: 18) {
                poster(entry)
                VStack(spacing: 6) {
                    Text(entry.title)
                        .font(.system(size: 24, weight: .heavy))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                    Text(watchCaption(entry))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
        }
    }

    private func poster(_ entry: FriendStorySlide) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [theme.accentColor.opacity(0.65), Color.black.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: PlinkMediaKind.symbol(for: entry.kind))
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            if let url = entry.thumbURL {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill().transition(.opacity)
                    }
                }
            }
        }
        .frame(width: 210, height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.16), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 24, y: 14)
    }

    private func watchCaption(_ entry: FriendStorySlide) -> String {
        var parts: [String] = []
        if let kind = PlinkMediaKind.title(for: entry.kind) { parts.append(kind) }
        if let at = entry.watchedAt {
            parts.append("\(LocalizationManager.shared.string(.frStoryWatched).lowercased()) \(at.formatted(.relative(presentation: .named)))")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Footer

    @ViewBuilder
    private func footer(_ owner: FriendStoryOwner, slide: Slide?) -> some View {
        if isMine {
            Button {
                HapticManager.impact(.light)
                close { onEditStatus() }
            } label: {
                Label(LocalizationManager.shared.string(.frStoryEditStatus), systemImage: "pencil")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(.white.opacity(0.16), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.22), lineWidth: 1))
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 10) {
                Button {
                    HapticManager.impact(.medium)
                    close { onWatchTogether(owner) }
                } label: {
                    Label(LocalizationManager.shared.string(.dvWatchTogether), systemImage: "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(theme.accentColor.opacity(0.92), in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)
                Button {
                    HapticManager.impact(.light)
                    close { onMessage(owner) }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background(.white.opacity(0.16), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.22), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(LocalizationManager.shared.string(.frStoryMessage))
            }
        }
    }

    // MARK: - Navigation

    private func step(_ delta: Int, slideCount: Int) {
        let next = slideIndex + delta
        if next >= 0 && next < slideCount {
            progress = 0
            slideIndex = next
            return
        }
        let nextOwner = ownerIndex + (delta > 0 ? 1 : -1)
        guard presentation.owners.indices.contains(nextOwner) else {
            if delta > 0 { close() } else { progress = 0 }
            return
        }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            ownerIndex = nextOwner
            slideIndex = delta > 0 ? 0 : max(slides(of: presentation.owners[nextOwner]).count - 1, 0)
            progress = 0
        }
    }

    private func runTimer() async {
        progress = 0
        let tick: Double = 1.0 / 30.0
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(tick * 1_000_000_000))
            if Task.isCancelled { return }
            guard !paused, dragY == 0 else { continue }
            progress += tick / slideDuration
            if progress >= 1 {
                if let owner { step(1, slideCount: slides(of: owner).count) }
                return
            }
        }
    }

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if value.translation.height > 0 { dragY = value.translation.height }
            }
            .onEnded { value in
                if value.translation.height > 120 || value.predictedEndTranslation.height > 260 {
                    close()
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { dragY = 0 }
                }
            }
    }

    private func close(then action: @escaping () -> Void = {}) {
        guard !closing else { return }
        withAnimation(.easeOut(duration: 0.18)) { closing = true }
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { action() }
    }
}
