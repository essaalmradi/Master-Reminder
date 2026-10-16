import Foundation

public struct ReminderAudio: Codable, Equatable {
    public var recordingID: String? = nil
    public var libraryEntryID: String? = nil
    public var reciterID: String? = nil
    public var voiceIdentifier: String? = nil
    public var spokenText: String? = nil
    public var volume: Double? = nil
    public init() {}
    public var isValid: Bool {
        [recordingID, libraryEntryID, reciterID, voiceIdentifier].compactMap { $0 }.allSatisfy { $0.count <= 200 } &&
        (spokenText?.count ?? 0) <= 4000 && (volume == nil || (volume!.isFinite && (0...1).contains(volume!)))
    }
}

public struct QuranReciter: Identifiable {
    public let id: String
    public let name: String
    public let directory: String
}
public struct AudioRecording: Identifiable {
    public let id: String
    public let title: String
    public let url: URL
    public let sourceURL: URL
}
public enum AudioCatalog {
    public static let reciters: [QuranReciter] = [
        .init(id: "alafasy", name: "مشاري راشد العفاسي", directory: "Alafasy_128kbps"),
        .init(id: "husary", name: "محمود خليل الحصري", directory: "Husary_128kbps"),
        .init(id: "minshawi", name: "محمد صديق المنشاوي", directory: "Minshawy_Murattal_128kbps"),
        .init(id: "maher", name: "ماهر المعيقلي", directory: "MaherAlMuaiqly128kbps"),
        .init(id: "abdulbasit", name: "عبد الباسط عبد الصمد · مرتّل", directory: "Abdul_Basit_Murattal_192kbps"),
        .init(id: "sudais", name: "عبد الرحمن السديس", directory: "Abdurrahmaan_As-Sudais_192kbps")
    ]
    public static let adhans: [AudioRecording] = [
        adhan("alafasy", "مشاري راشد العفاسي", "a9"),
        adhan("nafees", "أحمد النفيس", "a1"),
        adhan("zahrani", "منصور الزهراني", "a11-mansour-al-zahrani"),
        adhan("mustafa", "مصطفى أوزجان", "a2")
    ]
    private static func adhan(_ id: String, _ title: String, _ file: String) -> AudioRecording {
        .init(id: id, title: title, url: URL(string: "https://cdn.aladhan.com/audio/adhans/\(file).mp3")!, sourceURL: URL(string: "https://aladhan.com/download-adhans")!)
    }
    public static func recording(for reminder: Reminder) throws -> AudioRecording? {
        switch reminder.sound {
        case .adhan:
            guard let item = adhans.first(where: { $0.id == reminder.audio?.recordingID }) else { throw AudioSelectionError.chooseMuezzin }
            return item
        case .quran:
            guard let id = reminder.audio?.libraryEntryID, let entry = SpiritualLibrary.shared.entry(id), entry.category == "quran" else { throw AudioSelectionError.chooseVerse }
            guard let reciter = reciters.first(where: { $0.id == reminder.audio?.reciterID }) else { throw AudioSelectionError.chooseReciter }
            let parts = id.split(separator: "-")
            guard parts.count == 3, let surah = Int(parts[1]), let ayah = Int(parts[2]) else { throw AudioSelectionError.chooseVerse }
            let file = String(format: "%03d%03d", surah, ayah)
            return .init(id: "\(reciter.id)-\(file)", title: "\(reciter.name) · \(entry.title)",
                         url: URL(string: "https://everyayah.com/data/\(reciter.directory)/\(file).mp3")!, sourceURL: URL(string: "https://everyayah.com/recitations_ayat.html")!)
        case .library:
            guard let id = reminder.audio?.libraryEntryID, let entry = SpiritualLibrary.shared.entry(id),
                  let raw = entry.audioURL, let url = URL(string: raw), url.scheme == "https" else { throw AudioSelectionError.chooseRecording }
            return .init(id: entry.id, title: "حمد الدريهم · \(entry.title)", url: url, sourceURL: URL(string: "https://github.com/rn0x/Adhkar-json")!)
        default: return nil
        }
    }
    public static func choices(for reminder: Reminder) -> [SoundChoice] {
        var choices: [SoundChoice] = [.none]
        if reminder.type == .prayer { choices.append(.adhan) }
        if reminder.type == .quran { choices.append(.quran) }
        if [.dhikr, .dua, .tasbih].contains(reminder.type) || reminder.audio?.libraryEntryID.flatMap({ SpiritualLibrary.shared.entry($0)?.audioURL }) != nil { choices.append(.library) }
        if reminder.type != .quran && reminder.type != .prayer { choices.append(.speech) }
        choices += [.custom, .default, .bell, .soft, .dhikr]
        if !choices.contains(reminder.sound) { choices.append(reminder.sound) }
        return choices
    }
    public static func summary(_ reminder: Reminder) -> String {
        if let recording = try? recording(for: reminder) { return recording.title }
        return reminder.sound.title
    }
    public static func suggestedSound(for reminder: Reminder) -> SoundChoice {
        if reminder.type == .prayer { return .adhan }
        if reminder.type == .quran { return .quran }
        if let id = reminder.audio?.libraryEntryID, SpiritualLibrary.shared.entry(id)?.audioURL != nil { return .library }
        return .speech
    }
}
public enum AudioSelectionError: LocalizedError {
    case chooseMuezzin, chooseVerse, chooseReciter, chooseRecording, missingDownload, noVoice, emptyText, downloadFailed, invalidAudio
    public var errorDescription: String? {
        switch self {
        case .chooseMuezzin: return "اختر المؤذّن أولًا."
        case .chooseVerse: return "اختر الآية من المكتبة لربط التلاوة بالنص الصحيح."
        case .chooseReciter: return "اختر القارئ أولًا."
        case .chooseRecording: return "اختر الذكر أو الدعاء من المكتبة لربط تسجيله بالتذكير."
        case .missingDownload: return "الصوت غير محفوظ على الجهاز. افتح التذكير واختر الصوت ثم احفظه."
        case .noVoice: return "لا يوجد صوت عربي متاح. أضف صوتًا عربيًا من إعدادات تسهيلات الاستخدام في macOS، أو اختر ملفًا صوتيًا."
        case .emptyText: return "اكتب النص الذي تريد سماعه."
        case .downloadFailed: return "تعذّر تنزيل الصوت. تحقق من الإنترنت وحاول مجددًا؛ لم يتم حفظ تغيير الصوت."
        case .invalidAudio: return "ملف الصوت غير صالح أو حجمه أكبر من 50 MB."
        }
    }
}
