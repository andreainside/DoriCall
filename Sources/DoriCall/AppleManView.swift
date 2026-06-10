import AppKit
import SwiftUI

/// Dori 官方表情:透明抠图(tools/cutout.swift 用 Vision 主体分割生成)+ 弹起动画
/// (软件版"升核"——Dori 从卡片里弹出来),直接站在彩色卡片上,无背景框。
struct DoriFaceView: View {
    let face: String          // Resources 里的图名,如 "dori-loud"
    var size: CGFloat = 68
    var ringing: Bool = false // 待回应的卡:持续呼吸光晕 + 左右摇摆
    @State private var risen = false
    @State private var glow = false
    @State private var rock = false

    var body: some View {
        if let img = Self.image(face) {
            Image(nsImage: img)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .rotationEffect(.degrees(ringing ? (rock ? 4 : -4) : 0), anchor: .bottom)
                .scaleEffect(risen ? 1 : 0.3)
                .offset(y: risen ? 0 : 16)
                .opacity(risen ? 1 : 0)
                .shadow(color: ringing ? .yellow.opacity(glow ? 0.9 : 0.3) : .black.opacity(0.3),
                        radius: ringing ? (glow ? 12 : 4) : 2, y: ringing ? 0 : 1)
                .onAppear {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.58).delay(0.05)) { risen = true }
                    guard ringing else { return }
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { glow = true }
                    withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { rock = true }
                }
        }
        // 找不到资源(裸跑、无 .app)时不显示表情,卡片纯文字,功能不受影响
    }

    private static var cache: [String: NSImage] = [:]
    private static func image(_ name: String) -> NSImage? {
        if let hit = cache[name] { return hit }
        guard let path = Bundle.main.path(forResource: name, ofType: "png"),
              let img = NSImage(contentsOfFile: path) else { return nil }
        cache[name] = img
        return img
    }
}
