import AppKit
import CoreGraphics

let S: CGFloat = 1024
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: Int(S), height: Int(S),
    bitsPerComponent: 8, bytesPerRow: 0, space: cs,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }

func rgb(_ r: CGFloat,_ g: CGFloat,_ b: CGFloat,_ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [r/255, g/255, b/255, a])!
}

// 圓角底(squircle 近似)：全幅圓角矩形 + 垂直漸層深藍→黑
let inset: CGFloat = 0
let rect = CGRect(x: inset, y: inset, width: S-2*inset, height: S-2*inset)
let radius: CGFloat = S * 0.2237   // Apple 圓角比例
let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
ctx.addPath(path); ctx.clip()

let grad = CGGradient(colorsSpace: cs, colors: [
    rgb(30, 41, 59), rgb(15, 23, 33), rgb(8, 12, 18)
] as CFArray, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: 0), options: [])

// 細網格線(淡)
ctx.setStrokeColor(rgb(255,255,255,0.05)); ctx.setLineWidth(2)
for i in 1..<6 {
    let y = S * CGFloat(i)/6
    ctx.move(to: CGPoint(x: 120, y: y)); ctx.addLine(to: CGPoint(x: S-120, y: y))
}
ctx.strokePath()

// 台股紅
let up = rgb(233, 59, 59)
let upGlow = rgb(255, 90, 80)

// 蠟燭(由左到右逐步走高)
struct C { let x: CGFloat; let lo: CGFloat; let hi: CGFloat; let oLo: CGFloat; let oHi: CGFloat }
let bars: [C] = [
    C(x: 235, lo: 360, hi: 500, oLo: 390, oHi: 460),
    C(x: 375, lo: 400, hi: 585, oLo: 430, oHi: 545),
    C(x: 515, lo: 470, hi: 660, oLo: 505, oHi: 620),
    C(x: 655, lo: 545, hi: 745, oLo: 585, oHi: 705),
    C(x: 795, lo: 620, hi: 835, oLo: 665, oHi: 795),
]
let bw: CGFloat = 70
for b in bars {
    ctx.setStrokeColor(up); ctx.setLineWidth(12)
    ctx.move(to: CGPoint(x: b.x, y: b.lo)); ctx.addLine(to: CGPoint(x: b.x, y: b.hi)); ctx.strokePath()
    ctx.setFillColor(up)
    let r = CGRect(x: b.x - bw/2, y: b.oLo, width: bw, height: b.oHi - b.oLo)
    ctx.fill(r)
}

// 上升趨勢線 + 發光
ctx.setLineCap(.round); ctx.setLineJoin(.round)
let pts = bars.map { CGPoint(x: $0.x, y: ($0.oLo + $0.oHi)/2 + 30) }
ctx.setShadow(offset: .zero, blur: 40, color: upGlow.copy(alpha: 0.9))
ctx.setStrokeColor(upGlow); ctx.setLineWidth(26)
ctx.move(to: pts[0]); for p in pts.dropFirst() { ctx.addLine(to: p) }
ctx.strokePath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)

// 箭頭(右上)
let tip = CGPoint(x: 855, y: 895)
ctx.setFillColor(upGlow)
ctx.move(to: tip)
ctx.addLine(to: CGPoint(x: tip.x - 95, y: tip.y - 30))
ctx.addLine(to: CGPoint(x: tip.x - 30, y: tip.y - 95))
ctx.closePath(); ctx.fillPath()

guard let img = ctx.makeImage() else { exit(1) }
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let rep = NSBitmapImageRep(cgImage: img)
guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! data.write(to: url)
print("wrote", url.path)
