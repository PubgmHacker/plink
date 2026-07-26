//  EmojiManifest.kt
//  Plink Android
//
//  Manifest of 5 Plink+ emoji packs (81 emojis total).
//  Source: plink_emoji_packs.zip (user-provided custom art).
//

package com.plink.app.data.models

data class EmojiItem(
    val id: String,
    val name: String,
    val resName: String,  // R.drawable.emoji_xxx
    val animated: Boolean // true for .gif
)

data class EmojiPack(
    val id: String,
    val name: String,
    val premium: Boolean,
    val preview: String,  // preview resource name
    val emojis: List<EmojiItem>
)

object EmojiManifest {

    val packs = listOf(
        // ═══ 1. CUTE FACES (28 emojis) ═══
        EmojiPack(
            id = "cute_faces",
            name = "Cute Faces",
            premium = true,
            preview = "emoji_cute_faces_owo",
            emojis = listOf(
                EmojiItem("owo", "OwO", "emoji_cute_faces_owo", false),
                EmojiItem("oh", "Oh", "emoji_cute_faces_oh", false),
                EmojiItem("shy", "Shy", "emoji_cute_faces_shy", false),
                EmojiItem("sup", "Sup", "emoji_cute_faces_sup_shawty", false),
                EmojiItem("embarrassed", "Embarrassed", "emoji_cute_faces_embarassed", false),
                EmojiItem("staring", "Staring", "emoji_cute_faces_staring", false),
                EmojiItem("munching", "Munching", "emoji_cute_faces_munching", false),
                EmojiItem("pat_pat", "Pat Pat", "emoji_cute_faces_pat_pat_give", false),
                EmojiItem("confused", "Confused", "emoji_cute_faces_emoji_confused", false),
                EmojiItem("sleepy", "Sleepy", "emoji_cute_faces_emoji_sleepy", false),
                EmojiItem("blehhh", "Blehhh", "emoji_cute_faces_blehhh", false),
                EmojiItem("owono", "OwOno", "emoji_cute_faces_owono", false),
                EmojiItem("murder", "Murder", "emoji_cute_faces_emoji_murder", false),
                EmojiItem("petpet", "PetPet", "emoji_cute_faces_petpetemoji", false),
                EmojiItem("birthday", "Birthday", "emoji_cute_faces_emoji_birthdayhat", false),
                EmojiItem("zooted", "Zooted", "emoji_cute_faces_zooted", false),
                EmojiItem("aww", "Aww", "emoji_cute_faces_awwemojix", false),
                EmojiItem("inlove_hearts", "In Love", "emoji_cute_faces_inlovehearts", false),
                EmojiItem("knife", "Knife", "emoji_cute_faces_emoji_knife", false),
                EmojiItem("loading", "Loading", "emoji_cute_faces_loading", false),
                EmojiItem("rainboarf", "Rainbow", "emoji_cute_faces_rainboarf", false),
                EmojiItem("cursed", "Cursed", "emoji_cute_faces_cursedemojieepy", false),
                EmojiItem("sighh", "Sighh", "emoji_cute_faces_sighh", false),
                EmojiItem("pleadcat", "Plead Cat", "emoji_cute_faces_emoji_pleadcat", false),
                EmojiItem("cute_cat", "Cat", "emoji_cute_faces_cuteemojiwithcat", false),
                EmojiItem("explain", "Explain", "emoji_cute_faces_explainthisshit", false),
                EmojiItem("12", "12", "emoji_cute_faces_12", false),
                EmojiItem("rainbow_gif", "Rainbow", "emoji_cute_faces_take_my_loverainbow", true),
            )
        ),

        // ═══ 2. PEPE (24 emojis — 14 PNG + 10 GIF) ═══
        EmojiPack(
            id = "pepe",
            name = "Pepe",
            premium = true,
            preview = "emoji_pepe_pepe",
            emojis = listOf(
                EmojiItem("pepe", "Pepe", "emoji_pepe_pepe", false),
                EmojiItem("smile", "Smile", "emoji_pepe_pepesmile", false),
                EmojiItem("heart", "Heart", "emoji_pepe_pepeheart", false),
                EmojiItem("cross", "Cross", "emoji_pepe_pepecross", false),
                EmojiItem("perfect", "Perfect", "emoji_pepe_pepeperfect", false),
                EmojiItem("dumb", "Dumb", "emoji_pepe_pepedumb", false),
                EmojiItem("hang", "Hang", "emoji_pepe_pepehang", false),
                EmojiItem("scream", "Scream", "emoji_pepe_pepescream", false),
                EmojiItem("ooo", "OOO", "emoji_pepe_pepeooo", false),
                EmojiItem("okay", "Okay", "emoji_pepe_pepeokay", false),
                EmojiItem("king_1", "King", "emoji_pepe_kingpepe", false),
                EmojiItem("king_2", "King 2", "emoji_pepe_kingpepe", false),
                EmojiItem("nou", "NO U", "emoji_pepe_nou", false),
                EmojiItem("pray", "Pray", "emoji_pepe_praypepe", false),
                // GIF animated
                EmojiItem("typing", "Typing", "emoji_pepe_pepetyping", true),
                EmojiItem("laugh", "Laugh", "emoji_pepe_pepelaugh", true),
                EmojiItem("strong", "Strong", "emoji_pepe_strongpepe", true),
                EmojiItem("clap", "Clap", "emoji_pepe_pepeclap", true),
                EmojiItem("torch", "Torch", "emoji_pepe_pepetorchfire", true),
                EmojiItem("uwu", "UwU", "emoji_pepe_pepeuwu", true),
                EmojiItem("lmao", "LMAO", "emoji_pepe_pepelmao", true),
                EmojiItem("rain", "Rain", "emoji_pepe_peperain", true),
                EmojiItem("rich", "Rich", "emoji_pepe_peperich", true),
                EmojiItem("hacker", "Hacker", "emoji_pepe_pepehacker", true),
            )
        ),

        // ═══ 3. STICKERS (16 emojis) ═══
        EmojiPack(
            id = "stickers",
            name = "Stickers",
            premium = true,
            preview = "emoji_emojis_wassup",
            emojis = listOf(
                EmojiItem("wassup", "Wassup", "emoji_emojis_wassup", false),
                EmojiItem("stinky", "Stinky", "emoji_emojis_stinky", false),
                EmojiItem("redcard", "Red Card", "emoji_emojis_redcard", false),
                EmojiItem("inlove", "In Love", "emoji_emojis_inlove", false),
                EmojiItem("plotting", "Plotting", "emoji_emojis_plotting", false),
                EmojiItem("nobrain", "No Brain", "emoji_emojis_nobrain", false),
                EmojiItem("downvote", "Downvote", "emoji_emojis_downvote", false),
                EmojiItem("licking", "Licking", "emoji_emojis_lickingscreen", false),
                EmojiItem("approve", "Approve", "emoji_emojis_approve", false),
                EmojiItem("glasses", "Glasses", "emoji_emojis_glasses", false),
                EmojiItem("peace", "Peace", "emoji_emojis_peace", false),
                EmojiItem("hungry", "Hungry", "emoji_emojis_hungry", false),
                EmojiItem("give", "Give", "emoji_emojis_give", false),
                EmojiItem("gunpoint", "Gunpoint", "emoji_emojis_gunpoint", false),
                EmojiItem("fight", "Fight", "emoji_emojis_fight", false),
                EmojiItem("money", "Money", "emoji_emojis_moneyhands", false),
            )
        ),

        // ═══ 4. CATS (6 emojis) ═══
        EmojiPack(
            id = "cats",
            name = "Cats",
            premium = true,
            preview = "emoji_cat_flowersforyou",
            emojis = listOf(
                EmojiItem("flowers", "Flowers", "emoji_cat_flowersforyou", false),
                EmojiItem("stinky", "Stinky", "emoji_cat_stinky", false),
                EmojiItem("plotting", "Plotting", "emoji_cat_plotting", false),
                EmojiItem("sadqueen", "Sad Queen", "emoji_cat_sadqueen", false),
                EmojiItem("peace", "Peace", "emoji_cat_peace", false),
                EmojiItem("ring", "Ring", "emoji_cat_ring", false),
            )
        ),

        // ═══ 5. LE PEPE (7 emojis — 6 PNG + 1 GIF) ═══
        EmojiPack(
            id = "le_pepe",
            name = "Le Pepe",
            premium = true,
            preview = "emoji_ze_frog_es_le_pepe_pepohappy",
            emojis = listOf(
                EmojiItem("blushy", "Blushy", "emoji_ze_frog_es_le_pepe_pepe_blushy", false),
                EmojiItem("sad", "Sad", "emoji_ze_frog_es_le_pepe_pepe_sad", false),
                EmojiItem("hug", "Hug", "emoji_ze_frog_es_le_pepe_pepehug", false),
                EmojiItem("le_pepes", "Pepes", "emoji_ze_frog_es_le_pepe_pepes", false),
                EmojiItem("sleepy", "Sleepy", "emoji_ze_frog_es_le_pepe_sleepypepe", false),
                EmojiItem("happy", "Happy", "emoji_ze_frog_es_le_pepe_pepohappy", false),
                EmojiItem("hehe", "Hehe", "emoji_ze_frog_es_le_pepe_pepe_hehe", true),
            )
        ),
    )

    // Free standard emojis (unicode)
    val freeEmojis = listOf(
        EmojiItem("👍", "Thumbs Up", "", false),
        EmojiItem("❤️", "Heart", "", false),
        EmojiItem("🔥", "Fire", "", false),
        EmojiItem("😂", "Joy", "", false),
        EmojiItem("😮", "Wow", "", false),
        EmojiItem("😢", "Sad", "", false),
        EmojiItem("🎉", "Party", "", false),
        EmojiItem("💯", "100", "", false),
    )

    val freePack = EmojiPack(
        id = "free",
        name = "Standard",
        premium = false,
        preview = "",
        emojis = freeEmojis,
    )

    val allPacks = listOf(freePack) + packs

    fun findEmoji(id: String): EmojiItem? {
        for (pack in packs) {
            val found = pack.emojis.find { it.id == id }
            if (found != null) return found
        }
        return null
    }
}
