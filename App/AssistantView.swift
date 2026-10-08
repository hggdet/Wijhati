import SwiftUI
import CoreLocation

// MARK: - Arabic local assistant (intent chat over Wijhati's own data)
struct AssistantView: View {
    var userLocation: CLLocationCoordinate2D?
    var onSelectPlace: (Place) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var messages: [AMsg] = [
        AMsg(text: "هلا بيك 👋 آني مساعد وجهتي المحلي. اسألني عن أقرب مكان، الطقس، أو اكتب اسم أي مكان تريده.".loc, user: false, places: nil)
    ]
    @State private var input = ""
    @State private var busy = false

    struct AMsg: Identifiable {
        let id = UUID()
        var text: String
        var user: Bool
        var places: [Place]?
    }

    private let chips: [(label: String, query: String)] = [("أقرب صيدلية", "أقرب صيدلية"), ("أقرب محطة وقود", "أقرب محطة وقود"), ("شنو الطقس؟", "شنو الطقس؟"), ("وين أني؟", "وين أني؟")]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(messages) { msg in
                                VStack(alignment: msg.user ? .trailing : .leading, spacing: 6) {
                                    HStack {
                                        if msg.user { Spacer(minLength: 40) }
                                        Text(msg.text)
                                            .font(.subheadline)
                                            .padding(.horizontal, 12).padding(.vertical, 9)
                                            .background(msg.user ? Color.blue : Color.secondary.opacity(0.14),
                                                        in: RoundedRectangle(cornerRadius: 16))
                                            .foregroundStyle(msg.user ? .white : .primary)
                                        if !msg.user { Spacer(minLength: 40) }
                                    }
                                    if let places = msg.places {
                                        ForEach(places) { place in
                                            Button {
                                                onSelectPlace(place)
                                                dismiss()
                                            } label: {
                                                HStack(spacing: 8) {
                                                    Image(systemName: "mappin.circle.fill").foregroundStyle(adaptiveInk)
                                                    VStack(alignment: .leading, spacing: 1) {
                                                        Text(place.name).font(.caption.weight(.semibold)).foregroundStyle(.primary)
                                                        if !place.address.isEmpty {
                                                            Text(place.address).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                                        }
                                                    }
                                                    Spacer()
                                                    Image(systemName: "arrow.up.forward.app").font(.caption2).foregroundStyle(.secondary)
                                                }
                                                .padding(9)
                                                .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                                            }
                                        }
                                    }
                                }
                                .id(msg.id)
                            }
                            if busy {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text("دا أفكر…".loc).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(14)
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(chips, id: \.query) { chip in
                            Button(chip.label.loc) { send(chip.query) }
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Color.blue.opacity(0.12), in: Capsule())
                        }
                    }.padding(.horizontal, 14).padding(.vertical, 6)
                }
                HStack(spacing: 8) {
                    TextField("اسأل أو اكتب اسم مكان…".loc, text: $input)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                        .onSubmit { send(input) }
                    Button { send(input) } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || busy)
                }
                .padding(12)
            }
            .navigationTitle("المساعد المحلي".loc)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("إغلاق".loc) { dismiss() }
                }
            }
        }
    }

    private func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy else { return }
        input = ""
        messages.append(AMsg(text: text, user: true, places: nil))
        busy = true
        Task {
            let reply = await answer(text)
            messages.append(reply)
            busy = false
        }
    }

    private func distText(_ place: Place) -> String {
        guard let userLocation else { return "" }
        let d = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
            .distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude))
        return d < 1000 ? "\(Int(d.rounded())) م" : String(format: "%.1f كم", d / 1000)
    }

    private func answer(_ text: String) async -> AMsg {
        let t = text
        // 1) Nearest place by category
        let catMap: [(words: [String], key: String)] = [
            (["صيدلي"], "pharmacy"), (["مطعم", "أكل", "اكل"], "restaurant"),
            (["كافيه", "قهوة", "مقهى"], "cafe"), (["مستشفى", "طوارئ", "طبيب"], "hospital"),
            (["وقود", "بنزين", "محطة"], "fuel"), (["فندق", "نوم"], "hotel"),
            (["حديقة", "منتزه"], "park"), (["سوبر", "سوق", "مول", "تسوق"], "supermarket")
        ]
        if let hit = catMap.first(where: { entry in entry.words.contains { t.contains($0) } }),
           let cat = categories.first(where: { $0.key == hit.key }) {
            guard let userLocation else {
                return AMsg(text: "فعّل الموقع حتى أكدر ألكي الأقرب إلك.".loc, user: false, places: nil)
            }
            let found = await GeoService.nearby(amenity: cat.key, group: cat.group, near: userLocation)
            if found.isEmpty {
                return AMsg(text: "ما لكيت \(cat.title) قريبة منك ضمن 5 كم.", user: false, places: nil)
            }
            let top = Array(found.prefix(4))
            return AMsg(text: "أقرب \(cat.title) منك: \(top[0].name) — يبعد \(distText(top[0])). دوس على أي نتيجة حتى تشوفها عالخريطة.", user: false, places: top)
        }
        // 2) Weather
        if t.contains("طقس") || t.contains("مطر") || t.contains("حار") || t.contains("جو") {
            guard let userLocation else {
                return AMsg(text: "فعّل الموقع حتى أجيبلك الطقس.".loc, user: false, places: nil)
            }
            if let w = await GeoService.weather(lat: userLocation.latitude, lon: userLocation.longitude) {
                return AMsg(text: "الطقس عندك هسه: \(w.label)، الحرارة \(Int(w.temperature.rounded()))°. الشروق \(w.sunrise) والغروب \(w.sunset).", user: false, places: nil)
            }
            return AMsg(text: "ما كدرت أجيب الطقس هسه، جرّب بعد شوية.".loc, user: false, places: nil)
        }
        // 3) Where am I
        if t.contains("وين اني") || t.contains("وين أني") || t.contains("موقعي") || t.contains("شارع") {
            guard let userLocation else {
                return AMsg(text: "فعّل الموقع أولاً.".loc, user: false, places: nil)
            }
            if let street = await GeoService.currentStreet(lat: userLocation.latitude, lon: userLocation.longitude) {
                return AMsg(text: "أنت هسه قريب من: \(street)", user: false, places: nil)
            }
            return AMsg(text: "موقعك معروف عندي بس ما كدرت أحدد اسم الشارع.".loc, user: false, places: nil)
        }
        // 4) Greeting
        if t.contains("سلام") || t.contains("هلا") || t.contains("مرحبا") {
            return AMsg(text: "هلا وعليكم السلام 🌹 اسألني: «أقرب صيدلية» أو «شنو الطقس؟» أو اكتب اسم مكان.".loc, user: false, places: nil)
        }
        // 5) Fallback: treat as a place search
        let found = await GeoService.search(t, near: userLocation, limit: 5)
        if !found.isEmpty {
            return AMsg(text: "لكيت هاي النتائج لـ«\(t)». دوس على وحدة حتى تفتحها عالخريطة.", user: false, places: found)
        }
        return AMsg(text: "ما لكيت نتيجة لـ«\(t)». جرّب: «أقرب مطعم»، «شنو الطقس؟»، أو اسم مكان أوضح.", user: false, places: nil)
    }
}
