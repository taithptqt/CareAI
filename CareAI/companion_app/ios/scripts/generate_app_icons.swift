import Foundation
import AppKit

let logoPath = "CareAI/companion_app/assets/images/logo.png"
let appIconSetDir = "CareAI/companion_app/ios/Runner/Assets.xcassets/AppIcon.appiconset"

guard let logoImage = NSImage(contentsOfFile: logoPath) else {
    print("Error: Could not load logo from \(logoPath)")
    exit(1)
}

let masterSize: CGFloat = 1024.0
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(
    data: nil,
    width: Int(masterSize),
    height: Int(masterSize),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    print("Error: Could not create CGContext")
    exit(1)
}

// 1. Vẽ nền gradient tinh tế màu xanh đen y tế sang trọng (Deep Medical Navy #0C1527 -> #13223E)
let colors = [
    CGColor(red: 12.0/255.0, green: 21.0/255.0, blue: 39.0/255.0, alpha: 1.0),
    CGColor(red: 19.0/255.0, green: 34.0/255.0, blue: 62.0/255.0, alpha: 1.0)
] as CFArray

if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) {
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: 0),
        end: CGPoint(x: masterSize, y: masterSize),
        options: []
    )
} else {
    context.setFillColor(red: 19.0/255.0, green: 30.0/255.0, blue: 49.0/255.0, alpha: 1.0)
    context.fill(CGRect(x: 0, y: 0, width: masterSize, height: masterSize))
}

// 2. Vẽ biểu tượng CareAI ở chính giữa (kích thước 720x720, lề 152px)
guard let cgLogo = logoImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("Error: Could not convert NSImage to CGImage")
    exit(1)
}

let logoDrawSize: CGFloat = 720.0
let offset = (masterSize - logoDrawSize) / 2.0
let logoRect = CGRect(x: offset, y: offset, width: logoDrawSize, height: logoDrawSize)
context.draw(cgLogo, in: logoRect)

guard let masterCGImage = context.makeImage() else {
    print("Error: Could not create master CGImage")
    exit(1)
}

let masterRep = NSBitmapImageRep(cgImage: masterCGImage)
guard let masterPngData = masterRep.representation(using: .png, properties: [:]) else {
    print("Error: Could not convert to PNG data")
    exit(1)
}

let masterPath = "\(appIconSetDir)/Icon-App-1024x1024@1x.png"
try masterPngData.write(to: URL(fileURLWithPath: masterPath))
print("Successfully generated master icon: \(masterPath)")

// Danh sách các kích thước theo Contents.json
let iconSpecs: [(name: String, size: Int)] = [
    ("Icon-App-20x20@1x.png", 20),
    ("Icon-App-20x20@2x.png", 40),
    ("Icon-App-20x20@3x.png", 60),
    ("Icon-App-29x29@1x.png", 29),
    ("Icon-App-29x29@2x.png", 58),
    ("Icon-App-29x29@3x.png", 87),
    ("Icon-App-40x40@1x.png", 40),
    ("Icon-App-40x40@2x.png", 80),
    ("Icon-App-40x40@3x.png", 120),
    ("Icon-App-60x60@2x.png", 120),
    ("Icon-App-60x60@3x.png", 180),
    ("Icon-App-76x76@1x.png", 76),
    ("Icon-App-76x76@2x.png", 152),
    ("Icon-App-83.5x83.5@2x.png", 167)
]

for spec in iconSpecs {
    let destPath = "\(appIconSetDir)/\(spec.name)"
    guard let resizedContext = CGContext(
        data: nil,
        width: spec.size,
        height: spec.size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { continue }
    
    resizedContext.interpolationQuality = .high
    resizedContext.draw(masterCGImage, in: CGRect(x: 0, y: 0, width: spec.size, height: spec.size))
    
    if let resizedCGImage = resizedContext.makeImage() {
        let rep = NSBitmapImageRep(cgImage: resizedCGImage)
        if let pngData = rep.representation(using: .png, properties: [:]) {
            try pngData.write(to: URL(fileURLWithPath: destPath))
            print("Generated \(spec.name) (\(spec.size)x\(spec.size))")
        }
    }
}

print("All AppIcon assets generated successfully!")
