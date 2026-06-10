// 图标生成:Assets/dori-wave.png → App 图标(白底圆角方)+ 菜单栏小圆标(头部特写)
// 用法: 在仓库根目录执行  swift tools/gen_icons.swift
import AppKit

let root = FileManager.default.currentDirectoryPath
let srcPath = root + "/Assets/dori-wave.png"
let outDir = root + "/Assets"

guard let src = NSImage(contentsOfFile: srcPath),
      let tiff = src.tiffRepresentation,
      let srcRep = NSBitmapImageRep(data: tiff),
      let srcCG = srcRep.cgImage else {
    fatalError("读不到 \(srcPath)")
}
let srcW = CGFloat(srcCG.width), srcH = CGFloat(srcCG.height)

func render(size: Int, draw: (CGContext, CGFloat) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size,
                        bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    draw(ctx, CGFloat(size))
    return ctx.makeImage()!
}

func savePNG(_ img: CGImage, _ path: String) {
    let rep = NSBitmapImageRep(cgImage: img)
    try! rep.representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: path))
}

// 1) App 图标母版 1024:白底 + macOS 圆角方 + 居中角色
let appMaster = render(size: 1024) { ctx, S in
    let rect = CGRect(x: 0, y: 0, width: S, height: S)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: S * 0.2237, cornerHeight: S * 0.2237, transform: nil))
    ctx.clip()
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(rect)
    let side = S * 0.86
    ctx.draw(srcCG, in: CGRect(x: (S - side) / 2, y: (S - side) / 2 - S * 0.01, width: side, height: side))
}
savePNG(appMaster, outDir + "/AppIcon-1024.png")

// 2) 菜单栏图标:头部特写圆形贴纸,18pt@2x = 36px(另出 144px 预览)
//    裁剪框:以源图 (0.45, 0.49) 为中心(纵向自顶部计),边长 0.78
let cropSide = 0.78 * min(srcW, srcH)
var crop = CGRect(x: 0.45 * srcW - cropSide / 2, y: 0.49 * srcH - cropSide / 2,
                  width: cropSide, height: cropSide)
crop.origin.x = max(0, min(crop.origin.x, srcW - cropSide))
crop.origin.y = max(0, min(crop.origin.y, srcH - cropSide))
let headCG = srcCG.cropping(to: crop)!

for (px, name) in [(36, "menubar.png"), (144, "menubar-preview.png")] {
    let img = render(size: px) { ctx, S in
        ctx.addEllipse(in: CGRect(x: 0, y: 0, width: S, height: S))
        ctx.clip()
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))
        ctx.draw(headCG, in: CGRect(x: 0, y: 0, width: S, height: S))
    }
    savePNG(img, outDir + "/" + name)
}
print("✅ 生成: AppIcon-1024.png / menubar.png / menubar-preview.png")
