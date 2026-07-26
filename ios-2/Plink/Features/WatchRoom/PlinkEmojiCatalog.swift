//  PlinkEmojiCatalog.swift
//  Plink
//
//  Auto-generated catalog of 5 Plink+ emoji packs (81 emojis total).
//  Source: plink_emoji_packs.zip (user-provided custom art).
//

import SwiftUI
import Foundation

// MARK: - Plink+ Emoji Catalog (5 packs, 81 emojis)

enum PlinkEmojiCatalog {
    /// All 5 Plink+ custom emoji packs (premium only)
    static let premiumPacks: [EmojiPack] = [
        EmojiPack(
            name: "Cute Faces",
            emojis: [
                "1403-owo", "34080-oh", "34904-shy", "4208-sup-shawty",
                "4496-embarassed", "45654-staring", "5181-munching",
                "57751-pat-pat-give", "6687-emoji-confused", "6912-emoji-sleepy",
                "8036-blehhh", "8237-owono", "8468-emoji-murder", "8596-petpetemoji",
                "9288-emoji-birthdayhat", "93422-zooted", "9732-awwemojix",
                "9848-inlovehearts", "1217-emoji-knife", "22981-loading",
                "2695-rainboarf", "3090-cursedemojieepy", "3123-sighh",
                "3380-emoji-pleadcat", "10870-cuteemojiwithcat", "4990-explainthisshit",
                "10221-12",
                // GIF animated
                "8714-take-my-loverainbow",
            ],
            isPremium: true
        ),
        EmojiPack(
            name: "Pepe",
            emojis: [
                "830563-pepe", "383141-pepesmile", "149743-pepeheart",
                "120458-pepecross", "182109-pepeperfect", "236705-pepedumb",
                "304977-pepehang", "543336-pepescream", "583748-pepeooo",
                "618704-pepeokay", "702336-kingpepe", "733150-kingpepe",
                "798781-nou", "877975-praypepe",
                // GIF animated
                "121023-pepetyping", "175472-pepelaugh", "249299-strongpepe",
                "431882-pepeclap", "436131-pepetorchfire", "588971-pepeuwu",
                "690612-pepelmao", "827729-peperain", "828203-peperich",
                "950522-pepehacker",
            ],
            isPremium: true
        ),
        EmojiPack(
            name: "Stickers",
            emojis: [
                "18038-wassup", "440174-redcard", "455353-inlove",
                "501481-nobrain", "502259-downvote",
                "549205-lickingscreen", "559934-approve", "600559-glasses",
                "67803-hungry", "767943-give", "77254-gunpoint",
                "794547-fight", "980819-moneyhands",
            ],
            isPremium: true
        ),
        EmojiPack(
            name: "Cats",
            emojis: [
                "129403-flowersforyou", "233828-stinky", "486800-plotting",
                "563716-sadqueen", "617091-peace", "736199-ring",
            ],
            isPremium: true
        ),
        EmojiPack(
            name: "Le Pepe",
            emojis: [
                "3439-pepe-blushy", "370700-pepe-sad", "477732-pepehug",
                "638973-pepes", "733056-sleepypepe", "857990-pepohappy",
                // GIF animated
                "47945-pepe-hehe",
            ],
            isPremium: true
        ),
    ]

    /// All available packs (standard + premium)
    /// Standard packs (Reactions, Plink+, Fun) are SF Symbol-based — kept for back-compat.
    /// Premium packs (Cute Faces, Pepe, Stickers, Cats, Le Pepe) use custom PNG/GIF art.
    static let allPacks: [EmojiPack] = [
        // Existing SF Symbol packs (free + premium)
        EmojiPack(name: "Reactions", emojis: [
            "emoji_laugh", "emoji_fire", "emoji_heart", "emoji_thumbs_up",
            "emoji_thumbs_down", "emoji_scream", "emoji_cry", "emoji_love",
            "emoji_think", "emoji_cool", "emoji_party", "emoji_angry",
            "emoji_sad", "emoji_wow", "emoji_sleepy", "emoji_clap",
            "emoji_pray", "emoji_ok", "emoji_poop", "emoji_flex",
        ], isPremium: false),
        EmojiPack(name: "Plink+", emojis: [
            "emoji_neon_laugh", "emoji_neon_fire", "emoji_neon_heart",
            "emoji_neon_thumbs_up", "emoji_neon_party", "emoji_neon_cool",
            "emoji_neon_wow", "emoji_neon_clap",
        ], isPremium: true),
        EmojiPack(name: "Fun", emojis: [
            "emoji_popcorn", "emoji_movie", "emoji_clapper", "emoji_director",
            "emoji_oscar", "emoji_ticket", "emoji_film", "emoji_camera",
        ], isPremium: true),
    ] + premiumPacks

    /// Pack directory name for filesystem lookup
    /// (EmojiAssetImage loads from Resources/Emojis/{packDir}/)
    static func packDirectory(for packName: String) -> String {
        switch packName {
        case "Reactions": return "reactions"
        case "Plink+": return "plinkplus"
        case "Fun": return "fun"
        case "Cute Faces": return "cute-faces"
        case "Pepe": return "pepe"
        case "Stickers": return "emojis"
        case "Cats": return "cat"
        case "Le Pepe": return "ze-frog-es-le-pepe"
        default: return packName.lowercased().replacingOccurrences(of: " ", with: "-")
        }
    }

    /// Whether a pack uses custom PNG art (vs SF Symbol renders)
    static func usesCustomArt(_ packName: String) -> Bool {
        return ["Cute Faces", "Pepe", "Stickers", "Cats", "Le Pepe", "Plink+", "Fun", "Reactions"].contains(packName)
            && packName != "Базовые" && packName != "Кино"
    }

    // MARK: - DM packs (unicode free + Plink+ art)

    /// Free unicode set for friend chat
    static let freeUnicodePack = EmojiPack(
        name: "Базовые",
        emojis: [
            "😀", "😂", "😍", "🥰", "😘", "🤗", "🤔", "🤩", "🥳", "😭",
            "😱", "🤯", "👍", "👎", "👏", "🙌", "🤝", "💪", "❤️", "🔥",
            "✨", "🎉", "💯", "⚡", "🌟", "💎", "👑", "🚀", "🌈", "🎬",
            "😎", "🥺", "😅", "🤣", "😈", "👻", "💀", "🫡", "😴", "🤮",
        ],
        isPremium: false
    )

    /// Free cinema-ish unicode
    static let cinemaUnicodePack = EmojiPack(
        name: "Кино",
        emojis: ["🎬", "🍿", "🎥", "📽️", "🎞️", "🎫", "🏆", "🎭", "📺", "🎧", "🎤", "🎶"],
        isPremium: false
    )

    /// All packs shown in friend DM emoji picker
    static var dmAllPacks: [EmojiPack] {
        [freeUnicodePack, cinemaUnicodePack] + allPacks
    }

    // Token format in messages: :pack/name:
    // Example: :Plink+/emoji_neon_laugh:  or  :Pepe/830563-pepe:
    static func encodeToken(pack: String, name: String) -> String {
        let p = pack.replacingOccurrences(of: ":", with: "")
        let n = name.replacingOccurrences(of: ":", with: "")
        return ":\(p)/\(n):"
    }

    static func isCustomArtToken(_ s: String) -> Bool {
        s.hasPrefix(":") && s.hasSuffix(":") && s.contains("/")
    }

    enum MessagePart: Equatable {
        case text(String)
        case custom(pack: String, name: String)
    }

    /// Split message into plain text and custom emoji tokens.
    static func splitMessage(_ text: String) -> [MessagePart] {
        // Pattern: :Pack Name/emoji-id:
        guard let regex = try? NSRegularExpression(
            pattern: #":([^:/]+)/([^:]+):"#,
            options: []
        ) else {
            return [.text(text)]
        }
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        let matches = regex.matches(in: text, options: [], range: full)
        guard !matches.isEmpty else { return [.text(text)] }

        var parts: [MessagePart] = []
        var cursor = 0
        for m in matches {
            if m.range.location > cursor {
                let t = ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
                if !t.isEmpty { parts.append(.text(t)) }
            }
            let pack = ns.substring(with: m.range(at: 1))
            let name = ns.substring(with: m.range(at: 2))
            parts.append(.custom(pack: pack, name: name))
            cursor = m.range.location + m.range.length
        }
        if cursor < ns.length {
            let t = ns.substring(from: cursor)
            if !t.isEmpty { parts.append(.text(t)) }
        }
        return parts.isEmpty ? [.text(text)] : parts
    }
}
