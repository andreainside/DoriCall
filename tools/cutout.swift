// 批量抠图:用 Vision 主体分割把 Assets 里的 Dori 表情白底去掉,输出透明 PNG(原地覆盖)。
// 源图是从贴纸图集裁出来的,顶边常带相邻贴纸的残留 —— 凡是贴着图片最顶边的实例一律丢弃。
// 用法:cd 仓库根目录 && swift tools/cutout.swift
import AppKit
import Vision
import CoreImage

let faces = ["dori-loud", "dori-wink", "dori-thumbsup", "dori-working", "dori-sleep", "dori-victory"]
/// 这些图的手/身体贴着画框边,Vision 会当成裁切残留丢掉 —— 改用白底泛洪抠图
let floodFaces: Set<String> = ["dori-thumbsup"]
let assetsDir = URL(fileURLWithPath: "Assets")
let ciContext = CIContext()

func loadCG(_ url: URL) -> CGImage {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        fatalError("读不到 \(url.path)")
    }
    return img
}

func writePNG(_ img: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        fatalError("建不了 \(url.path)")
    }
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
}

/// 蒙版是否贴到图片最顶边(顶部 6 行内有命中 → 是图集裁切残留)
func touchesTop(_ mask: CVPixelBuffer) -> Bool {
    CVPixelBufferLockBaseAddress(mask, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
    let w = CVPixelBufferGetWidth(mask)
    let stride = CVPixelBufferGetBytesPerRow(mask) / MemoryLayout<Float>.size
    guard let base = CVPixelBufferGetBaseAddress(mask)?.assumingMemoryBound(to: Float.self) else { return false }
    for row in 0..<min(6, CVPixelBufferGetHeight(mask)) {
        for col in 0..<w where base[row * stride + col] > 0.5 { return true }
    }
    return false
}

/// 白底泛洪抠图:从四边的近白像素 BFS 把背景淹成透明,再腐蚀 2px 消抗锯齿白边。
/// 比 Vision 笨,但绝不会把贴着画框边缘的手脚当背景丢掉;画面内部的白色(牙齿、高光)不挨边,保留。
func floodCutout(_ img: CGImage) -> CGImage {
    let w = img.width, h = img.height
    var raw = [UInt8](repeating: 0, count: w * h * 4)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: &raw, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    func nearWhite(_ p: Int) -> Bool { raw[p * 4] > 235 && raw[p * 4 + 1] > 235 && raw[p * 4 + 2] > 235 }
    func clear(_ p: Int) { raw[p * 4] = 0; raw[p * 4 + 1] = 0; raw[p * 4 + 2] = 0; raw[p * 4 + 3] = 0 }
    var stack: [Int] = []
    for x in 0..<w { stack.append(x); stack.append((h - 1) * w + x) }
    for y in 0..<h { stack.append(y * w); stack.append(y * w + w - 1) }
    var seen = [Bool](repeating: false, count: w * h)
    while let p = stack.popLast() {
        if seen[p] { continue }
        seen[p] = true
        guard nearWhite(p), raw[p * 4 + 3] > 0 else { continue }
        clear(p)
        let x = p % w, y = p / w
        if x > 0 { stack.append(p - 1) }
        if x < w - 1 { stack.append(p + 1) }
        if y > 0 { stack.append(p - w) }
        if y < h - 1 { stack.append(p + w) }
    }
    return ctx.makeImage()!
}

/// 腐蚀 N 像素:挨着透明区/画框边的不透明像素清掉,消抗锯齿白边。
/// 必须在 removeTopComponents 之后跑 —— 先腐蚀会把顶边残留"剃离"顶边,让残留检测扑空
func erode(_ img: CGImage, passes: Int) -> CGImage {
    let w = img.width, h = img.height
    var raw = [UInt8](repeating: 0, count: w * h * 4)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: &raw, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    for _ in 0..<passes {
        var kill: [Int] = []
        for y in 0..<h {
            for x in 0..<w {
                let p = y * w + x
                guard raw[p * 4 + 3] > 0 else { continue }
                let edge = x == 0 || x == w - 1 || y == 0 || y == h - 1
                if edge || raw[(p - 1) * 4 + 3] == 0 || raw[(p + 1) * 4 + 3] == 0
                        || raw[(p - w) * 4 + 3] == 0 || raw[(p + w) * 4 + 3] == 0 { kill.append(p) }
            }
        }
        for p in kill { raw[p * 4] = 0; raw[p * 4 + 1] = 0; raw[p * 4 + 2] = 0; raw[p * 4 + 3] = 0 }
    }
    return ctx.makeImage()!
}

/// 去掉贴着顶边的连通块(Vision 可能把图集残留并进主体蒙版):
/// 从顶部 3 行的不透明像素出发 BFS,把整个连通块清成透明;人物和残留之间隔着透明区,不会误伤
func removeTopComponents(_ img: CGImage) -> CGImage {
    let w = img.width, h = img.height
    var raw = [UInt8](repeating: 0, count: w * h * 4)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: &raw, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    var stack: [Int] = []
    for y in 0..<min(3, h) {
        for x in 0..<w where raw[(y * w + x) * 4 + 3] > 10 { stack.append(y * w + x) }
    }
    var seen = [Bool](repeating: false, count: w * h)
    while let p = stack.popLast() {
        if seen[p] { continue }
        seen[p] = true
        if raw[p * 4 + 3] <= 10 { continue }
        raw[p * 4] = 0; raw[p * 4 + 1] = 0; raw[p * 4 + 2] = 0; raw[p * 4 + 3] = 0
        let x = p % w, y = p / w
        if x > 0 { stack.append(p - 1) }
        if x < w - 1 { stack.append(p + 1) }
        if y > 0 { stack.append(p - w) }
        if y < h - 1 { stack.append(p + w) }
    }
    return ctx.makeImage()!
}

/// 裁掉透明边、加 4% 留白、补成正方形画布
func squareTrim(_ img: CGImage) -> CGImage {
    let w = img.width, h = img.height
    var raw = [UInt8](repeating: 0, count: w * h * 4)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: &raw, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    var minX = w, minY = h, maxX = -1, maxY = -1
    for y in 0..<h {
        for x in 0..<w where raw[(y * w + x) * 4 + 3] > 10 {
            if x < minX { minX = x }; if x > maxX { maxX = x }
            if y < minY { minY = y }; if y > maxY { maxY = y }
        }
    }
    guard maxX >= minX else { return img }
    let bw = maxX - minX + 1, bh = maxY - minY + 1
    let pad = Int(Double(max(bw, bh)) * 0.04)
    let side = max(bw, bh) + pad * 2
    let outCtx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                           space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // cropping(to:) 是左上角原点,和扫描用的内存行号同一坐标系,不要翻转 y
    let cropped = ctx.makeImage()!.cropping(to: CGRect(x: minX, y: minY, width: bw, height: bh))!
    outCtx.draw(cropped, in: CGRect(x: (side - bw) / 2, y: (side - bh) / 2, width: bw, height: bh))
    return outCtx.makeImage()!
}

var previews: [CGImage] = []
for name in faces {
    let url = assetsDir.appendingPathComponent("\(name).png")
    let img = loadCG(url)
    let cut: CGImage
    var note: String
    if floodFaces.contains(name) {
        cut = erode(removeTopComponents(floodCutout(img)), passes: 2)
        note = "泛洪抠图"
    } else {
        let handler = VNImageRequestHandler(cgImage: img)
        let request = VNGenerateForegroundInstanceMaskRequest()
        try! handler.perform([request])
        guard let obs = request.results?.first else { fatalError("\(name): 没识别出主体") }
        var keep = IndexSet()
        for i in obs.allInstances {
            let mask = try! obs.generateScaledMaskForImage(forInstances: IndexSet(integer: i), from: handler)
            if !touchesTop(mask) { keep.insert(i) }
        }
        if keep.isEmpty { keep = obs.allInstances }   // 兜底:全是顶边实例就全保留
        let cutBuffer = try! obs.generateMaskedImage(ofInstances: keep, from: handler, croppedToInstancesExtent: false)
        let ciImg = CIImage(cvPixelBuffer: cutBuffer)
        cut = ciContext.createCGImage(ciImg, from: ciImg.extent)!
        note = "Vision 抠图,\(obs.allInstances.count) 实例保留 \(keep.count)"
    }
    let final = squareTrim(removeTopComponents(cut))
    writePNG(final, to: url)
    previews.append(final)
    print("✓ \(name): \(note),输出 \(final.width)×\(final.height)")
}

// 预览图:每个表情贴在红色和深色背景上各一份,人工检查边缘/对比度用
let cell = 150, cols = faces.count
let pvCtx = CGContext(data: nil, width: cell * cols, height: cell * 2, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
for (i, img) in previews.enumerated() {
    for (rowIdx, bg) in [CGColor(red: 1, green: 0.42, blue: 0.42, alpha: 1),
                         CGColor(red: 0.13, green: 0.13, blue: 0.13, alpha: 1)].enumerated() {
        let origin = CGPoint(x: i * cell, y: rowIdx * cell)
        pvCtx.setFillColor(bg)
        pvCtx.fill(CGRect(origin: origin, size: CGSize(width: cell, height: cell)))
        pvCtx.draw(img, in: CGRect(x: origin.x + 10, y: origin.y + 10, width: CGFloat(cell - 20), height: CGFloat(cell - 20)))
    }
}
writePNG(pvCtx.makeImage()!, to: URL(fileURLWithPath: "/tmp/cutout_preview.png"))
print("✓ 预览: /tmp/cutout_preview.png")
