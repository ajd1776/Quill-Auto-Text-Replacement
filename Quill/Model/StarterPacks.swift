import Foundation

/// Built-in sets of snippets, each added as its own group that can be switched off or removed.
struct StarterPack: Identifiable {
    let id: String
    let name: String
    let summary: String
    let icon: String
    let color: GroupColor
    let mode: ExpansionMode
    let matchesAnyCase: Bool
    let entries: [(trigger: String, text: String)]

    static let all: [StarterPack] = [emoji, typos, dates]

    static let emoji = StarterPack(
        id: "emoji", name: "Emoji Shortcodes",
        summary: "Type :smile: for 😄, as in Slack and GitHub. Expands as soon as you type the closing colon.",
        icon: "😄", color: .yellow, mode: .immediate, matchesAnyCase: false,
        entries: [
            (":smile:", "😄"), (":grin:", "😁"), (":joy:", "😂"), (":laughing:", "😆"), (":wink:", "😉"),
            (":blush:", "😊"), (":heart_eyes:", "😍"), (":cool:", "😎"), (":thinking:", "🤔"), (":smirk:", "😏"),
            (":sob:", "😭"), (":shrug:", "🤷"), (":facepalm:", "🤦"), (":eyes:", "👀"), (":wave:", "👋"),
            (":thumbsup:", "👍"), (":thumbsdown:", "👎"), (":ok:", "👌"), (":clap:", "👏"), (":pray:", "🙏"),
            (":muscle:", "💪"), (":heart:", "❤️"), (":purple_heart:", "💜"), (":fire:", "🔥"), (":sparkles:", "✨"),
            (":star:", "⭐️"), (":tada:", "🎉"), (":rocket:", "🚀"), (":100:", "💯"), (":check:", "✅"),
            (":x:", "❌"), (":warning:", "⚠️"), (":bulb:", "💡"), (":memo:", "📝"), (":calendar:", "📅"),
            (":phone:", "📱"), (":mail:", "📧"), (":lock:", "🔒"), (":key:", "🔑"), (":money:", "💰"),
            (":box:", "📦"), (":truck:", "🚚"), (":gift:", "🎁"), (":coffee:", "☕️"), (":pizza:", "🍕"),
            (":beer:", "🍺"), (":uk:", "🇬🇧"), (":arrow:", "→"),
        ]
    )

    static let typos = StarterPack(
        id: "typos", name: "Typo Fixes",
        summary: "Fixes common misspellings as you type, such as teh → the and recieve → receive. Matches any capitals.",
        icon: "✏️", color: .green, mode: .afterDelimiter, matchesAnyCase: true,
        entries: [
            ("teh", "the"), ("adn", "and"), ("hte", "the"), ("taht", "that"), ("thier", "their"),
            ("recieve", "receive"), ("recieved", "received"), ("seperate", "separate"), ("definately", "definitely"),
            ("occured", "occurred"), ("untill", "until"), ("wich", "which"), ("becuase", "because"), ("beleive", "believe"),
            ("accomodate", "accommodate"), ("acheive", "achieve"), ("adress", "address"), ("alot", "a lot"),
            ("arguement", "argument"), ("begining", "beginning"), ("calender", "calendar"), ("commited", "committed"),
            ("concious", "conscious"), ("embarass", "embarrass"), ("enviroment", "environment"), ("existance", "existence"),
            ("foriegn", "foreign"), ("freind", "friend"), ("goverment", "government"), ("grammer", "grammar"),
            ("happend", "happened"), ("independant", "independent"), ("knowlege", "knowledge"), ("liason", "liaison"),
            ("neccessary", "necessary"), ("noticable", "noticeable"), ("occassion", "occasion"), ("posession", "possession"),
            ("prefered", "preferred"), ("publically", "publicly"), ("realy", "really"), ("reccomend", "recommend"),
            ("refered", "referred"), ("relevent", "relevant"), ("sucess", "success"), ("suprise", "surprise"),
            ("tommorow", "tomorrow"), ("truely", "truly"), ("wierd", "weird"), ("doesnt", "doesn't"),
            ("didnt", "didn't"), ("isnt", "isn't"), ("wasnt", "wasn't"), ("couldnt", "couldn't"), ("shouldnt", "shouldn't"),
        ]
    )

    static let dates = StarterPack(
        id: "dates", name: "Dates and Times",
        summary: "Today's date and time in common formats, such as ;dmy → 18/11/2026 and ;day → Wednesday.",
        icon: "📅", color: .blue, mode: .afterDelimiter, matchesAnyCase: false,
        entries: [
            (";td", "{date}"), (";tm", "{time}"), (";now", "{date} at {time}"),
            (";dmy", "{date:dd/MM/yyyy}"), (";mdy", "{date:MM/dd/yyyy}"), (";iso", "{date:yyyy-MM-dd}"),
            (";day", "{date:EEEE}"), (";month", "{date:MMMM}"), (";yr", "{date:yyyy}"), (";ts", "{date:yyyy-MM-dd HH:mm}"),
        ]
    )
}

extension SnippetStore {
    func installedGroup(for pack: StarterPack) -> SnippetGroup? {
        groups.first { $0.packID == pack.id }
    }

    /// Adds the pack as a new group, skipping shortcuts you already have. Returns how many were added.
    @discardableResult
    func install(_ pack: StarterPack) -> Int {
        guard installedGroup(for: pack) == nil else { return 0 }
        var group = SnippetGroup(name: pack.name, color: pack.color, symbol: pack.icon)
        group.packID = pack.id
        group.isExpanded = false
        let snippets: [Snippet] = pack.entries.compactMap { entry in
            guard !containsTrigger(entry.trigger) else { return nil }
            var snippet = Snippet(trigger: entry.trigger, expansion: entry.text)
            snippet.groupID = group.id
            snippet.mode = pack.mode
            snippet.matchesAnyCase = pack.matchesAnyCase
            // Quiet by default: an effect on every typo fix or emoji gets tiring.
            snippet.animation = .instant
            return snippet
        }
        groups.append(group)
        add(contentsOf: snippets)
        return snippets.count
    }

    func uninstall(_ pack: StarterPack) {
        guard let group = installedGroup(for: pack) else { return }
        deleteGroup(group.id, keepingSnippets: false)
    }
}
