import SwiftUI

extension WordMark {
    /// Accent color used for this mark's decoration and buttons.
    var color: Color {
        switch self {
        case .raw: return .red
        case .half: return .orange
        case .familiar: return .green
        case .unmarked: return .secondary
        }
    }
}

/// Applies the user's annotation style to a word view:
/// 生 → a circle (stroked capsule) around it, 半熟 → an underline, 熟/未标 → plain.
struct WordMarkDecoration: ViewModifier {
    let mark: WordMark

    func body(content: Content) -> some View {
        switch mark {
        case .raw:
            content
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(WordMark.raw.color, lineWidth: 2.5)
                )
        case .half:
            content
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(WordMark.half.color)
                        .frame(height: 2.5)
                        .offset(y: 5)
                }
        case .familiar, .unmarked:
            content
        }
    }
}

extension View {
    /// Decorate a word view according to its familiarity mark.
    func wordMark(_ mark: WordMark) -> some View {
        modifier(WordMarkDecoration(mark: mark))
    }
}
