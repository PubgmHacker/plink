// «Почему Plink безопаснее» — клин против кризиса доверия Rave (strategy P0-2).

import SwiftUI

struct PlinkSaferScreen: View {
    @Environment(\.dismiss) private var dismiss

    private let points: [(icon: String, title: String, body: String)] = [
        (
            "lock.shield.fill",
            "Без чужих паролей",
            "Plink не просит логины Netflix или Кинопоиска. Вы входите в свой аккаунт сами — или шарите экран. Мы не храним пароли сторонних сервисов."
        ),
        (
            "eye.slash.fill",
            "Нет скрытой слежки",
            "Нет невидимого прокси контента и «магического» обхода DRM. Режим «ваш экран» честно говорит, как устроен просмотр кинотеатров."
        ),
        (
            "hand.raised.fill",
            "Контроль данных",
            "Удаление аккаунта из приложения уходит на сервер (grace 14 дней). Экспорт и анонимизация — через GDPR-эндпоинты."
        ),
        (
            "person.2.slash.fill",
            "Модерация и блоки",
            "Жалобы, блоки и админ-панель с аутентификацией. UGC не остаётся без инструментов App Store 1.2."
        ),
        (
            "waveform.path.ecg",
            "Синхрон, который видно",
            "Значок дрейфа показывает, насколько вы в такте — без «верь на слово»."
        ),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Смотрите вместе без чужих паролей и без чёрного ящика.")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(V4.ink)
                        .padding(.top, 8)

                    Text("Коротко: что отличается от приложений, которые просят OTT-логины и обещают «любой сервис» в WebView.")
                        .font(.system(size: 14))
                        .foregroundStyle(V4.muted)

                    ForEach(Array(points.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: item.icon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(V4.accent)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(V4.ink)
                                Text(item.body)
                                    .font(.system(size: 13.5))
                                    .foregroundStyle(V4.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(V4.surface.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .background(V4.canvas.ignoresSafeArea())
            .navigationTitle("Почему Plink безопаснее")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            AnalyticsService.shared.track("safer_screen_open")
        }
    }
}
