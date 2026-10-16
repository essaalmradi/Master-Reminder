import SwiftUI
import AVFoundation
import ReminderCore

@MainActor public final class AudioPreview: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published public private(set) var isPlaying = false
    @Published public private(set) var message: String?
    private var local: AVAudioPlayer?
    private var remote: AVPlayer?
    private var status: NSKeyValueObservation?
    private var endToken: NSObjectProtocol?
    public override init() { super.init() }
    public func play(_ entry: LibraryEntry) {
        stop(); message = nil
        #if os(iOS)
        do { try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio); try AVAudioSession.sharedInstance().setActive(true) }
        catch { message = error.localizedDescription; return }
        #endif
        if let name = entry.bundledAudio, let url = AppResources.url(name, "mp3") {
            do { let player = try AVAudioPlayer(contentsOf: url); player.delegate = self; local = player; isPlaying = player.play() }
            catch { message = "تعذّر تشغيل التسجيل." }
        } else if let raw = entry.audioURL, let url = URL(string: raw), url.scheme == "https" {
            message = "جارٍ تحميل التسجيل…"
            let item = AVPlayerItem(url: url); let player = AVPlayer(playerItem: item); remote = player
            status = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
                Task { @MainActor in
                    guard self?.remote?.currentItem === item else { return }
                    if item.status == .failed { self?.message = "تعذّر تحميل التسجيل. تحقق من الإنترنت وحاول مجددًا."; self?.isPlaying = false }
                    if item.status == .readyToPlay { self?.message = "تسجيل حصن المسلم"; self?.isPlaying = true }
                }
            }
            endToken = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.stop() }
            }
            player.play(); isPlaying = true
        } else { message = "لا يتوفر تسجيل لهذا النص في هذه النسخة." }
    }
    public func stop() {
        local?.stop(); remote?.pause(); local = nil; remote = nil; status = nil
        if let endToken { NotificationCenter.default.removeObserver(endToken) }; endToken = nil; isPlaying = false
    }
    nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.isPlaying = false }
    }
}

public struct LibraryBrowser: View {
    @Environment(\.colorScheme) private var scheme
    @State private var query = ""
    @State private var category: SpiritualCategory?
    @State private var chapter = 0
    @State private var selected: LibraryEntry?
    @State private var limit = 60
    @State private var favoritesOnly = false
    @AppStorage("library-favorites-v1") private var favorites = ""
    private let fixedCategory: SpiritualCategory?
    private let onAdd: (LibraryEntry) -> Void
    private let library = SpiritualLibrary.shared
    public init(category: SpiritualCategory? = nil, onAdd: @escaping (LibraryEntry) -> Void) {
        self.fixedCategory = category; self.onAdd = onAdd; _category = State(initialValue: category)
    }
    private var favoriteSet: Set<String> { Set(favorites.split(separator: "|").map(String.init)) }
    private var results: [LibraryEntry] {
        library.search(query, category: category, chapter: category == .quran && chapter > 0 ? chapter : nil)
            .filter { !favoritesOnly || favoriteSet.contains($0.id) }
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("ابحث بكلمة، أو باسم سورة، أو باب…", text: $query).textFieldStyle(.plain).font(Brand.font(16))
                if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain) }
            }.padding(14).background(Brand.panel(scheme), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Brand.line(scheme)))
            if fixedCategory == nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterChip("الكل", active: category == nil) { category = nil; chapter = 0 }
                        ForEach(SpiritualCategory.allCases.filter { $0 != .prayer && $0 != .custom }) { item in
                            filterChip(item.title, active: category == item) { category = item; chapter = 0 }
                        }
                    }
                }
            }
            HStack {
                if category == .quran {
                    Picker("السورة", selection: $chapter) {
                        Text("كل السور").tag(0)
                        ForEach(library.surahs) { Text("\($0.number). \($0.name)").tag($0.number) }
                    }.frame(maxWidth: 250)
                }
                Text("\(results.count) نص").font(Brand.font(14)).foregroundStyle(.secondary)
                Spacer()
                Button { favoritesOnly.toggle() } label: { Label("المفضلة", systemImage: favoritesOnly ? "heart.fill" : "heart") }
                    .buttonStyle(.plain).foregroundStyle(Brand.accent(scheme))
            }
            if let error = library.loadError { Text(error).font(Brand.font()).foregroundStyle(.red) }
            if results.isEmpty {
                VStack(spacing: 14) { Image(systemName: "book.closed").font(.largeTitle); Text("لا توجد نتائج").font(Brand.font(24)); Text("جرّب كلمة أخرى أو غيّر التصنيف.").font(Brand.font(16)) }
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(Array(results.prefix(limit))) { entry in
                            Button { selected = entry } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: entry.type.symbol).foregroundStyle(Brand.accent(scheme))
                                        Text(entry.title).font(Brand.font(15))
                                        Spacer()
                                        if favoriteSet.contains(entry.id) { Image(systemName: "heart.fill").foregroundStyle(Brand.accent(scheme)) }
                                        Image(systemName: "chevron.left").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Text(entry.text).font(Brand.font(17)).lineSpacing(5).lineLimit(2).multilineTextAlignment(.leading)
                                    Text(entry.reference).font(Brand.font(12)).foregroundStyle(.secondary).lineLimit(1)
                                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Brand.panel(scheme), in: RoundedRectangle(cornerRadius: 18))
                                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Brand.line(scheme).opacity(0.55), lineWidth: 0.7))
                                    .contentShape(RoundedRectangle(cornerRadius: 18))
                            }.buttonStyle(.plain)
                        }
                        if results.count > limit { Button("عرض المزيد") { limit += 60 }.buttonStyle(BrandButton()).padding() }
                    }.padding(.bottom, 12)
                }
            }
        }.font(Brand.font(16)).foregroundStyle(Brand.ink(scheme))
        .onChange(of: query) { _ in limit = 60 }
        .onChange(of: category) { _ in limit = 60 }
        .onChange(of: chapter) { _ in limit = 60 }
        .sheet(item: $selected) { entry in
            LibraryDetail(entry: entry, isFavorite: favoriteSet.contains(entry.id), toggleFavorite: {
                var set = favoriteSet
                if set.contains(entry.id) { set.remove(entry.id) } else { set.insert(entry.id) }
                favorites = set.sorted().joined(separator: "|")
            }, onAdd: {
                selected = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onAdd(entry) }
            })
        }
    }
    private func filterChip(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).font(Brand.font(14)).padding(.horizontal, 16).padding(.vertical, 8)
            .background(active ? Brand.ocean : Brand.panel(scheme), in: Capsule()).foregroundStyle(active ? .white : Brand.ink(scheme))
        }.buttonStyle(.plain)
    }
}

public struct LibraryDetail: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @StateObject private var audio = AudioPreview()
    @State private var favorite: Bool
    let entry: LibraryEntry
    let toggleFavorite: () -> Void
    let onAdd: () -> Void
    public init(entry: LibraryEntry, isFavorite: Bool = false, toggleFavorite: @escaping () -> Void = {}, onAdd: @escaping () -> Void) {
        self.entry = entry; self.toggleFavorite = toggleFavorite; self.onAdd = onAdd; _favorite = State(initialValue: isFavorite)
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text(entry.title).font(Brand.font(24)); Spacer(); Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain) }
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(entry.text).font(Brand.font(25)).lineSpacing(12).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    Divider()
                    Text(entry.reference).font(Brand.font(15)).foregroundStyle(.secondary)
                    if entry.repetitions > 1 { Text("التكرار الوارد في المصدر: \(entry.repetitions)").font(Brand.font(15)) }
                    if let url = URL(string: entry.sourceURL) { Link("اقرأ المصدر", destination: url).font(Brand.font(15)) }
                    if entry.category == "quran" { Text("النص من مشروع تنزيل · محفوظ كما ورد في المصدر").font(Brand.font(13)).foregroundStyle(.secondary) }
                    if entry.audioURL != nil {
                        Button { if audio.isPlaying { audio.stop() } else { audio.play(entry) } } label: {
                            Label(audio.isPlaying ? "إيقاف التسجيل" : (entry.bundledAudio == nil ? "استمع · يحتاج الإنترنت" : "استمع · متاح بدون إنترنت"), systemImage: audio.isPlaying ? "stop.circle" : "play.circle")
                        }.buttonStyle(BrandButton())
                        if let message = audio.message { Text(message).font(Brand.font(13)).foregroundStyle(.secondary) }
                    }
                }.padding(.vertical, 8)
            }
            HStack {
                Button { toggleFavorite(); favorite.toggle() } label: { Label("المفضلة", systemImage: favorite ? "heart.fill" : "heart") }.buttonStyle(.plain)
                Spacer()
                Button("ذكّرني بهذا", action: onAdd).buttonStyle(BrandButton()).disabled(entry.reminder.detail.count > 4000)
            }
            if entry.reminder.detail.count > 4000 { Text("هذا النص طويل للتنبيه. يمكنك قراءته هنا وإضافة تذكير مخصص بعنوانه.").font(Brand.font(13)).foregroundStyle(.secondary) }
        }.padding(28).background(Brand.page(scheme)).environment(\.layoutDirection, .rightToLeft)
        .font(Brand.font()).tint(Brand.ocean)
        #if os(macOS)
        .frame(width: 630, height: 640)
        #endif
        .onDisappear { audio.stop() }
    }
}

public struct TasbihView: View {
    @Environment(\.colorScheme) private var scheme
    @AppStorage("tasbih-session-count") private var count = 0
    @AppStorage("tasbih-total-count") private var total = 0
    @State private var selected = 0
    @State private var reset = false
    private let phrases = ["سبحان الله", "الحمد لله", "الله أكبر", "لا إله إلا الله", "أستغفر الله", "سبحان الله وبحمده"]
    public init() {}
    public var body: some View {
        VStack(spacing: 24) {
            Text("التسبيح").font(Brand.font(27))
            Text("اضغط بهدوء، وخذ وقتك.").font(Brand.font(16)).foregroundStyle(.secondary)
            Picker("الذكر", selection: $selected) { ForEach(phrases.indices, id: \.self) { Text(phrases[$0]).tag($0) } }.font(Brand.font(20)).frame(maxWidth: 320)
            Button { count += 1; total += 1 } label: {
                VStack(spacing: 14) {
                    Text("\(count)").font(Brand.number(64))
                    Text(phrases[selected]).font(Brand.font(23))
                    Image(systemName: "hand.tap").font(.title2)
                }.foregroundStyle(Brand.accent(scheme)).frame(width: 260, height: 260).brandGlass(radius: 130)
            }.buttonStyle(.plain).accessibilityLabel("زيادة عداد التسبيح، العدد الحالي \(count)")
            Text("المجموع على هذا الجهاز: \(total)").font(Brand.font(15)).foregroundStyle(.secondary)
            Button("تصفير الجلسة") { reset = true }.font(Brand.font(15))
            Text("عداد شخصي؛ لا يحدد عددًا تعبديًا ملزمًا.").font(Brand.font(13)).foregroundStyle(.secondary)
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
            .confirmationDialog("تصفير عداد هذه الجلسة؟", isPresented: $reset) { Button("تصفير الجلسة", role: .destructive) { count = 0 } }
    }
}
