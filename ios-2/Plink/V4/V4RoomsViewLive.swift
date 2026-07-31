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
    let openRoom: () -> Void
    var createRoom: (() -> Void)? = nil
    var joinByCode: (() -> Void)? = nil

    // M32: поиск + фильтр
    @State private var searchQuery = ""
    @State private var roomFilter: RoomFilter = .all

    enum RoomFilter: String, CaseIterable {
        case all      = "Все"
        case active   = "Сейчас"
        case friends  = "Друзья"
    }

    var body: some View {
        ScrollView(showsIndicators:false) {
            VStack(spacing:0) {
                HStack(alignment:.top) {
                    V4Heading(eyebrow:"ОБЗОР",title:"Комнаты")
                        .accessibilityIdentifier("screen.rooms")
                    Spacer()
                    Button {
                        HapticManager.selection()
                        joinByCode?()
                    } label: {
                        // Join-by-code — NOT person.badge.plus (that’s “add friend”)
                        HStack(spacing:4) {
                            Image(systemName: "qrcode")
                                .font(.system(size:13, weight:.bold))
                            Text("Код")
                                .font(.system(size:11, weight:.heavy))
                        }
                        .foregroundStyle(theme.buttonTextColor)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(theme.accentColor, in: Capsule())
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Войти по коду комнаты")
                    .padding(.trailing, 8)
                    Button {
                        HapticManager.selection()
                        createRoom?()
                    } label: {
                        Image(systemName:"plus.circle.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(theme.accentColor)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Создать комнату")
                }.padding(.horizontal,18).padding(.top,10).padding(.bottom,16)

                // M32: поиск комнат
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass").foregroundStyle(V4.muted).font(.system(size:14))
                    TextField("Поиск комнат...", text: $searchQuery)
                        .foregroundStyle(V4.ink)
                        .font(.system(size:13))
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
                .padding(.horizontal, 13)
                .frame(minHeight: 44)
                .background(V4.searchBG)
                .clipShape(RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(V4.line))
                .padding(.horizontal, 18)
                .padding(.bottom, 10)

                // M32: фильтр-пилюли
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(RoomFilter.allCases, id: \.self) { f in
                            Button {
                                HapticManager.selection()
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) { roomFilter = f }
                            } label: {
                                Text(f.rawValue)
                                    .font(.system(size: 12, weight: roomFilter == f ? .bold : .medium))
                                    .foregroundStyle(roomFilter == f ? theme.buttonTextColor : V4.muted)
                                    .padding(.horizontal, 14)
                                    .frame(minHeight: 44)
                                    .background(roomFilter == f ? theme.accentColor : V4.cardBG.opacity(0.5), in: Capsule())
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 18)
                }.padding(.bottom, 12)

                if let rs = roomsStore {
                    switch rs.state {
                    case .loading:
                        RoundedRectangle(cornerRadius: 29).fill(V4.cardBG).frame(height: 235).padding(.horizontal,13).padding(.bottom,28)
                            .overlay { ProgressView().tint(theme.accentColor) }
                    case .loaded:
                        if let hero = rs.heroRoom {
                            V4Hero(title: hero.name, meta: "\(hero.participantCount) зрителей · открытая комната", button:"Войти",height:235,theme:theme,action:openRoom)
                                .padding(.horizontal,13).padding(.bottom,28)
                        }
                        // M32/M33: поиск + фильтр (в т.ч. по друзьям) + обложки
                        let friendNames: Set<String> = Set(FriendManager.shared.friends.map { $0.username.lowercased() })
                        let filteredRail: [Room] = rs.railRooms.filter { room in
                            let matchesSearch = searchQuery.isEmpty || room.name.localizedCaseInsensitiveContains(searchQuery)
                            let matchesFilter: Bool
                            switch roomFilter {
                            case .all: matchesFilter = true
                            case .active: matchesFilter = room.isActive
                            case .friends: matchesFilter = friendNames.contains(room.hostName.lowercased())
                            }
                            return matchesSearch && matchesFilter
                        }
                        if filteredRail.isEmpty && rs.heroRoom == nil {
                            VStack(spacing: 10) {
                                Image(systemName: searchQuery.isEmpty && roomFilter == .all ? "person.3.sequence.fill" : "magnifyingglass")
                                    .font(.title2)
                                    .foregroundStyle(V4.muted)
                                Text(searchQuery.isEmpty && roomFilter == .all ? "Пока нет активных комнат" : "Ничего не найдено")
                                    .font(.headline)
                                Text(searchQuery.isEmpty && roomFilter == .all ? "Создай первую комнату или войди по коду друга" : "Измени запрос или выбери другой фильтр")
                                    .font(.subheadline)
                                    .foregroundStyle(V4.muted)
                                    .multilineTextAlignment(.center)
                                if searchQuery.isEmpty && roomFilter == .all {
                                    Button("Создать комнату") { createRoom?() }
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
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 11) {
                                    ForEach(filteredRail) { room in
                                        V4MediaCard(
                                            title: room.name,
                                            meta: "\(room.participantCount) участников",
                                            thumbnailURL: room.mediaItem?.thumbnailURL
                                        )
                                    }
                                }.padding(.horizontal, 19)
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
                                createRoom?()
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
}


