import SwiftUI

struct PrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: BeautySpacing.sm) {
                if isLoading { ProgressView().tint(BeautyColor.limeInk) }
                if let systemImage { Image(systemName: systemImage) }
                Text(title).font(.system(size: 16, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .foregroundStyle(BeautyColor.limeInk)
            .background(
                LinearGradient(colors: [BeautyColor.lime, BeautyColor.limeSoft], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: Capsule()
            )
            .overlay(Capsule().stroke(BeautyColor.limeInk.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityAddTraits(.isButton)
    }
}

struct SecondaryButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: BeautySpacing.sm) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title).font(.system(size: 16, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundStyle(BeautyColor.ink)
            .background(BeautyColor.milk, in: Capsule())
            .overlay(Capsule().stroke(BeautyColor.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
    }
}

struct BeautyChip: View {
    let title: String
    var isSelected: Bool = false
    var icon: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.caption) }
                Text(title).font(BeautyFont.callout.weight(isSelected ? .semibold : .regular))
            }
            .foregroundStyle(BeautyColor.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isSelected ? BeautyColor.limeSoft.opacity(0.82) : BeautyColor.milk, in: Capsule())
            .overlay(Capsule().stroke(isSelected ? BeautyColor.lime.opacity(0.7) : BeautyColor.line.opacity(0.7), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: BeautySpacing.xs) {
            Text(title).font(BeautyFont.title2).foregroundStyle(BeautyColor.ink)
            if let subtitle { Text(subtitle).font(BeautyFont.callout).foregroundStyle(BeautyColor.taupe) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MatchBadge: View {
    let score: Int

    var body: some View {
        VStack(spacing: 0) {
            Text("\(score)%")
                .font(.system(size: 14, weight: .bold))
            Text("совп.")
                .font(BeautyFont.caption2)
        }
        .foregroundStyle(BeautyColor.limeInk)
        .lineLimit(1)
        .minimumScaleFactor(0.9)
        .frame(width: 50, height: 36)
        .background(BeautyColor.limeSoft, in: Capsule())
        .overlay(Capsule().stroke(BeautyColor.lime.opacity(0.55), lineWidth: 1))
        .accessibilityLabel("Совпадение \(score) процентов")
    }
}

struct RoutineStepPill: View {
    let title: String

    var body: some View {
        Text(title)
            .font(BeautyFont.caption)
            .foregroundStyle(BeautyColor.taupe)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(BeautyColor.champagne.opacity(0.22), in: Capsule())
    }
}

struct LoadingStateView: View {
    var title: String = "Подбираю рутину"
    var subtitle: String = "Сверяю Beauty ID, бюджет и каталог."

    var body: some View {
        VStack(spacing: BeautySpacing.md) {
            ProgressView().tint(BeautyColor.lime)
            Text(title).font(BeautyFont.headline)
            Text(subtitle).font(BeautyFont.callout).foregroundStyle(BeautyColor.taupe).multilineTextAlignment(.center)
        }
        .padding(BeautySpacing.xl)
        .frame(maxWidth: .infinity)
        .beautyCard()
    }
}

struct EmptyStateView: View {
    var title: String
    var subtitle: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: BeautySpacing.md) {
            Image("empty_state")
                .resizable()
                .scaledToFit()
                .frame(height: 132)
                .clipShape(RoundedRectangle(cornerRadius: BeautyRadius.lg, style: .continuous))
                .accessibilityHidden(true)
            Text(title).font(BeautyFont.headline).foregroundStyle(BeautyColor.ink)
            Text(subtitle).font(BeautyFont.callout).foregroundStyle(BeautyColor.taupe).multilineTextAlignment(.center)
            if let actionTitle, let action {
                SecondaryButton(title: actionTitle, action: action)
            }
        }
        .frame(maxWidth: .infinity)
        .beautyCard()
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: BeautySpacing.sm) {
            Image(systemName: "exclamationmark.circle")
            Text(message).font(BeautyFont.callout)
            Spacer()
        }
        .foregroundStyle(BeautyColor.danger)
        .padding(BeautySpacing.md)
        .background(BeautyColor.blush.opacity(0.22), in: RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous))
    }
}

struct StatusBanner: View {
    let message: String
    var systemImage: String = "checkmark.seal"

    var body: some View {
        HStack(alignment: .top, spacing: BeautySpacing.sm) {
            Image(systemName: systemImage)
            Text(message).font(BeautyFont.callout)
            Spacer()
        }
        .foregroundStyle(BeautyColor.ink)
        .padding(BeautySpacing.md)
        .background(BeautyColor.limeSoft.opacity(0.34), in: RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous).stroke(BeautyColor.lime.opacity(0.26), lineWidth: 1))
    }
}

struct FlowLayout<Data: RandomAccessCollection, Content: View>: View where Data.Element: Hashable {
    let data: Data
    let spacing: CGFloat
    let content: (Data.Element) -> Content

    init(_ data: Data, spacing: CGFloat = 8, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        var width = CGFloat.zero
        var height = CGFloat.zero
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(Array(data), id: \.self) { item in
                    content(item)
                        .padding(.trailing, spacing)
                        .padding(.bottom, spacing)
                        .alignmentGuide(.leading) { dimension in
                            if abs(width - dimension.width) > proxy.size.width {
                                width = 0
                                height -= dimension.height + spacing
                            }
                            let result = width
                            if let last = data.last, item == last { width = 0 }
                            else { width -= dimension.width + spacing }
                            return result
                        }
                        .alignmentGuide(.top) { _ in
                            let result = height
                            if let last = data.last, item == last { height = 0 }
                            return result
                        }
                }
            }
        }
        .frame(minHeight: 52)
    }
}
