import SwiftUI

struct BeautyScanOverlayView: View {
    let faceState: BeautyScanFaceState
    let stage: BeautyScanCameraStage

    @State private var scanLinePosition: CGFloat = 0
    @State private var alignedPulse = false

    private var accent: Color {
        faceState.isAligned || stage == .capturing ? BeautyColor.lime : Color.white.opacity(0.82)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                cameraVignette

                if let normalizedRect = faceState.faceRect {
                    let rect = displayRect(from: normalizedRect, in: proxy.size).insetBy(dx: -18, dy: -24)
                    FaceAdaptiveGuide(rect: rect, isAligned: faceState.isAligned || stage == .capturing, accent: accent)
                        .opacity(faceState.isRecentlyLost ? 0.58 : 1)
                    if faceState.isAligned || stage == .capturing {
                        scanLine(in: rect)
                    }
                } else {
                    EmptyFaceGuide()
                        .frame(width: min(proxy.size.width * 0.62, 270), height: min(proxy.size.height * 0.38, 360))
                        .position(x: proxy.size.width / 2, y: proxy.size.height * 0.44)
                }
            }
            .animation(.easeInOut(duration: 0.34), value: faceState.faceRect)
            .animation(.easeInOut(duration: 0.24), value: faceState.isAligned)
            .animation(.easeInOut(duration: 0.28), value: faceState.isRecentlyLost)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.55).repeatForever(autoreverses: true)) {
                    scanLinePosition = 1
                    alignedPulse = true
                }
            }
        }
        .ignoresSafeArea()
    }

    private var cameraVignette: some View {
        ZStack {
            LinearGradient(
                colors: [.black.opacity(0.42), .clear, .black.opacity(0.62)],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [.clear, .black.opacity(0.28)],
                center: .center,
                startRadius: 120,
                endRadius: 440
            )
        }
        .ignoresSafeArea()
    }

    private func displayRect(from normalized: CGRect, in size: CGSize) -> CGRect {
        CGRect(
            x: normalized.minX * size.width,
            y: normalized.minY * size.height,
            width: normalized.width * size.width,
            height: normalized.height * size.height
        )
    }

    private func scanLine(in rect: CGRect) -> some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [.clear, BeautyColor.lime.opacity(0.92), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: rect.width * 0.92, height: 2.5)
            .shadow(color: BeautyColor.lime.opacity(0.36), radius: 14, y: 0)
            .position(x: rect.midX, y: rect.minY + rect.height * (0.18 + scanLinePosition * 0.64))
            .opacity(stage == .capturing ? 1 : 0.74)
    }
}

private struct FaceAdaptiveGuide: View {
    let rect: CGRect
    let isAligned: Bool
    let accent: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: min(rect.width, rect.height) * 0.22, style: .continuous)
                .stroke(accent.opacity(isAligned ? 0.38 : 0.24), lineWidth: 1)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

            FaceCornerBrackets(cornerLength: min(rect.width, rect.height) * 0.18, radius: 26)
                .stroke(accent, style: StrokeStyle(lineWidth: isAligned ? 3 : 2.2, lineCap: .round, lineJoin: .round))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .shadow(color: isAligned ? BeautyColor.lime.opacity(0.28) : .clear, radius: 10)

            if isAligned {
                RoundedRectangle(cornerRadius: min(rect.width, rect.height) * 0.22, style: .continuous)
                    .stroke(BeautyColor.lime.opacity(0.16), lineWidth: 9)
                    .frame(width: rect.width + 10, height: rect.height + 10)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
    }
}

private struct FaceCornerBrackets: Shape {
    let cornerLength: CGFloat
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let l = min(cornerLength, min(rect.width, rect.height) / 3)
        let r = min(radius, l * 0.70)

        path.move(to: CGPoint(x: rect.minX, y: rect.minY + l))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + l, y: rect.minY))

        path.move(to: CGPoint(x: rect.maxX - l, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + l))

        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - l))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - l, y: rect.maxY))

        path.move(to: CGPoint(x: rect.minX + l, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - l))

        return path
    }
}

private struct EmptyFaceGuide: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 44, style: .continuous)
                .stroke(Color.white.opacity(0.30), lineWidth: 1)
            FaceCornerBrackets(cornerLength: 46, radius: 24)
                .stroke(Color.white.opacity(0.68), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            VStack(spacing: 8) {
                Image(systemName: "face.smiling")
                    .font(.system(size: 32, weight: .light))
                Text("Жду лицо")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.74))
        }
    }
}
