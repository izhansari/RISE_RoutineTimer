//
//  GlyphCatalog.swift
//  RISE_RoutineTimer
//
//  The icons offered in the step editor.
//
//  Deliberately curated rather than the whole Unicode emoji set: a routine
//  step is a shower, a stretch, a coffee or a page of notes, and a 1,900-item
//  grid makes those harder to find, not easier. Every entry carries search
//  keywords, so "gym", "lift" and "weights" all land on the same tile.
//
//  The Marks category is typographic rather than pictorial — it fits the
//  receipt/dot-matrix look better than a colour emoji does, for anyone who
//  wants the list to stay monochrome.
//

import Foundation

nonisolated struct Glyph: Identifiable, Equatable {
    let value: String
    let keywords: [String]

    var id: String { value }

    init(_ value: String, _ keywords: String...) {
        self.value = value
        self.keywords = keywords
    }

    func matches(_ query: String) -> Bool {
        let needle = query.lowercased()
        if value == query { return true }
        return keywords.contains { $0.contains(needle) }
    }
}

nonisolated struct GlyphCategory: Identifiable {
    let name: String
    let glyphs: [Glyph]

    var id: String { name }
}

nonisolated enum GlyphCatalog {
    static let categories: [GlyphCategory] = [
        GlyphCategory(name: "Marks", glyphs: [
            Glyph("★", "star", "favourite", "favorite", "mark"),
            Glyph("☆", "star", "outline", "mark"),
            Glyph("●", "dot", "circle", "filled", "bullet"),
            Glyph("○", "circle", "outline", "ring"),
            Glyph("◆", "diamond", "filled"),
            Glyph("◇", "diamond", "outline"),
            Glyph("■", "square", "filled", "block"),
            Glyph("□", "square", "outline", "box"),
            Glyph("▲", "triangle", "up", "arrow"),
            Glyph("▶", "play", "start", "triangle", "right"),
            Glyph("✓", "check", "tick", "done", "complete"),
            Glyph("✕", "cross", "close", "no", "cancel"),
            Glyph("✚", "plus", "add", "cross", "health"),
            Glyph("❖", "diamond", "ornament", "mark"),
            Glyph("➤", "arrow", "next", "right", "go"),
            Glyph("§", "section", "text", "paragraph"),
            Glyph("†", "dagger", "mark"),
            Glyph("°", "degree", "temperature", "heat"),
            Glyph("※", "reference", "note", "mark"),
            Glyph("⌘", "command", "key", "control"),
            Glyph("⚑", "flag", "goal", "target", "milestone"),
            Glyph("☰", "menu", "lines", "list", "bars")
        ]),
        GlyphCategory(name: "Morning", glyphs: [
            Glyph("☀️", "sun", "morning", "day", "sunrise", "light"),
            Glyph("🌅", "sunrise", "morning", "dawn", "sun"),
            Glyph("🌄", "sunrise", "mountain", "morning", "dawn"),
            Glyph("🌙", "moon", "night", "evening", "sleep"),
            Glyph("⏰", "alarm", "clock", "wake", "time", "timer"),
            Glyph("🛏️", "bed", "sleep", "wake", "bedroom"),
            Glyph("😴", "sleep", "tired", "nap", "rest"),
            Glyph("☕", "coffee", "drink", "caffeine", "morning", "cup"),
            Glyph("🍵", "tea", "drink", "matcha", "green", "cup"),
            Glyph("💧", "water", "drink", "hydrate", "droplet"),
            Glyph("🥤", "drink", "shake", "smoothie", "cup", "water"),
            Glyph("🚿", "shower", "wash", "bathe", "clean"),
            Glyph("🛁", "bath", "bathe", "soak", "wash"),
            Glyph("🪥", "toothbrush", "teeth", "brush", "dental", "wash"),
            Glyph("🧼", "soap", "wash", "clean", "hands"),
            Glyph("🧴", "lotion", "skincare", "moisturise", "moisturize", "cream"),
            Glyph("🪒", "shave", "razor", "groom"),
            Glyph("💊", "pill", "medicine", "vitamin", "supplement"),
            Glyph("🧻", "paper", "bathroom", "toilet")
        ]),
        GlyphCategory(name: "Body", glyphs: [
            Glyph("🧘", "stretch", "yoga", "meditate", "calm", "breathe"),
            Glyph("🏃", "run", "jog", "cardio", "exercise", "running"),
            Glyph("🚶", "walk", "steps", "stroll", "exercise"),
            Glyph("🏋️", "gym", "lift", "weights", "strength", "workout"),
            Glyph("🤸", "stretch", "exercise", "mobility", "cartwheel", "workout"),
            Glyph("🚴", "bike", "cycle", "cycling", "cardio", "exercise"),
            Glyph("🏊", "swim", "pool", "cardio", "exercise"),
            Glyph("💪", "strength", "muscle", "gym", "workout", "lift"),
            Glyph("❤️", "heart", "health", "cardio", "love"),
            Glyph("🫁", "lungs", "breathe", "breath", "breathing"),
            Glyph("🦷", "teeth", "tooth", "dental", "brush"),
            Glyph("🥗", "salad", "food", "eat", "healthy", "meal", "lunch"),
            Glyph("🍳", "breakfast", "egg", "cook", "food", "eat", "meal"),
            Glyph("🍎", "apple", "fruit", "food", "eat", "snack"),
            Glyph("🥣", "cereal", "breakfast", "bowl", "food", "eat", "oats")
        ]),
        GlyphCategory(name: "Mind", glyphs: [
            Glyph("📝", "notes", "write", "journal", "plan", "todo"),
            Glyph("✍️", "write", "journal", "notes", "handwriting"),
            Glyph("📖", "read", "book", "reading", "study"),
            Glyph("📚", "books", "read", "study", "learn"),
            Glyph("🧠", "brain", "mind", "think", "focus", "learn"),
            Glyph("💭", "think", "thought", "reflect", "mind"),
            Glyph("🙏", "pray", "prayer", "gratitude", "thanks", "meditate"),
            Glyph("📿", "prayer", "beads", "meditate", "rosary", "dhikr"),
            Glyph("🕌", "mosque", "prayer", "salah", "worship"),
            Glyph("🎧", "headphones", "music", "listen", "podcast", "audio"),
            Glyph("🎵", "music", "song", "listen", "audio"),
            Glyph("🗒️", "notepad", "notes", "list", "plan", "todo"),
            Glyph("🧩", "puzzle", "problem", "think", "focus")
        ]),
        GlyphCategory(name: "Work", glyphs: [
            Glyph("💻", "laptop", "work", "computer", "code", "desk"),
            Glyph("⌨️", "keyboard", "type", "work", "code"),
            Glyph("🖥️", "desktop", "computer", "work", "monitor", "screen"),
            Glyph("📊", "chart", "data", "report", "work", "review", "stats"),
            Glyph("📈", "growth", "chart", "progress", "up", "review", "stats"),
            Glyph("📅", "calendar", "schedule", "plan", "day", "agenda"),
            Glyph("✅", "done", "check", "complete", "task", "todo"),
            Glyph("📌", "pin", "important", "note", "task"),
            Glyph("🗂️", "files", "organise", "organize", "folder", "admin"),
            Glyph("📧", "email", "inbox", "mail", "message"),
            Glyph("📱", "phone", "mobile", "screen", "device"),
            Glyph("⚙️", "settings", "setup", "config", "admin", "gear"),
            Glyph("💰", "money", "finance", "budget", "cash")
        ]),
        GlyphCategory(name: "Home", glyphs: [
            Glyph("🏠", "home", "house", "tidy"),
            Glyph("🧹", "sweep", "clean", "tidy", "broom", "chores"),
            Glyph("🧺", "laundry", "washing", "clothes", "chores", "basket"),
            Glyph("🍽️", "dishes", "wash", "kitchen", "chores", "plate", "eat"),
            Glyph("🗑️", "bin", "trash", "rubbish", "chores", "waste"),
            Glyph("🛒", "shopping", "groceries", "store", "errand"),
            Glyph("🪴", "plant", "water", "garden", "houseplant"),
            Glyph("🐕", "dog", "walk", "pet", "animal"),
            Glyph("🐈", "cat", "pet", "feed", "animal"),
            Glyph("👔", "dress", "clothes", "shirt", "getready", "outfit"),
            Glyph("👟", "shoes", "trainers", "sneakers", "getready", "run"),
            Glyph("🎒", "bag", "pack", "backpack", "getready", "school"),
            Glyph("🔑", "keys", "lock", "leave", "getready"),
            Glyph("🚗", "car", "drive", "commute", "leave", "travel"),
            Glyph("🚌", "bus", "commute", "transit", "travel")
        ])
    ]

    /// Categories filtered by a search query, empty ones dropped.
    static func filtered(by query: String) -> [GlyphCategory] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return categories }
        return categories.compactMap { category in
            let hits = category.glyphs.filter { $0.matches(trimmed) }
            return hits.isEmpty ? nil : GlyphCategory(name: category.name, glyphs: hits)
        }
    }
}
