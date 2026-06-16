import SwiftUI

/// Paywall shown when a free-tier user runs out of daily metronome time (or taps
/// "unlock" proactively). Sells the single non-consumable unlimited unlock.
struct PaywallView: View {
    let store: StoreManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var restoring = false

    private let accent = Color.indigo

    /// Apple's standard EULA. Used unless you set a custom license agreement in
    /// App Store Connect (App Information → License Agreement).
    private static let eulaURL = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
    /// Hosted privacy policy. App Store review requires a reachable privacy
    /// policy for apps that offer in-app purchase.
    private static let privacyURL = "https://github.com/windyboyy/better-life-privacy/blob/main/privacy-policy.md"

    var body: some View {
        VStack(spacing: 0) {
            closeBar
            ScrollView {
                VStack(spacing: 28) {
                    hero
                    benefits
                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
            }
            footer
        }
        .background(background.ignoresSafeArea())
        .task { await store.loadProduct() }
    }

    // MARK: - Pieces

    private var closeBar: some View {
        HStack {
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                    .padding(16)
            }
            .buttonStyle(.plain)
        }
    }

    private var hero: some View {
        VStack(spacing: 14) {
            Image(systemName: "infinity.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(accent)

            Text("解锁无限学习时长")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)

            Text("免费版每天可使用 10 分钟节拍器。\n一次性解锁，永久畅用，不限时长。")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 16) {
            benefitRow(icon: "infinity", title: "无限时长", detail: "节拍器想用多久就用多久")
            benefitRow(icon: "bolt.fill", title: "一次买断", detail: "非订阅，付一次永久有效")
            benefitRow(icon: "hand.raised.slash", title: "畅学不中断", detail: "学到一半不会被时长打断")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(colorScheme == .dark ? accent.opacity(0.12) : .white)
                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        )
    }

    private func benefitRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    if await store.purchase() { dismiss() }
                }
            } label: {
                Group {
                    if store.isPurchasing {
                        ProgressView().tint(.white)
                    } else {
                        Text("解锁无限 · \(store.priceText)")
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(accent)
                        .shadow(color: accent.opacity(0.3), radius: 10, y: 5)
                )
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(store.isPurchasing || store.product == nil)

            Button {
                Task {
                    restoring = true
                    await store.restore()
                    restoring = false
                    if store.isPro { dismiss() }
                }
            } label: {
                Text(restoring ? "恢复中…" : "恢复购买")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(restoring)

            legal
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 24)
    }

    /// One-time-purchase disclosure plus the legal links App Store review expects:
    /// terms of use (EULA) and a privacy policy.
    private var legal: some View {
        VStack(spacing: 6) {
            Text("一次性买断 · 非订阅 · 无自动续费")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Link("服务条款 (EULA)", destination: URL(string: Self.eulaURL)!)
                Text("·").foregroundStyle(.secondary)
                Link("隐私政策", destination: URL(string: Self.privacyURL)!)
            }
            .font(.system(size: 11))
            .tint(.secondary)
        }
        .padding(.top, 4)
    }

    private var background: Color {
        colorScheme == .dark
            ? Color(red: 0.1, green: 0.1, blue: 0.1)
            : Color(red: 0.96, green: 0.95, blue: 0.93)
    }
}

#Preview {
    PaywallView(store: StoreManager())
}
