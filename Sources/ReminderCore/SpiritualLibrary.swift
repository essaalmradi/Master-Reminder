import Foundation

public enum AppResources {
    public static let bundle: Bundle = {
        #if os(macOS)
        if Bundle.main.bundleURL.pathExtension == "app" {
            // SwiftPM's CLI accessor searches beside the app, then its absolute
            // build directory. Installed macOS apps keep bundles in Resources.
            // Never evaluate that fatal build-path fallback inside a .app.
            return installedBundle(in: Bundle.main) ?? Bundle.main
        }
        #endif
        return Bundle.module
    }()
    static func installedBundle(in application: Bundle) -> Bundle? {
        guard let resources = application.resourceURL else { return nil }
        return Bundle(url: resources.appendingPathComponent("MasterReminder_ReminderCore.bundle", isDirectory: true))
    }
    public static func url(_ name: String, _ ext: String) -> URL? {
        bundle.url(forResource: name, withExtension: ext)
    }
}

public enum SpiritualCategory: String, CaseIterable, Identifiable {
    case dhikr, dua, quran, hadith, tasbih, prayer, custom
    public var id: String { rawValue }
    public var type: ReminderType { ReminderType(rawValue: rawValue) ?? .custom }
    public var title: String {
        switch self {
        case .dhikr: return "أذكار"
        case .dua: return "أدعية"
        case .quran: return "قرآن كريم"
        case .hadith: return "أحاديث نبوية"
        case .tasbih: return "تسبيح"
        case .prayer: return "صلاة وأذان"
        case .custom: return "تذكير مخصص"
        }
    }
    public var subtitle: String {
        switch self {
        case .dhikr: return "الصباح، المساء، ومواقف يومك"
        case .dua: return "دعوة تجعل للقلب متّسعًا"
        case .quran: return "آية تقرؤها وتتدبرها"
        case .hadith: return "من هدي النبي ﷺ"
        case .tasbih: return "لحظة ذكر مع عدّادك"
        case .prayer: return "اضبط وقت الصلاة وتنبيهها"
        case .custom: return "اكتب ما تريد أن تتذكره"
        }
    }
}

public struct LibraryEntry: Codable, Identifiable, Equatable {
    public let id: String
    public let category: String
    public let title: String
    public let text: String
    public let reference: String
    public let sourceURL: String
    public let repetitions: Int
    public let chapter: Int
    public var audioURL: String? = nil
    public var bundledAudio: String? = nil
    public var type: ReminderType { ReminderType(rawValue: category) ?? .dhikr }
    public var reminder: Reminder {
        var value = Reminder(title: title, date: Date().addingTimeInterval(3600))
        value.type = type; value.detail = text + "\n\n" + reference
        value.preAlertMinutes = 0; value.repeatRule = .daily
        if bundledAudio != nil { value.sound = .dhikr }
        return value
    }
}

public struct SurahInfo: Codable, Identifiable {
    public let number: Int
    public let name: String
    public var id: Int { number }
}

public final class SpiritualLibrary {
    public static let shared = SpiritualLibrary()
    public private(set) var entries: [LibraryEntry] = []
    public private(set) var surahs: [SurahInfo] = []
    public private(set) var loadError: String?
    private var searchIndex: [String: String] = [:]
    private var byID: [String: LibraryEntry] = [:]
    public init() {
        do {
            func read(_ name: String, _ ext: String) throws -> Data {
                guard let url = AppResources.url(name, ext) else { throw DataError.invalidData }
                return try Data(contentsOf: url)
            }
            surahs = try JSONDecoder().decode([SurahInfo].self, from: read("surahs", "json"))
            entries = try JSONDecoder().decode([LibraryEntry].self, from: read("library", "json"))
            let names = Dictionary(uniqueKeysWithValues: surahs.map { ($0.number, $0.name) })
            let raw = try String(decoding: read("quran-tanzil", "txt"), as: UTF8.self)
            var verses: [LibraryEntry] = []
            for line in raw.components(separatedBy: .newlines) {
                let parts = line.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
                guard parts.count == 3, let chapter = Int(parts[0]), let verse = Int(parts[1]) else { continue }
                verses.append(LibraryEntry(id: "quran-\(chapter)-\(verse)", category: "quran",
                    title: "\(names[chapter] ?? "") · الآية \(verse)", text: String(parts[2]),
                    reference: "سورة \(names[chapter] ?? "") · \(chapter):\(verse) · مشروع تنزيل",
                    sourceURL: "https://tanzil.net/#\(chapter):\(verse)", repetitions: 1, chapter: chapter))
            }
            guard verses.count == 6236, surahs.count == 114, entries.count == 309 else { throw DataError.invalidData }
            entries.append(contentsOf: verses)
            guard Set(entries.map(\.id)).count == entries.count else { throw DataError.invalidData }
            byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
            searchIndex = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, Self.searchKey($0.title + " " + $0.text + " " + $0.reference)) })
        } catch { entries = []; loadError = "تعذّر تحميل المكتبة. أعد تثبيت التطبيق لاستعادة ملفات المحتوى." }
    }
    public func entry(_ id: String) -> LibraryEntry? { byID[id] }
    public func search(_ query: String, category: SpiritualCategory? = nil, chapter: Int? = nil) -> [LibraryEntry] {
        let key = Self.searchKey(query)
        return entries.filter {
            (category == nil || $0.category == category!.rawValue) &&
            (chapter == nil || $0.chapter == chapter) &&
            (key.isEmpty || searchIndex[$0.id, default: ""].contains(key))
        }
    }
    public func dailyVerse(at date: Date = Date()) -> LibraryEntry? {
        let ids = ["quran-13-28", "quran-94-5", "quran-94-6", "quran-20-114", "quran-2-152", "quran-93-5", "quran-55-60"]
        let day = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        return entry(ids[day % ids.count])
    }
    public func dailyDhikr(at date: Date = Date()) -> LibraryEntry? {
        let choices = entries.filter { $0.category == "dhikr" && $0.text.count < 95 && $0.text.count > 25 }
        guard !choices.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        return choices[day % choices.count]
    }
    public var audioSample: LibraryEntry? { entries.first { $0.bundledAudio != nil } }
    public static func searchKey(_ value: String) -> String {
        let bare = value.unicodeScalars.filter { !CharacterSet.nonBaseCharacters.contains($0) && $0.value != 0x640 }
        return String(String.UnicodeScalarView(bare)).lowercased()
            .replacingOccurrences(of: "أ", with: "ا").replacingOccurrences(of: "إ", with: "ا")
            .replacingOccurrences(of: "آ", with: "ا").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
