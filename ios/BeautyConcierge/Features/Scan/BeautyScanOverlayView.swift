import SwiftUI

/// Centered oval face guide (FaceID-style) with a dimmed surround and a pulsing accent stroke.
/// The oval is a fixed target the user aligns to — far calmer than the old adaptive bracket box.
struct BeautyScanOverlayView: View {
    let faceState: BeautyScanFaceState
    let stage: BeautyScanCameraStage

    @State private var pulse = false
    @State private var sweep: CGFloat = 0

    private var isLocked: Bool {
        faceState.isAligned || stage == .aligned || stage == .capturing
    }

    private var accent: Color {
        isLocked ? BeautyColor.lime : Color.white.opacity(0.9)
    }

    var body: some View {
        GeometryReader { proxy in
            let oval = ovalRect(in: proxy.size)

            ZStack {
                // Dimmed surround with an oval cutout so the face area stays bright.
                Color.black.opacity(0.55)
                    .mask {
                        Rectangle()
                            .overlay {
                                Ellipse()
                                    .frame(width: oval.width, height: oval.height)
                                    .position(x: oval.midX, y: oval.midY)
                                    .blendMode(.destinationOut)
                            }
                            .compositingGroup()
                    }
                    .ignoresSafeArea()

                // Soft outer halo when locked.
                Ellipse()
                    .stroke(BeautyColor.lime.opacity(isLocked ? 0.18 : 0), lineWidth: 12)
                    .frame(width: oval.width + 14, height: oval.height + 14)
                    .position(x: oval.midX, y: oval.midY)

                // Primary guide stroke — pulses while searching, solid lime when locked.
                Ellipse()
                    .stroke(
                        accent.opacity(isLocked ? 1 : (pulse ? 0.95 : 0.55)),
                        style: StrokeStyle(lineWidth: isLocked ? 4 : 2.5, lineCap: .round)
                    )
                    .frame(width: oval.width, height: oval.height)
                    .position(x: oval.midX, y: oval.midY)
                    .scaleEffect(isLocked ? 1 : (pulse ? 1.012 : 0.99))
                    .shadow(color: isLocked ? BeautyColor.lime.opacity(0.4) : .clear, radius: 12)

                // Scan sweep line inside the oval while capturing/aligned.
                if isLocked {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.clear, BeautyColor.lime.opacity(0.9), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: oval.width * 0.86, height: 2.5)
                        .position(
                            x: oval.midX,
                            y: oval.minY + oval.height * (0.16 + sweep * 0.68)
                        )
                        .shadow(color: BeautyColor.lime.opacity(0.35), radius: 10)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: isLocked)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    pulse = true
                }
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    sweep = 1
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    /// A portrait oval centred horizontally, sitting in the upper-middle of the frame
    /// so it never collides with the guidance panel at the bottom. Scales with screen size.
    private func ovalRect(in size: CGSize) -> CGRect {
        let width = min(size.width * 0.72, 320)
        let height = min(width * 1.32, size.height * 0.56)
        let centerX = size.width / 2
        let centerY = size.height * 0.40
        return CGRect(
            x: centerX - width / 2,
            y: centerY - height / 2,
            width: width,
            height: height
        )
    }
}
