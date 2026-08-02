// Plink/V4/V4RoomsViewLive.swift — split from PlinkV4PixelPerfect (move-only, no logic change)
// Source of truth: V4 design module. Do not change visuals.

import SwiftUI
import PhotosUI
import UIKit
import Foundation

// Аудит 26.07.2026: здесь был статический макет с захардкоженными данными
// (0 инстанцирований по всему проекту) — удалён, живой экран ниже.

struct V4RoomsViewLive: View {
    let theme: V4Theme
    var roomsStore: V4RoomsStore?
    let openRoom: (Room) -> Void
    let createRoom: () -> Void
    let joinByCode: () -> Void

    // Rooms has one job: enter an existing room or start a new one.
    @State private var searchQuery = ""
    @State private var searchExpanded = false

    var body: some View {
        ScrollView(showsIndicators:false) {
            VStack(spacing:0) {
                HStack(alignment:.center, spacing: 10) {
                    V4Heading(eyebrow:"ВМЕСТЕ СЕЙЧАС",title:"Комнаты")
                        .accessibilityIdentifier("screen.rooms")
                    Spacer()
                    Button {
                        HapticManager.selection()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                            searchExpanded.toggle()
                            if !searchExpanded { searchQuery = "" }
                        }
                    } label: {
                        Image(systemName: searchExpanded ? "xmark" : "magnifyingglass")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(V4.ink)
                            .frame(width: 44, height: 44)
                            .background(V4.roundBG, in: Circle())
                            .overlay(Circle().stroke(V4.line))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(searchExpanded ? "Закрыть поиск" : "Найти комнату")
                    Button {
                        HapticManager.selection()
                        joinByCode()
                    } label: {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(V4.ink)
                            .frame(width: 44, height: 44)
                            .background(V4.roundBG, in: Circle())
                            .overlay(Circle().stroke(V4.line))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Войти по коду комнаты")
                    Button {
                        HapticManager.impact(.medium)
                        createRoom()
                    } label: {
                        Image(systemName:"plus")
                            .font(.system(size: 16, weight: .black))
                            .foregroundStyle(theme.buttonTextColor)
                            .frame(width: 44, height: 44)
                            .background(theme.accentColor, in: Circle())
                            .shadow(color: theme.accentColor.opacity(0.3), radius: 12, y: 6)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Создать комнату")
                }.padding(.horizontal,18).padding(.top,10).padding(.bottom,16)

                if searchExpanded {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(theme.accentColor)
                            .font(.system(size:14, weight: .semibold))
                        TextField("Название комнаты или владелец", text: $searchQuery)
                            .foregroundStyle(V4.ink)
                            .font(.system(size:14, weight: .medium))
                        if !searchQuery.isEmpty {
                            Button { searchQuery = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(V4.muted)
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Очистить поиск")
                        }
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 4)
                    .frame(minHeight: 50)
                    .background(
                        LinearGradient(
                            colors: [V4.surface.opacity(0.96), theme.accentColor.opacity(0.07)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(theme.accentColor.opacity(0.18), lineWidth: 1)
                    )
                    .padding(.horizontal, 18)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                if let rs = roomsStore {
                    switch rs.state {
                    case .loading:
                        RoundedRectangle(cornerRadius: 29).fill(V4.cardBG).frame(height: 235).padding(.horizontal,13).padding(.bottom,28)
                            .overlay { ProgressView().tint(theme.accentColor) }
                    case .loaded:
                        let filteredRooms = rs.rooms.filter { room in
                            searchQuery.isEmpty ||
                            room.name.localizedCaseInsensitiveContains(searchQuery) ||
                            room.hostName.localizedCaseInsensitiveContains(searchQuery) ||
                            (room.mediaItem?.title.localizedCaseInsensitiveContains(searchQuery) ?? false)
                        }
                        let featuredRoom: Room? = searchQuery.isEmpty
                            ? (rs.heroRoom ?? filteredRooms.first)
                            : filteredRooms.first
                        let filteredRail = filteredRooms.filter { $0.id != featuredRoom?.id }
                        if filteredRooms.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: searchQuery.isEmpty ? "person.3.sequence.fill" : "magnifyingglass")
                                    .font(.title2)
                                    .foregroundStyle(V4.muted)
                                Text(searchQuery.isEmpty ? "Пока нет активных комнат" : "Ничего не найдено")
                                    .font(.headline)
                                Text(searchQuery.isEmpty ? "Создай первую комнату или войди по коду друга" : "Проверь название комнаты или имя владельца")
                                    .font(.subheadline)
                                    .foregroundStyle(V4.muted)
                                    .multilineTextAlignment(.center)
                                if searchQuery.isEmpty {
                                    Button("Создать комнату") { createRoom() }
                                        .buttonStyle(.borderedProminent)
                                        .tint(theme.accentColor)
                                        .foregroundStyle(theme.buttonTextColor)
                                        .frame(minHeight: 44)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 40)
                        } else {
                            if let featuredRoom {
                                roomFeatureCard(featuredRoom)
                                    .padding(.horizontal, 18)
                                    .padding(.bottom, 26)
                            }
                            if !filteredRail.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 11) {
                                    ForEach(filteredRail) { room in
                                        roomRailCard(room)
                                    }
                                }.padding(.horizontal, 19)
                            }
                            }
                        }
                    case .empty:
                        VStack(spacing:16) {
                            Image(systemName:"plus.app.fill")
                                .font(.system(size: 48, weight: .semibold))
                                .foregroundStyle(theme.accentColor)
                            Text("Нет активных комнат").font(.headline)
                            Text("Создай свою комнату и пригласи друзей смотреть вместе").font(.subheadline).foregroundStyle(V4.muted)
                                .multilineTextAlignment(.center)
                            Button {
                                createRoom()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "plus")
                                    Text("Создать комнату")
                                }
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(theme.buttonTextColor)
                                .padding(.horizontal, 20)
                                .frame(minHeight: 44)
                                .background(theme.accentColor)
                                .clipShape(Capsule())
                            }
                        }.padding(.top,60).padding(.horizontal,24)
                    case .failed(let error):
                        VStack(spacing:12) {
                            Image(systemName:"exclamationmark.triangle").font(.largeTitle).foregroundStyle(V4.amber)
                            Text(error).font(.subheadline).foregroundStyle(V4.muted)
                            Button("Повторить") { Task { await roomsStore?.load() } }
                                .buttonStyle(.borderedProminent)
                                .tint(theme.accentColor)
                                .foregroundStyle(theme.buttonTextColor)
                                .frame(minHeight: 44)
                        }.padding(.top,60)
                    case .idle:
                        Color.clear.frame(height:100)
                    }
                } else {
                    ProgressView().tint(theme.accentColor).padding(.top,60)
                }
            }.padding(.bottom,96)
        }.foregroundStyle(V4.ink)
        .refreshable { await roomsStore?.load() }
    }

    private func roomFeatureCard(_ room: Room) -> some View {
        Button {
            HapticManager.impact(.medium)
            openRoom(room)
        } label: {
            ZStack(alignment: .bottomLeading) {
                roomArtwork(room)
                    .frame(maxWidth: .infinity)
                    .frame(height: 268)
                    .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.22), .black.opacity(0.94)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        if room.isActive {
                            HStack(spacing: 6) {
                                Circle().fill(.white).frame(width: 5, height: 5)
                                Text("LIVE")
                            }
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(V4.danger, in: Capsule())
                        }
                        Text("\(room.participantCount) смотрят")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .plinkGlass(.control, in: Capsule(style: .continuous))
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(theme.buttonTextColor)
                            .frame(width: 40, height: 40)
                            .background(theme.accentColor, in: Circle())
                    }

                    Spacer(minLength: 30)

                    Text(room.mediaItem?.title ?? room.name)
                        .font(.system(size: 25, weight: .black))
                        .tracking(-0.55)
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.fill")
                        Text("\(room.name) · Владелец: \(room.hostName)")
                            .lineLimit(1)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.74))
                }
                .padding(18)
            }
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [theme.accentColor.opacity(0.34), .white.opacity(0.10), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.42), radius: 28, y: 16)
        }
        .buttonStyle(.plain)
    }

    private func roomRailCard(_ room: Room) -> some View {
        Button {
            HapticManager.impact(.light)
            openRoom(room)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topLeading) {
                    roomArtwork(room)
                        .frame(width: 238, height: 148)
                        .clipped()
                    LinearGradient(
                        colors: [.black.opacity(0.44), .clear, .black.opacity(0.58)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    HStack(spacing: 6) {
                        if room.isActive {
                            Circle().fill(V4.danger).frame(width: 7, height: 7)
                        }
                        Text(room.isActive ? "Сейчас" : "Комната")
                    }
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .plinkGlass(.control, in: Capsule(style: .continuous))
                    .padding(12)
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                Text(room.mediaItem?.title ?? room.name)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(V4.ink)
                    .lineLimit(2)
                HStack(spacing: 5) {
                    Image(systemName: "person.2.fill")
                    Text("\(room.participantCount)")
                    Text("·")
                    Text(room.hostName).lineLimit(1)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(V4.muted)
            }
            .padding(9)
            .frame(width: 256, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [V4.surface.opacity(0.92), theme.accentColor.opacity(0.055)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 25, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .stroke(theme.accentColor.opacity(0.13), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func roomArtwork(_ room: Room) -> some View {
        if let raw = room.mediaItem?.thumbnailURL, let url = URL(string: raw) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image): image.resizable().aspectRatio(contentMode: .fill)
                default: roomArtworkFallback(room)
                }
            }
        } else {
            roomArtworkFallback(room)
        }
    }

    private func roomArtworkFallback(_ room: Room) -> some View {
        let seed = abs(room.id.hashValue)
        let hue = Double(seed % 70) + 225
        return ZStack {
            LinearGradient(
                colors: [
                    Color.oklch(0.58, 0.22, hue),
                    Color.oklch(0.26, 0.14, hue + 35),
                    Color.oklch(0.07, 0.03, 250)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(.white.opacity(0.11))
                .frame(width: 190, height: 190)
                .blur(radius: 10)
                .offset(x: 110, y: -64)
            Image(systemName: "play.fill")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.white.opacity(0.72))
                .shadow(color: .black.opacity(0.34), radius: 18)
        }
    }
}


