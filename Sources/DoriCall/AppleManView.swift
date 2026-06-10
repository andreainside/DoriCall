import SwiftUI

/// Dori 苹果人:有人叫你时,苹果核从身体里升起 + 发光呼吸(软件版的"硬件升核"创意)
struct AppleManView: View {
    var ringing: Bool
    @State private var risen = false
    @State private var glow = false

    var body: some View {
        ZStack {
            core
                .offset(y: risen ? -26 : 4)
                .opacity(risen ? 1 : 0)
            apple
            leaf
        }
        .frame(width: 70, height: 84)
        .onAppear {
            guard ringing else { return }
            withAnimation(.spring(response: 0.8, dampingFraction: 0.55).delay(0.1)) { risen = true }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { glow = true }
        }
    }

    /// 苹果核:奶白色胶囊 + 两颗籽,发黄光
    private var core: some View {
        ZStack {
            Capsule()
                .fill(Color(hex: "FFF3CD"))
                .frame(width: 18, height: 36)
            VStack(spacing: 5) {
                Circle().fill(Color(hex: "6B4A12")).frame(width: 3.5, height: 3.5)
                Circle().fill(Color(hex: "6B4A12")).frame(width: 3.5, height: 3.5)
            }
        }
        .shadow(color: Color.yellow.opacity(glow ? 0.9 : 0.2), radius: glow ? 13 : 3)
    }

    /// 苹果身体 + 脸(两只眼睛 + 微笑)
    private var apple: some View {
        ZStack {
            Ellipse()
                .fill(Color(hex: "FF6B6B"))
                .frame(width: 50, height: 42)
            VStack(spacing: 4) {
                HStack(spacing: 11) {
                    Circle().fill(Color.black.opacity(0.72)).frame(width: 4.5, height: 4.5)
                    Circle().fill(Color.black.opacity(0.72)).frame(width: 4.5, height: 4.5)
                }
                Capsule().fill(Color.black.opacity(0.6)).frame(width: 11, height: 3)
            }
        }
        .offset(y: 16)
    }

    private var leaf: some View {
        Ellipse()
            .fill(Color(hex: "69DB7C"))
            .frame(width: 16, height: 8)
            .rotationEffect(.degrees(-28))
            .offset(x: 9, y: -8)
    }
}
