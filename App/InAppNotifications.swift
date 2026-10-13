import SwiftUI

/// Semantic tint for the compact in-app notification card.
enum InAppNoticeTone {
    case neutral
    case success
    case warning

    var color: Color {
        switch self {
        case .neutral: return Color(red: 0.36, green: 0.70, blue: 1.00)
        case .success: return Color(red: 0.28, green: 0.82, blue: 0.62)
        case .warning: return Color(red: 1.00, green: 0.68, blue: 0.28)
        }
    }
}

struct InAppNotice: Identifiable {
    let id: UUID
    let title: String
    let message: String?
    let symbol: String
    let tone: InAppNoticeTone
    let action: (() -> Void)?
}

/// One shared event sink keeps app notices consistent across screens.
@MainActor
final class InAppNoticeCenter: ObservableObject {
    static let shared = InAppNoticeCenter()

    @Published private(set) var current: InAppNotice?
    private var dismissTask: Task<Void, Never>?

    func show(title: String,
              message: String? = nil,
              symbol: String = "bell.fill",
              tone: InAppNoticeTone = .neutral,
              duration: TimeInterval? = 3.6,
              action: (() -> Void)? = nil) {
        dismissTask?.cancel()
        let notice = InAppNotice(id: UUID(), title: title, message: message,
                                 symbol: symbol, tone: tone, action: action)
        current = notice

        guard let duration, duration > 0 else { return }
        let id = notice.id
        let nanoseconds = UInt64(min(duration, 86_400) * 1_000_000_000)
        dismissTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled, let self, self.current?.id == id else { return }
            self.current = nil
        }
    }

    func dismiss(_ id: UUID) {
        guard current?.id == id else { return }
        dismissTask?.cancel()
        dismissTask = nil
        current = nil
    }

    func activate(_ notice: InAppNotice) {
        notice.action?()
        dismiss(notice.id)
    }
}

/// Lightweight, native Dynamic Island-inspired overlay. It uses a solid
/// rounded surface and a single opacity/slide transition rather than blur.
@MainActor
struct DynamicIslandNoticeOverlay: View {
    @ObservedObject private var center = InAppNoticeCenter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let notice = center.current {
                Button { center.activate(notice) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: notice.symbol)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(notice.tone.color)
                            .frame(width: 38, height: 38)
                            .background(notice.tone.color.opacity(0.16), in: Circle())

                        VStack(alignment: .leading, spacing: 3) {
                            Text(notice.title)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            if let message = notice.message, !message.isEmpty {
                                Text(message)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(Color.white.opacity(0.74))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 12)
                    .frame(maxWidth: 380, minHeight: 62, alignment: .leading)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 27, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 27, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.75)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityAction(named: Text("إغلاق".loc)) { center.dismiss(notice.id) }
                .highPriorityGesture(
                    DragGesture(minimumDistance: 12).onEnded { value in
                        if value.translation.height < -18 { center.dismiss(notice.id) }
                    }
                )
                .padding(.horizontal, 16)
                .padding(.top, 52)
                .id(notice.id)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: center.current?.id)
        .allowsHitTesting(center.current != nil)
    }
}
