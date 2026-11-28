import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Gunarok Sprite Sheet Processor
// Cuts AI-generated source sheets from art_source/sprites/ into crisp 192x128
// transparent pixel-art atlases + Godot 4 SpriteFrames (.tres) resources.
//
// Compile & run from workspace root:
//   CLANG_MODULE_CACHE_PATH=/tmp/clang-cache swiftc -O -module-cache-path /tmp/swift-cache tools/gunarok_sprites.swift -o /tmp/gunarok_sprites
//   /tmp/gunarok_sprites caesar
//   /tmp/gunarok_sprites all

let CELL_W = 192
let CELL_H = 128
let PAD = 4
let FEET_Y = CELL_H - PAD // 124 (4 px bottom padding)
let ATLAS_COLS = 10

let ART_TO_WARRIOR: [String: String] = [
    "leonidas": "leonidas",
    "caesar": "julius_caesar",
    "ragnar": "ragnar",
    "musashi": "musashi",
    "lapulapu": "lapu_lapu",
    "simo": "simo_hayha",
    "naikhanomtom": "nai_khanom_tom",
    "zeus": "zeus",
    "thor": "thor",
    "susanoo": "susanoo",
    "anubis": "anubis",
]

let STAND_HEIGHT_OVERRIDES: [String: Double] = [
    "zeus": 90.0,
    "leonidas": 88.0, // includes helmet crest so body stays ~84 px
    "thor": 88.0,
]

let LOOPING_ANIMS: Set<String> = [
    "idle", "walk", "grabbed",
]

let ANIM_FPS: [String: Double] = [
    "idle": 8.0,
    "walk": 11.0,
    "jump": 9.0,
    "crouch": 14.0,
    "block": 16.0,
    "crouch_block": 16.0,
    "hitstun": 10.0,
    "knockdown": 10.0,
    "getup": 10.0,
    "ko": 9.0,
    "victory": 8.0,
    "parry": 12.0,
    "parry_fail": 9.0,
    "parried": 8.0,
    "grabbed": 6.0,
    "light": 12.0,
    "forward_light": 12.0,
    "back_light": 12.0,
    "jump_light": 12.0,
    "heavy": 12.0,
    "forward_heavy": 12.0,
    "back_heavy": 12.0,
    "jump_heavy": 12.0,
    "seize": 12.0,
    "seize_throw": 12.0,
    "crouch_light": 12.0,
    "crouch_heavy": 12.0,
    "skill_ground": 12.0,
    "skill_air": 12.0,
    "skill_low": 12.0,
    "ultimate": 12.0,
]

let ANIM_ORDER: [String] = [
    "idle", "walk", "jump", "crouch", "block", "crouch_block",
    "hitstun", "knockdown", "getup", "ko", "victory",
    "parry", "parry_fail", "parried", "grabbed",
    "light", "forward_light", "back_light", "jump_light",
    "heavy", "forward_heavy", "back_heavy", "jump_heavy",
    "seize", "seize_throw", "crouch_light", "crouch_heavy",
    "skill_ground", "skill_air", "skill_low", "ultimate",
]

struct ManifestEntry {
    let file: String
    let champion: String
    let animation: String
    let frames: Int
    let layout: String
    let background: String
}

struct RGBAImage {
    let width: Int
    let height: Int
    var pixels: [UInt8] // width * height * 4, non-premultiplied RGBA
}

struct FrameCrop {
    let minX: Int
    let minY: Int
    let maxX: Int
    let maxY: Int
    let footCenterX: Double
    let pixelArea: Int
    let mask: [Bool]? // optional local pixel mask (only pixels belonging to THIS figure)
    let maskW: Int
    let maskOffX: Int
    let maskOffY: Int
    var width: Int { maxX - minX + 1 }
    var height: Int { maxY - minY + 1 }
}

func loadRGBA(path: String) -> RGBAImage? {
    let url = URL(fileURLWithPath: path)
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        return nil
    }
    let w = cg.width
    let h = cg.height
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: &buf,
        width: w,
        height: h,
        bitsPerComponent: 8,
        bytesPerRow: w * 4,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    return RGBAImage(width: w, height: h, pixels: buf)
}

func savePNG(image: RGBAImage, path: String) -> Bool {
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let cs = CGColorSpaceCreateDeviceRGB()
    let data = Data(image.pixels)
    guard let provider = CGDataProvider(data: data as CFData) else { return false }
    guard let cg = CGImage(
        width: image.width,
        height: image.height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: image.width * 4,
        space: cs,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    ) else { return false }
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        return false
    }
    CGImageDestinationAddImage(dest, cg, nil)
    return CGImageDestinationFinalize(dest)
}

func medianByte(_ arr: inout [Int]) -> Int {
    arr.sort()
    return arr[arr.count / 2]
}

func sampleBackground(_ img: RGBAImage) -> (r: Int, g: Int, b: Int, isGreen: Bool) {
    var rs: [Int] = []
    var gs: [Int] = []
    var bs: [Int] = []
    let corners = [
        (0, 0), (img.width - 10, 0),
        (0, img.height - 10), (img.width - 10, img.height - 10),
    ]
    for (cx, cy) in corners {
        for dy in 0..<8 {
            for dx in 0..<8 {
                let x = max(0, min(img.width - 1, cx + dx))
                let y = max(0, min(img.height - 1, cy + dy))
                let i = (y * img.width + x) * 4
                rs.append(Int(img.pixels[i]))
                gs.append(Int(img.pixels[i + 1]))
                bs.append(Int(img.pixels[i + 2]))
            }
        }
    }
    let r = medianByte(&rs)
    let g = medianByte(&gs)
    let b = medianByte(&bs)
    let isGreen = (g > r + 20) && (g > b + 18)
    return (r, g, b, isGreen)
}

@inline(__always)
func colorDistSq(_ r1: Int, _ g1: Int, _ b1: Int, _ r2: Int, _ g2: Int, _ b2: Int) -> Int {
    let dr = r1 - r2
    let dg = g1 - g2
    let db = b1 - b2
    return dr * dr + dg * dg + db * db
}

func removeBackground(_ img: inout RGBAImage) {
    let w = img.width
    let h = img.height
    let n = w * h
    let bg = sampleBackground(img)
    let bgLum = (bg.r * 299 + bg.g * 587 + bg.b * 114) / 1000
    var isBg = [Bool](repeating: false, count: n)

    if bg.isGreen {
        // Green-screen champions (Simo, Zeus): remove green anywhere in the sheet.
        for idx in 0..<n {
            let p = idx * 4
            let r = Int(img.pixels[p])
            let g = Int(img.pixels[p + 1])
            let b = Int(img.pixels[p + 2])
            let d2 = colorDistSq(r, g, b, bg.r, bg.g, bg.b)
            if d2 <= 48 * 48 || (g > r + 14 && g > b + 12 && d2 <= 88 * 88) {
                isBg[idx] = true
            }
        }
    } else {
        // Gray/White-background champions: border BFS flood fill so silver weapons stay intact.
        var queue = [Int]()
        queue.reserveCapacity(n / 2)
        func trySeed(_ idx: Int) {
            if isBg[idx] { return }
            let p = idx * 4
            let r = Int(img.pixels[p])
            let g = Int(img.pixels[p + 1])
            let b = Int(img.pixels[p + 2])
            let d2 = colorDistSq(r, g, b, bg.r, bg.g, bg.b)
            let sat = max(r, max(g, b)) - min(r, min(g, b))
            let lum = (r * 299 + g * 587 + b * 114) / 1000
            if (d2 <= 44 * 44 && sat <= 28) || (bgLum >= 195 && lum >= bgLum - 26 && sat <= 18) {
                isBg[idx] = true
                queue.append(idx)
            }
        }
        for x in 0..<w {
            trySeed(x)
            trySeed((h - 1) * w + x)
        }
        for y in 0..<h {
            trySeed(y * w)
            trySeed(y * w + (w - 1))
        }
        var head = 0
        while head < queue.count {
            let cur = queue[head]
            head += 1
            let x = cur % w
            let y = cur / w
            if x > 0 { trySeed(cur - 1) }
            if x + 1 < w { trySeed(cur + 1) }
            if y > 0 { trySeed(cur - w) }
            if y + 1 < h { trySeed(cur + w) }
        }

        // Second pass: aggressively remove enclosed background pockets (arm-torso gaps,
        // between legs, shield/cape/hair loops) while protecting shaded silver blades.
        var visited = [Bool](repeating: false, count: n)
        var comp = [Int]()
        for idx in 0..<n {
            if isBg[idx] || visited[idx] { continue }
            let p = idx * 4
            let r = Int(img.pixels[p])
            let g = Int(img.pixels[p + 1])
            let b = Int(img.pixels[p + 2])
            let d2 = colorDistSq(r, g, b, bg.r, bg.g, bg.b)
            let sat = max(r, max(g, b)) - min(r, min(g, b))
            let lum = (r * 299 + g * 587 + b * 114) / 1000
            let isSeed = (d2 <= 28 * 28 && sat <= 20) || (bgLum >= 210 && lum >= 208 && sat <= 14)
            if !isSeed { continue }

            comp.removeAll(keepingCapacity: true)
            visited[idx] = true
            comp.append(idx)
            var ch = 0
            var borderDark = 0
            var borderTotal = 0
            var sumR = 0, sumG = 0, sumB = 0
            var minLum = 255, maxLum = 0
            while ch < comp.count {
                let c = comp[ch]
                ch += 1
                let cp = c * 4
                let cr = Int(img.pixels[cp]), cg = Int(img.pixels[cp + 1]), cb = Int(img.pixels[cp + 2])
                sumR += cr; sumG += cg; sumB += cb
                let clum = (cr * 299 + cg * 587 + cb * 114) / 1000
                if clum < minLum { minLum = clum }
                if clum > maxLum { maxLum = clum }

                let cx = c % w
                let cy = c / w
                let nbrs = [
                    cx > 0 ? c - 1 : -1,
                    cx + 1 < w ? c + 1 : -1,
                    cy > 0 ? c - w : -1,
                    cy + 1 < h ? c + w : -1,
                ]
                for nb in nbrs where nb >= 0 {
                    if isBg[nb] || visited[nb] { continue }
                    let np = nb * 4
                    let nr = Int(img.pixels[np])
                    let ng = Int(img.pixels[np + 1])
                    let nbv = Int(img.pixels[np + 2])
                    let nd2 = colorDistSq(nr, ng, nbv, bg.r, bg.g, bg.b)
                    let nsat = max(nr, max(ng, nbv)) - min(nr, min(ng, nbv))
                    let nlum = (nr * 299 + ng * 587 + nbv * 114) / 1000
                    if (nd2 <= 34 * 34 && nsat <= 24) || (bgLum >= 210 && nlum >= 205 && nsat <= 16) {
                        visited[nb] = true
                        comp.append(nb)
                    } else {
                        borderTotal += 1
                        if nlum < 130 { borderDark += 1 }
                    }
                }
            }
            if comp.count >= 8 && borderTotal > 0 {
                let cnt = comp.count
                let avgR = sumR / cnt, avgG = sumG / cnt, avgB = sumB / cnt
                let avgD2 = colorDistSq(avgR, avgG, avgB, bg.r, bg.g, bg.b)
                let avgLum = (avgR * 299 + avgG * 587 + avgB * 114) / 1000
                let darkRatio = Double(borderDark) / Double(borderTotal)
                let flatEnough = (maxLum - minLum) <= 44
                // Enclosed background pocket: close to sheet bg color (or pure flat white/light-gray)
                // surrounded by dark sprite outlines -> erase completely!
                let matchesBg = (avgD2 <= 28 * 28 && darkRatio >= 0.14)
                let pureWhitePocket = (bgLum >= 200 && avgLum >= 224 && flatEnough && darkRatio >= 0.16)
                let largeBgPocket = (cnt >= 36 && avgD2 <= 36 * 36 && flatEnough && darkRatio >= 0.12)
                if matchesBg || pureWhitePocket || largeBgPocket {
                    for c in comp { isBg[c] = true }
                }
            }
        }
    }

    // 3-pass anti-halo defringing (8-connected) to eliminate white/gray/green JPEG streaks.
    for pass in 0..<3 {
        var toRemove = [Int]()
        for y in 1..<(h - 1) {
            let row = y * w
            for x in 1..<(w - 1) {
                let idx = row + x
                if isBg[idx] { continue }
                let touchesBg = isBg[idx - 1] || isBg[idx + 1] || isBg[idx - w] || isBg[idx + w]
                    || (pass < 2 && (isBg[idx - w - 1] || isBg[idx - w + 1] || isBg[idx + w - 1] || isBg[idx + w + 1]))
                if !touchesBg { continue }
                let p = idx * 4
                let r = Int(img.pixels[p])
                let g = Int(img.pixels[p + 1])
                let b = Int(img.pixels[p + 2])
                let d2 = colorDistSq(r, g, b, bg.r, bg.g, bg.b)
                if bg.isGreen {
                    if d2 <= 82 * 82 || (g > r + 9 && g > b + 7 && g < 185) {
                        toRemove.append(idx)
                    }
                } else {
                    let sat = max(r, max(g, b)) - min(r, min(g, b))
                    let lum = (r * 299 + g * 587 + b * 114) / 1000
                    let thresh = pass == 0 ? 74 : (pass == 1 ? 64 : 52)
                    if (d2 <= thresh * thresh && sat <= 28 && lum > 135)
                        || (bgLum >= 200 && lum >= 220 && sat <= 20) {
                        toRemove.append(idx)
                    }
                }
            }
        }
        for idx in toRemove { isBg[idx] = true }
    }

    // Green-spill neutralization & bright-matte edge decontamination on surviving outline pixels.
    for y in 1..<(h - 1) {
        let row = y * w
        for x in 1..<(w - 1) {
            let idx = row + x
            if isBg[idx] { continue }
            if !(isBg[idx - 1] || isBg[idx + 1] || isBg[idx - w] || isBg[idx + w]) { continue }
            let p = idx * 4
            let r = Int(img.pixels[p])
            let g = Int(img.pixels[p + 1])
            let b = Int(img.pixels[p + 2])
            if bg.isGreen {
                if g > max(r, b) {
                    img.pixels[p + 1] = UInt8(min(255, (r + b) / 2 + 4))
                }
            } else {
                let sat = max(r, max(g, b)) - min(r, min(g, b))
                let lum = (r * 299 + g * 587 + b * 114) / 1000
                if sat <= 22 && lum > 175 && bgLum >= 190 {
                    // Darken stray pale JPEG halo pixels into crisp outline tone.
                    img.pixels[p] = UInt8(max(0, r - 65))
                    img.pixels[p + 1] = UInt8(max(0, g - 65))
                    img.pixels[p + 2] = UInt8(max(0, b - 65))
                }
            }
        }
    }

    for idx in 0..<n {
        if isBg[idx] {
            let p = idx * 4
            img.pixels[p] = 0
            img.pixels[p + 1] = 0
            img.pixels[p + 2] = 0
            img.pixels[p + 3] = 0
        } else {
            img.pixels[idx * 4 + 3] = 255
        }
    }
}

func rowCountsForLayout(_ layout: String, frames: Int) -> [Int] {
    switch layout {
    case "1 row":
        return [frames]
    case "2x2":
        return [2, 2]
    case "3x2":
        return [3, 3]
    case "3 top + 2 bottom":
        return [3, 2]
    default:
        return [frames]
    }
}

func findHorizontalSplit(_ img: RGBAImage) -> Int {
    let w = img.width
    let h = img.height
    let yMin = Int(Double(h) * 0.34)
    let yMax = Int(Double(h) * 0.66)
    var bestY = h / 2
    var bestScore = Int.max
    for y in yMin...yMax {
        var cnt = 0
        let row = y * w
        for x in 0..<w {
            if img.pixels[(row + x) * 4 + 3] > 0 { cnt += 1 }
        }
        // Slight preference for staying near center when multiple rows are completely empty.
        let score = cnt * 1000 + abs(y - h / 2)
        if score < bestScore {
            bestScore = score
            bestY = y
        }
    }
    return bestY
}

func findVerticalSplits(_ img: RGBAImage, y0: Int, y1: Int, count: Int) -> [Int] {
    let w = img.width
    if count <= 1 { return [0, w] }
    var colCounts = [Int](repeating: 0, count: w)
    var rowMinX = w
    var rowMaxX = 0
    for y in y0..<y1 {
        let row = y * w
        for x in 0..<w {
            if img.pixels[(row + x) * 4 + 3] > 0 {
                colCounts[x] += 1
                if x < rowMinX { rowMinX = x }
                if x > rowMaxX { rowMaxX = x }
            }
        }
    }
    if rowMinX >= rowMaxX { return [0, w] }
    let span = rowMaxX - rowMinX
    var splits = [0]
    for i in 1..<count {
        let ideal = rowMinX + Int(Double(span) * Double(i) / Double(count))
        let margin = Int(Double(span) * 0.22)
        let xMin = max(splits.last! + 10, ideal - margin)
        let xMax = min(rowMaxX - 10, ideal + margin)
        var bestX = ideal
        var bestScore = Int.max
        if xMin <= xMax {
            for x in xMin...xMax {
                let score = colCounts[x] * 1000 + abs(x - ideal)
                if score < bestScore {
                    bestScore = score
                    bestX = x
                }
            }
        }
        splits.append(bestX)
    }
    splits.append(w)
    return splits
}

struct Blob {
    var pixels: [Int]
    var minX: Int
    var minY: Int
    var maxX: Int
    var maxY: Int
    var cx: Double
    var cy: Double
}

/// Connected-component figure extraction: keeps every weapon/axe/sword attached to its own
/// character instead of slicing across overhanging weapons with straight grid lines!
func extractFiguresByComponents(_ img: RGBAImage, expectedFrames: Int, rowCounts: [Int]) -> [FrameCrop]? {
    let w = img.width
    let h = img.height
    let n = w * h
    var visited = [Bool](repeating: false, count: n)
    var blobs = [Blob]()
    var queue = [Int]()
    queue.reserveCapacity(4096)

    for idx in 0..<n {
        if visited[idx] || img.pixels[idx * 4 + 3] == 0 { continue }
        queue.removeAll(keepingCapacity: true)
        visited[idx] = true
        queue.append(idx)
        var head = 0
        var minX = w, minY = h, maxX = 0, maxY = 0
        var sumX = 0.0, sumY = 0.0
        while head < queue.count {
            let cur = queue[head]
            head += 1
            let x = cur % w
            let y = cur / w
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }
            sumX += Double(x)
            sumY += Double(y)
            // 8-connected so thin diagonal weapon shafts stay attached to hands
            let y0 = max(0, y - 1), y1 = min(h - 1, y + 1)
            let x0 = max(0, x - 1), x1 = min(w - 1, x + 1)
            for ny in y0...y1 {
                let row = ny * w
                for nx in x0...x1 {
                    let ni = row + nx
                    if !visited[ni] && img.pixels[ni * 4 + 3] > 0 {
                        visited[ni] = true
                        queue.append(ni)
                    }
                }
            }
        }
        if queue.count >= 24 {
            let cnt = Double(queue.count)
            blobs.append(Blob(
                pixels: queue,
                minX: minX, minY: minY, maxX: maxX, maxY: maxY,
                cx: sumX / cnt, cy: sumY / cnt
            ))
        }
    }

    if blobs.count < expectedFrames { return nil }
    // Sort by area descending; top `expectedFrames` are the main character bodies.
    blobs.sort { $0.pixels.count > $1.pixels.count }
    // Sanity check: the Nth largest blob must be a real figure (>= 25% of largest body area),
    // otherwise two figures touched and merged -> fall back to valley splitting.
    let largestArea = blobs[0].pixels.count
    if blobs[expectedFrames - 1].pixels.count < largestArea / 5 {
        return nil
    }

    var mains = Array(blobs[0..<expectedFrames])
    let extras = Array(blobs[expectedFrames...])

    // Sort main bodies into reading order matching rowCounts (1 row or 2 rows).
    if rowCounts.count == 1 {
        mains.sort { $0.cx < $1.cx }
    } else {
        mains.sort { $0.cy < $1.cy }
        let topCount = rowCounts[0]
        var topRow = Array(mains[0..<topCount])
        var botRow = Array(mains[topCount..<expectedFrames])
        topRow.sort { $0.cx < $1.cx }
        botRow.sort { $0.cx < $1.cx }
        mains = topRow + botRow
    }

    // Assign detached pieces (slash trails, muzzle flashes, dropped swords) to nearest main body.
    var groups: [[Blob]] = mains.map { [$0] }
    for ex in extras {
        var bestIdx = 0
        var bestDist = Double.greatestFiniteMagnitude
        for (i, m) in mains.enumerated() {
            // Distance from extra's centroid to main body's bounding box
            let dx = max(Double(m.minX) - ex.cx, max(0.0, ex.cx - Double(m.maxX)))
            let dy = max(Double(m.minY) - ex.cy, max(0.0, ex.cy - Double(m.maxY)))
            let d = hypot(dx, dy)
            if d < bestDist {
                bestDist = d
                bestIdx = i
            }
        }
        // Only attach if reasonably close to the character (< 140 source px).
        if bestDist < 140.0 {
            groups[bestIdx].append(ex)
        }
    }

    var crops = [FrameCrop]()
    for grp in groups {
        var minX = w, minY = h, maxX = 0, maxY = 0
        for b in grp {
            if b.minX < minX { minX = b.minX }
            if b.minY < minY { minY = b.minY }
            if b.maxX > maxX { maxX = b.maxX }
            if b.maxY > maxY { maxY = b.maxY }
        }
        let cw = maxX - minX + 1
        let ch = maxY - minY + 1
        var mask = [Bool](repeating: false, count: cw * ch)
        for b in grp {
            for p in b.pixels {
                let lx = (p % w) - minX
                let ly = (p / w) - minY
                mask[ly * cw + lx] = true
            }
        }
        // Foot centroid from main body's bottom 30%.
        let main = grp[0]
        let footBandTop = main.maxY - Int(Double(main.maxY - main.minY) * 0.30)
        var sumX = 0.0, cntX = 0.0
        for p in main.pixels {
            let py = p / w
            if py >= footBandTop {
                sumX += Double(p % w)
                cntX += 1.0
            }
        }
        let footCenterX = cntX > 0 ? (sumX / cntX) : Double(main.minX + main.maxX) * 0.5
        crops.append(FrameCrop(
            minX: minX, minY: minY, maxX: maxX, maxY: maxY,
            footCenterX: footCenterX,
            pixelArea: main.pixels.count,
            mask: mask, maskW: cw, maskOffX: minX, maskOffY: minY
        ))
    }
    return crops
}

func extractCellCrop(_ img: RGBAImage, x0: Int, y0: Int, x1: Int, y1: Int) -> FrameCrop? {
    let w = img.width
    let cw = x1 - x0
    let ch = y1 - y0
    if cw <= 0 || ch <= 0 { return nil }

    // Filter out tiny isolated noise blobs (< 24 pixels) inside this cell.
    var visited = [Bool](repeating: false, count: cw * ch)
    var validMask = [Bool](repeating: false, count: cw * ch)
    var comp = [Int]()

    for ly in 0..<ch {
        for lx in 0..<cw {
            let li = ly * cw + lx
            if visited[li] { continue }
            if img.pixels[((y0 + ly) * w + (x0 + lx)) * 4 + 3] == 0 { continue }
            comp.removeAll(keepingCapacity: true)
            visited[li] = true
            comp.append(li)
            var head = 0
            while head < comp.count {
                let c = comp[head]
                head += 1
                let cx = c % cw
                let cy = c / cw
                let nbrs = [
                    cx > 0 ? c - 1 : -1,
                    cx + 1 < cw ? c + 1 : -1,
                    cy > 0 ? c - cw : -1,
                    cy + 1 < ch ? c + cw : -1,
                ]
                for nb in nbrs where nb >= 0 {
                    if visited[nb] { continue }
                    let nx = nb % cw
                    let ny = nb / cw
                    if img.pixels[((y0 + ny) * w + (x0 + nx)) * 4 + 3] > 0 {
                        visited[nb] = true
                        comp.append(nb)
                    }
                }
            }
            if comp.count >= 24 {
                for c in comp { validMask[c] = true }
            }
        }
    }

    var minX = x1, minY = y1, maxX = x0, maxY = y0
    var found = false
    for ly in 0..<ch {
        for lx in 0..<cw {
            if validMask[ly * cw + lx] {
                found = true
                let gx = x0 + lx
                let gy = y0 + ly
                if gx < minX { minX = gx }
                if gx > maxX { maxX = gx }
                if gy < minY { minY = gy }
                if gy > maxY { maxY = gy }
            }
        }
    }
    if !found { return nil }

    // Compute horizontal center-of-mass of the bottom 30% (legs/feet) so extending
    // weapons and slash trails don't yank the champion's feet off center!
    let footBandTop = maxY - Int(Double(maxY - minY) * 0.30)
    var sumX = 0.0
    var cntX = 0.0
    for ly in (footBandTop - y0)...(maxY - y0) {
        for lx in (minX - x0)...(maxX - x0) {
            if validMask[ly * cw + lx] {
                sumX += Double(x0 + lx)
                cntX += 1.0
            }
        }
    }
    var area = 0
    for v in validMask where v { area += 1 }
    let footCenterX = cntX > 0 ? (sumX / cntX) : Double(minX + maxX) * 0.5
    return FrameCrop(
        minX: minX, minY: minY, maxX: maxX, maxY: maxY,
        footCenterX: footCenterX,
        pixelArea: max(1, area),
        mask: nil, maskW: 0, maskOffX: 0, maskOffY: 0
    )
}

/// Computes the exact scale factor for a sheet AND optional per-frame normalization
/// so sprite sizes stay rock-solid across idle, walk, block, crouch, parry, getup, and attacks!
func scalesForAnimation(anim: String, crops: [FrameCrop], standHeight: Double, targetBodyArea: Double) -> [Double] {
    if crops.isEmpty { return [] }
    if anim == "idle" || targetBodyArea <= 0.0 {
        let heights = crops.map { Double($0.height) }.sorted()
        let baseScale = standHeight / max(1.0, heights[heights.count / 2])
        // Even within idle, normalize slight AI frame-to-frame size jitter!
        let areas = crops.map { Double($0.pixelArea) }.sorted()
        let medArea = areas[areas.count / 2]
        return crops.map { crop in
            let corr = max(0.92, min(1.08, sqrt(medArea / max(1.0, Double(crop.pixelArea)))))
            return baseScale * corr
        }
    }

    let areas = crops.map { Double($0.pixelArea) }.sorted()
    let medArea = areas[areas.count / 2]
    let maxArea = areas.last!

    switch anim {
    case "crouch", "getup", "knockdown", "ko":
        // Multi-posture sheets contain both a standing frame and a crouched/lying frame.
        // Anchor the entire sheet to the standing frame's area (maxArea) so standing
        // matches idle 1:1 and crouched/lying frames stay anatomically proportional!
        let s = sqrt(targetBodyArea / max(1.0, maxArea))
        return Array(repeating: s, count: crops.count)

    case "crouch_block", "crouch_light", "crouch_heavy":
        // Tucked legs reduce silhouette area to ~88% of standing area; match 0.88 * targetBodyArea
        // so crouching fighters never blow up bigger than standing!
        let s = sqrt((targetBodyArea * 0.88) / max(1.0, medArea))
        return Array(repeating: s, count: crops.count)

    case "skill_low":
        let heights = crops.map { Double($0.height) }.sorted()
        if heights.last! / max(1.0, heights.first!) > 1.55 {
            // Transitions standing <-> prone (e.g., Simo Prone Shot): anchor to standing maxArea.
            let s = sqrt(targetBodyArea / max(1.0, maxArea))
            return Array(repeating: s, count: crops.count)
        }
        let s = sqrt((targetBodyArea * 0.90) / max(1.0, medArea))
        return Array(repeating: s, count: crops.count)

    case "walk", "block", "hitstun", "parry", "parry_fail", "parried", "grabbed", "back_light":
        // Standing utility/defense animations: normalize EACH frame to targetBodyArea
        // so blocking, parrying, or getting hit NEVER visibly jumps in size!
        return crops.map { crop in
            let s = sqrt(targetBodyArea / max(1.0, Double(crop.pixelArea)))
            let maxHScale = (standHeight * 1.08) / max(1.0, Double(crop.height))
            return min(s, maxHScale)
        }

    default:
        // Attacks, skills, jumps, victory, ultimate: anchor sheet to median body area
        // (frames with wide slash arcs stay slightly larger area, so median gives clean body match).
        let s = sqrt(targetBodyArea / max(1.0, medArea))
        return Array(repeating: s, count: crops.count)
    }
}

/// Renders one cropped figure onto a 192x128 cell at (destX, destY) in atlas using
/// opaque-only area averaging with a hard alpha cutoff -> zero halos, crisp pixel art.
func blitFrameToAtlas(
    src: RGBAImage,
    crop: FrameCrop,
    scale: Double,
    atlas: inout RGBAImage,
    cellCol: Int,
    cellRow: Int
) {
    let maxW = Double(CELL_W - PAD * 2)
    let maxH = Double(CELL_H - PAD * 2)
    var effScale = scale
    if Double(crop.width) * effScale > maxW {
        effScale = min(effScale, maxW / Double(crop.width))
    }
    if Double(crop.height) * effScale > maxH {
        effScale = min(effScale, maxH / Double(crop.height))
    }

    let outW = max(1, Int(round(Double(crop.width) * effScale)))
    let outH = max(1, Int(round(Double(crop.height) * effScale)))

    // Anchor feet centroid at x = 96, bottom of feet at y = 124 (clamped to padding).
    let footOffset = (crop.footCenterX - Double(crop.minX)) * effScale
    var dstX0 = Int(round(Double(CELL_W) * 0.5 - footOffset))
    dstX0 = max(PAD, min(CELL_W - PAD - outW, dstX0))
    let dstY0 = max(PAD, FEET_Y - outH)

    let atlasBaseX = cellCol * CELL_W + dstX0
    let atlasBaseY = cellRow * CELL_H + dstY0

    let invScale = 1.0 / effScale
    for ty in 0..<outH {
        let sy0 = crop.minY + Int(floor(Double(ty) * invScale))
        let sy1 = min(crop.maxY, max(sy0, crop.minY + Int(ceil(Double(ty + 1) * invScale)) - 1))
        let ay = atlasBaseY + ty
        for tx in 0..<outW {
            let sx0 = crop.minX + Int(floor(Double(tx) * invScale))
            let sx1 = min(crop.maxX, max(sx0, crop.minX + Int(ceil(Double(tx + 1) * invScale)) - 1))

            var sumR = 0, sumG = 0, sumB = 0
            var opaqueCount = 0
            var totalCount = 0
            for sy in sy0...sy1 {
                let sRow = sy * src.width
                for sx in sx0...sx1 {
                    totalCount += 1
                    if let m = crop.mask {
                        let lx = sx - crop.maskOffX
                        let ly = sy - crop.maskOffY
                        if !m[ly * crop.maskW + lx] { continue }
                    }
                    let sp = (sRow + sx) * 4
                    if src.pixels[sp + 3] > 0 {
                        opaqueCount += 1
                        sumR += Int(src.pixels[sp])
                        sumG += Int(src.pixels[sp + 1])
                        sumB += Int(src.pixels[sp + 2])
                    }
                }
            }
            if totalCount > 0 && Double(opaqueCount) / Double(totalCount) >= 0.45 {
                let ap = (ay * atlas.width + (atlasBaseX + tx)) * 4
                atlas.pixels[ap] = UInt8(sumR / opaqueCount)
                atlas.pixels[ap + 1] = UInt8(sumG / opaqueCount)
                atlas.pixels[ap + 2] = UInt8(sumB / opaqueCount)
                atlas.pixels[ap + 3] = 255
            }
        }
    }
}

/// Adds Simo Häyhä's iconic "White Death" winter snow mask across his lower face
/// (nose, cheeks, mouth, chin) while keeping his eyes, brow, ushanka hood, and hands crisp!
func applySimoSpriteCellMask(atlas: inout RGBAImage, cellCol: Int, cellRow: Int) {
    let x0 = cellCol * CELL_W
    let y0 = cellRow * CELL_H
    var minX = CELL_W, maxX = -1, minY = CELL_H, maxY = -1
    var isSkin = [Bool](repeating: false, count: CELL_W * CELL_H)
    for ly in 0..<CELL_H {
        for lx in 0..<CELL_W {
            let p = ((y0 + ly) * atlas.width + (x0 + lx)) * 4
            if atlas.pixels[p + 3] < 128 { continue }
            if lx < minX { minX = lx }; if lx > maxX { maxX = lx }
            if ly < minY { minY = ly }; if ly > maxY { maxY = ly }
            let r = Int(atlas.pixels[p]), g = Int(atlas.pixels[p + 1]), b = Int(atlas.pixels[p + 2])
            if r >= 152 && r > g + 14 && g > b + 7 && b < 175 && (r - b) >= 24 {
                isSkin[ly * CELL_W + lx] = true
            }
        }
    }
    if maxY <= minY { return }
    let figH = max(1, maxY - minY + 1)

    // Find ALL connected warm-skin clusters across the entire cell (handles standing,
    // crouching, jumping, knockdown, KO, getup, and prone sniper poses!).
    var visited = [Bool](repeating: false, count: CELL_W * CELL_H)
    var bestCluster: [(Int, Int)] = []
    var bestScore = -1_000_000

    for ly in minY...maxY {
        for lx in minX...maxX {
            let start = ly * CELL_W + lx
            if !isSkin[start] || visited[start] { continue }
            var queue = [(lx, ly)]
            visited[start] = true
            var head = 0
            while head < queue.count {
                let (cx, cy) = queue[head]; head += 1
                for dy in -2...2 {
                    for dx in -2...2 {
                        let nx = cx + dx, ny = cy + dy
                        if nx < minX || nx > maxX || ny < minY || ny > maxY { continue }
                        let ni = ny * CELL_W + nx
                        if isSkin[ni] && !visited[ni] {
                            visited[ni] = true
                            queue.append((nx, ny))
                        }
                    }
                }
            }
            if queue.count < 4 { continue }
            let cMinX = queue.map { $0.0 }.min()!
            let cMaxX = queue.map { $0.0 }.max()!
            let cMinY = queue.map { $0.1 }.min()!
            let cMaxY = queue.map { $0.1 }.max()!

            // Score cluster: face sits inside white ushanka hood (white pixels above/sides),
            // whereas hands touch the dark brown wooden rifle!
            var whiteHoodCount = 0
            var brownWoodCount = 0
            for sy in max(0, cMinY - 4)...min(CELL_H - 1, cMaxY + 2) {
                for sx in max(0, cMinX - 4)...min(CELL_W - 1, cMaxX + 4) {
                    if isSkin[sy * CELL_W + sx] { continue }
                    let p = ((y0 + sy) * atlas.width + (x0 + sx)) * 4
                    if atlas.pixels[p + 3] < 128 { continue }
                    let r = Int(atlas.pixels[p]), g = Int(atlas.pixels[p + 1]), b = Int(atlas.pixels[p + 2])
                    let sat = max(r, max(g, b)) - min(r, min(g, b))
                    if r >= 182 && g >= 188 && b >= 192 && sat <= 26 {
                        whiteHoodCount += (sy < cMinY ? 3 : 1)
                    } else if r >= 65 && r <= 148 && r > g + 16 && g > b + 10 {
                        brownWoodCount += 1
                    }
                }
            }
            let relY = Double(cMinY - minY) / Double(figH)
            let heightBonus = Int((1.0 - relY) * 60.0)
            let score = whiteHoodCount * 3 - brownWoodCount * 4 + heightBonus + min(queue.count, 40)
            if score > bestScore {
                bestScore = score
                bestCluster = queue
            }
        }
    }

    if bestCluster.count < 4 { return }
    let sMinY = bestCluster.map { $0.1 }.min()!
    let sMaxY = bestCluster.map { $0.1 }.max()!
    let sMinX = bestCluster.map { $0.0 }.min()!
    let sMaxX = bestCluster.map { $0.0 }.max()!
    let faceH = sMaxY - sMinY + 1
    if faceH < 3 { return }
    // Cover nose, cheeks, mouth & chin (~lower 68% of head skin) while keeping fierce eyes & brow visible!
    let maskStartY = sMinY + max(2, Int(floor(Double(faceH) * 0.32)))
    let midX = (sMinX + sMaxX) / 2
    for (lx, ly) in bestCluster where ly >= maskStartY {
        let p = ((y0 + ly) * atlas.width + (x0 + lx)) * 4
        if ly == maskStartY {
            atlas.pixels[p] = 165
            atlas.pixels[p + 1] = 180
            atlas.pixels[p + 2] = 194
        } else if ly >= sMaxY - 1 || lx < midX {
            atlas.pixels[p] = 204
            atlas.pixels[p + 1] = 216
            atlas.pixels[p + 2] = 226
        } else {
            atlas.pixels[p] = 240
            atlas.pixels[p + 1] = 245
            atlas.pixels[p + 2] = 249
        }
    }
}

/// Applies Simo Häyhä's pixel-art-quantized White Death snow balaclava to his cut-in portrait.
func applySimoCutinMask(_ img: inout RGBAImage) {
    let w = img.width
    let h = img.height
    // Strictly Simo's face box above the rifle receiver (x ~ 244..336, y ~ 115..182).
    var minX = w, maxX = 0, minY = h, maxY = 0
    for y in Int(Double(h) * 0.23)..<Int(Double(h) * 0.365) {
        for x in Int(Double(w) * 0.345)..<Int(Double(w) * 0.485) {
            let p = (y * w + x) * 4
            if img.pixels[p + 3] < 128 { continue }
            let r = Int(img.pixels[p]), g = Int(img.pixels[p + 1]), b = Int(img.pixels[p + 2])
            if r >= 175 && r > g + 22 && g > b + 14 && b < 165 {
                if x < minX { minX = x }; if x > maxX { maxX = x }
                if y < minY { minY = y }; if y > maxY { maxY = y }
            }
        }
    }
    if maxY <= minY || maxX <= minX { return }
    let maskTopY = minY + Int(Double(maxY - minY) * 0.48)
    let maskBotY = min(Int(Double(h) * 0.37), maxY + 4)
    let maskMaxX = min(Int(Double(w) * 0.485), maxX + 2)
    let block = 4
    for by in stride(from: maskTopY, to: maskBotY, by: block) {
        for bx in stride(from: minX, to: maskMaxX, by: block) {
            var skinCount = 0
            var total = 0
            for dy in 0..<block {
                let y = by + dy
                if y < 0 || y >= h { continue }
                for dx in 0..<block {
                    let x = bx + dx
                    if x < 0 || x >= w { continue }
                    total += 1
                    let p = (y * w + x) * 4
                    if img.pixels[p + 3] < 128 { continue }
                    let r = Int(img.pixels[p]), g = Int(img.pixels[p + 1]), b = Int(img.pixels[p + 2])
                    // Strictly bright peach face skin (excludes darker brown rifle stock & black receiver!)
                    if r >= 165 && r > g + 20 && g > b + 12 && b < 165 {
                        skinCount += 1
                    }
                }
            }
            if total == 0 || skinCount * 2 < total { continue }
            let relY = by - maskTopY
            let relX = Double(bx - minX) / Double(max(1, maskMaxX - minX))
            let (mr, mg, mb): (UInt8, UInt8, UInt8)
            if relY < block {
                (mr, mg, mb) = (78, 92, 106)
            } else if relY < block * 2 {
                (mr, mg, mb) = relX > 0.65 ? (212, 222, 230) : (242, 246, 249)
            } else if (relY / block) % 2 == 0 && relX > 0.25 && relX < 0.78 {
                (mr, mg, mb) = (214, 224, 232)
            } else if relX < 0.22 || relX > 0.78 || by >= maskBotY - block {
                (mr, mg, mb) = (178, 192, 204)
            } else {
                (mr, mg, mb) = (236, 242, 246)
            }
            for dy in 0..<block {
                let y = by + dy
                if y < 0 || y >= h { continue }
                for dx in 0..<block {
                    let x = bx + dx
                    if x < 0 || x >= w { continue }
                    let p = (y * w + x) * 4
                    if img.pixels[p + 3] < 128 { continue }
                    let r = Int(img.pixels[p]), g = Int(img.pixels[p + 1]), b = Int(img.pixels[p + 2])
                    if r >= 160 && r > g + 18 && g > b + 10 {
                        img.pixels[p] = mr
                        img.pixels[p + 1] = mg
                        img.pixels[p + 2] = mb
                    }
                }
            }
        }
    }
}

/// Strips a painted colorful anime-streak cut-in background right up to the sprite's crisp dark pixel outline.
func removePaintedCutinBackground(_ img: inout RGBAImage) {
    let w = img.width, h = img.height, n = w * h
    var isBg = [Bool](repeating: false, count: n)
    var queue = [Int]()
    queue.reserveCapacity(n / 2)

    func isTealBg(_ idx: Int) -> Bool {
        let p = idx * 4
        let r = Int(img.pixels[p]), g = Int(img.pixels[p + 1]), b = Int(img.pixels[p + 2])
        // Deep/saturated ocean teal ONLY (r < 95 strictly protects bright silver-blue Kampilan steel blade!).
        return r < 95 && g > r + 18 && b > r + 16
    }

    func canFloodAsBg(_ idx: Int) -> Bool {
        let p = idx * 4
        let r = Int(img.pixels[p]), g = Int(img.pixels[p + 1]), b = Int(img.pixels[p + 2])
        let lum = (r * 299 + g * 587 + b * 114) / 1000
        // Always flood saturated ocean teal (even darker teal shadows), NEVER bright pale steel.
        if r < 95 && g > r + 12 && b > r + 10 { return true }
        // Stop at true dark black pixel-art outlines and hair/wood shadows.
        if lum < 52 { return false }
        // Protect silver/gray/white-blue steel Kampilan sword blade (bright or low saturation).
        let maxC = max(r, max(g, b)), minC = min(r, min(g, b))
        let sat = maxC - minC
        if sat <= 46 || (r >= 135 && g >= 145 && b >= 155) { return false }
        // Protect warm tan/brown skin & brown wooden Kalasag shield tones (medium orange-brown).
        let isBrownSkinOrWood = (r >= 85 && r <= 230 && g >= 42 && g <= 168 && b >= 16 && b <= 118 && (r - g) <= 95 && (g - b) >= 12)
        if isBrownSkinOrWood { return false }
        // Allow vivid crimson/orange/yellow energy streaks (including darker crimson streak edges).
        let isCrimsonStreak = (r >= 90 && g <= 58 && b <= 58 && (r - max(g, b)) >= 48)
        let isGoldStreak = (r >= 195 && g >= 130 && b <= 95 && (r - b) >= 110)
        let isOrangeStreak = (r >= 185 && g >= 68 && g <= 150 && b <= 58)
        return isCrimsonStreak || isGoldStreak || isOrangeStreak
    }

    // Seed from top, left, and right edges (NOT bottom edge where torso/shield anchor),
    // plus any obvious teal background pixels (handles enclosed gaps between sword/arm/head).
    for x in 0..<w {
        let topIdx = x
        if canFloodAsBg(topIdx) { isBg[topIdx] = true; queue.append(topIdx) }
    }
    for y in 0..<h {
        let lIdx = y * w
        let rIdx = y * w + (w - 1)
        if !isBg[lIdx] && canFloodAsBg(lIdx) { isBg[lIdx] = true; queue.append(lIdx) }
        if !isBg[rIdx] && canFloodAsBg(rIdx) { isBg[rIdx] = true; queue.append(rIdx) }
    }
    for idx in 0..<n {
        if !isBg[idx] && isTealBg(idx) {
            isBg[idx] = true
            queue.append(idx)
        }
    }

    // Flood-fill across teal + vivid energy streak pixels, stopping cleanly at dark outlines, skin, steel, and wood.
    var head = 0
    while head < queue.count {
        let idx = queue[head]; head += 1
        let x = idx % w, y = idx / w
        let neighbors = [
            x > 0 ? idx - 1 : -1,
            x + 1 < w ? idx + 1 : -1,
            y > 0 ? idx - w : -1,
            y + 1 < h ? idx + w : -1,
        ]
        for nb in neighbors where nb >= 0 && !isBg[nb] {
            if canFloodAsBg(nb) {
                isBg[nb] = true
                queue.append(nb)
            }
        }
    }

    // Clean up 1-2px dark-teal / crimson anti-aliased fringe along outer edge of background streaks.
    for _ in 0..<2 {
        var toErase = [Int]()
        for y in 1..<(h - 1) {
            let row = y * w
            for x in 1..<(w - 1) {
                let idx = row + x
                if isBg[idx] { continue }
                let touchesBg = isBg[idx - 1] || isBg[idx + 1] || isBg[idx - w] || isBg[idx + w]
                if !touchesBg { continue }
                let p = idx * 4
                let r = Int(img.pixels[p]), g = Int(img.pixels[p + 1]), b = Int(img.pixels[p + 2])
                if r < 95 && g > r + 8 && b > r + 6 {
                    toErase.append(idx)
                }
            }
        }
        for idx in toErase { isBg[idx] = true }
    }

    // Keep ONLY the single largest connected foreground component (Lapu-Lapu's full bust + sword + shield),
    // automatically dropping any floating detached red/gold background streak arcs!
    var vis = [Bool](repeating: false, count: n)
    var bestComp = [Int]()
    var bfs = [Int]()
    for idx in 0..<n {
        if isBg[idx] || vis[idx] { continue }
        bfs.removeAll(keepingCapacity: true)
        vis[idx] = true
        bfs.append(idx)
        var h2 = 0
        while h2 < bfs.count {
            let c = bfs[h2]; h2 += 1
            let cx = c % w, cy = c / w
            for dy in -1...1 {
                let ny = cy + dy
                if ny < 0 || ny >= h { continue }
                let row = ny * w
                for dx in -1...1 {
                    let nx = cx + dx
                    if nx < 0 || nx >= w { continue }
                    let ni = row + nx
                    if !isBg[ni] && !vis[ni] {
                        vis[ni] = true
                        bfs.append(ni)
                    }
                }
            }
        }
        if bfs.count > bestComp.count {
            bestComp = bfs
        }
    }
    var keep = [Bool](repeating: false, count: n)
    for idx in bestComp { keep[idx] = true }

    for idx in 0..<n {
        if isBg[idx] || !keep[idx] {
            let p = idx * 4
            img.pixels[p] = 0; img.pixels[p + 1] = 0; img.pixels[p + 2] = 0; img.pixels[p + 3] = 0
        } else {
            img.pixels[idx * 4 + 3] = 255
        }
    }
}

func processCutin(srcPath: String, dstPath: String, artId: String) {
    guard var img = loadRGBA(path: srcPath) else { return }
    if artId == "lapulapu" {
        removePaintedCutinBackground(&img)
    } else {
        removeBackground(&img)
    }
    // Keep only main character + connected/nearby weapon components (drops stray snow/confetti specks!).
    let w0 = img.width, h0 = img.height, n0 = w0 * h0
    var visited = [Bool](repeating: false, count: n0)
    var blobs = [Blob]()
    var queue = [Int]()
    for idx in 0..<n0 {
        if visited[idx] || img.pixels[idx * 4 + 3] == 0 { continue }
        queue.removeAll(keepingCapacity: true)
        visited[idx] = true
        queue.append(idx)
        var head = 0
        var minX = w0, minY = h0, maxX = 0, maxY = 0
        var sx = 0.0, sy = 0.0
        while head < queue.count {
            let c = queue[head]; head += 1
            let x = c % w0, y = c / w0
            if x < minX { minX = x }; if x > maxX { maxX = x }
            if y < minY { minY = y }; if y > maxY { maxY = y }
            sx += Double(x); sy += Double(y)
            let yA = max(0, y - 1), yB = min(h0 - 1, y + 1)
            let xA = max(0, x - 1), xB = min(w0 - 1, x + 1)
            for ny in yA...yB {
                let row = ny * w0
                for nx in xA...xB {
                    let ni = row + nx
                    if !visited[ni] && img.pixels[ni * 4 + 3] > 0 {
                        visited[ni] = true
                        queue.append(ni)
                    }
                }
            }
        }
        let cnt = Double(queue.count)
        blobs.append(Blob(pixels: queue, minX: minX, minY: minY, maxX: maxX, maxY: maxY, cx: sx / cnt, cy: sy / cnt))
    }
    if blobs.isEmpty { return }
    blobs.sort { $0.pixels.count > $1.pixels.count }
    let main = blobs[0]
    var keepMask = [Bool](repeating: false, count: n0)
    for b in blobs {
        // Keep main portrait plus significant weapon/lightning bursts; drop stray snow/dust specks.
        let dx = max(Double(main.minX) - b.cx, max(0.0, b.cx - Double(main.maxX)))
        let dy = max(Double(main.minY) - b.cy, max(0.0, b.cy - Double(main.maxY)))
        let dist = hypot(dx, dy)
        if b.pixels.count >= 2400 || (b.pixels.count >= 900 && dist < 35.0) {
            for p in b.pixels { keepMask[p] = true }
        }
    }
    for idx in 0..<n0 where !keepMask[idx] {
        let p = idx * 4
        img.pixels[p] = 0; img.pixels[p + 1] = 0; img.pixels[p + 2] = 0; img.pixels[p + 3] = 0
    }

    guard let crop = extractCellCrop(img, x0: 0, y0: 0, x1: img.width, y1: img.height) else { return }

    let outW = 700
    let outH = 500
    var out = RGBAImage(width: outW, height: outH, pixels: [UInt8](repeating: 0, count: outW * outH * 4))
    let scale = min(Double(outW - 12) / Double(crop.width), Double(outH - 12) / Double(crop.height))
    let w = max(1, Int(round(Double(crop.width) * scale)))
    let h = max(1, Int(round(Double(crop.height) * scale)))
    let dx0 = (outW - w) / 2
    let dy0 = outH - h
    let inv = 1.0 / scale

    for ty in 0..<h {
        let sy0 = crop.minY + Int(floor(Double(ty) * inv))
        let sy1 = min(crop.maxY, max(sy0, crop.minY + Int(ceil(Double(ty + 1) * inv)) - 1))
        for tx in 0..<w {
            let sx0 = crop.minX + Int(floor(Double(tx) * inv))
            let sx1 = min(crop.maxX, max(sx0, crop.minX + Int(ceil(Double(tx + 1) * inv)) - 1))
            var sr = 0, sg = 0, sb = 0, oc = 0, tc = 0
            for sy in sy0...sy1 {
                for sx in sx0...sx1 {
                    tc += 1
                    let sp = (sy * img.width + sx) * 4
                    if img.pixels[sp + 3] > 0 {
                        oc += 1
                        sr += Int(img.pixels[sp])
                        sg += Int(img.pixels[sp + 1])
                        sb += Int(img.pixels[sp + 2])
                    }
                }
            }
            if tc > 0 && Double(oc) / Double(tc) >= 0.45 {
                let ap = ((dy0 + ty) * outW + (dx0 + tx)) * 4
                out.pixels[ap] = UInt8(sr / oc)
                out.pixels[ap + 1] = UInt8(sg / oc)
                out.pixels[ap + 2] = UInt8(sb / oc)
                out.pixels[ap + 3] = 255
            }
        }
    }
    if artId == "simo" {
        applySimoCutinMask(&out)
    }
    _ = savePNG(image: out, path: dstPath)
}

func writeSpriteFramesTres(
    warriorId: String,
    sheetResPath: String,
    animFrames: [String: [(col: Int, row: Int)]],
    outPath: String
) {
    var subResources = [String]()
    var subIdCounter = 0
    var animSubIds: [String: [String]] = [:]

    for anim in ANIM_ORDER {
        guard let coords = animFrames[anim], !coords.isEmpty else { continue }
        var ids = [String]()
        for (col, row) in coords {
            subIdCounter += 1
            let sid = "AtlasTexture_\(subIdCounter)"
            ids.append(sid)
            subResources.append("""
            [sub_resource type="AtlasTexture" id="\(sid)"]
            atlas = ExtResource("1_sheet")
            region = Rect2(\(col * CELL_W), \(row * CELL_H), \(CELL_W), \(CELL_H))
            """)
        }
        animSubIds[anim] = ids
    }

    let loadSteps = subIdCounter + 2
    var lines = [String]()
    lines.append("[gd_resource type=\"SpriteFrames\" load_steps=\(loadSteps) format=3]")
    lines.append("")
    lines.append("[ext_resource type=\"Texture2D\" path=\"\(sheetResPath)\" id=\"1_sheet\"]")
    lines.append("")
    for sr in subResources {
        lines.append(sr)
        lines.append("")
    }

    lines.append("[resource]")
    var animBlocks = [String]()
    for anim in ANIM_ORDER {
        guard let ids = animSubIds[anim] else { continue }
        let frameEntries = ids.map { sid in
            """
            {
            "duration": 1.0,
            "texture": SubResource("\(sid)")
            }
            """
        }.joined(separator: ", ")
        let loopStr = LOOPING_ANIMS.contains(anim) ? "true" : "false"
        let fps = ANIM_FPS[anim] ?? 10.0
        animBlocks.append("""
        {
        "frames": [\(frameEntries)],
        "loop": \(loopStr),
        "name": &"\(anim)",
        "speed": \(fps)
        }
        """)
    }
    lines.append("animations = [\(animBlocks.joined(separator: ", "))]")
    lines.append("")

    let url = URL(fileURLWithPath: outPath)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
}

func parseManifest(path: String) -> [ManifestEntry] {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
    var entries = [ManifestEntry]()
    for (idx, rawLine) in text.split(separator: "\n").enumerated() {
        if idx == 0 { continue }
        let parts = rawLine.split(separator: ",", omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        if parts.count < 6 { continue }
        guard let frames = Int(parts[3]) else { continue }
        entries.append(ManifestEntry(
            file: parts[0],
            champion: parts[1],
            animation: parts[2],
            frames: frames,
            layout: parts[4],
            background: parts[5]
        ))
    }
    return entries
}

func processChampion(artId: String, entries: [ManifestEntry], rootDir: String) {
    guard let warriorId = ART_TO_WARRIOR[artId] else {
        print("Unknown art id: \(artId)")
        return
    }
    let standHeight = STAND_HEIGHT_OVERRIDES[artId] ?? 84.0
    let champEntries = entries.filter { $0.champion == artId }
    var byAnim: [String: ManifestEntry] = [:]
    for e in champEntries { byAnim[e.animation] = e }

    // Auto-discover any directional attack sheets present on disk even if not yet in manifest.csv.
    let directionalSpecs: [(String, Int, String)] = [
        ("forward_light", 4, "2x2"),
        ("back_light", 3, "1 row"),
        ("jump_light", 3, "1 row"),
        ("forward_heavy", 4, "2x2"),
        ("back_heavy", 4, "2x2"),
        ("jump_heavy", 4, "2x2"),
    ]
    for (anim, frames, layout) in directionalSpecs {
        if byAnim[anim] == nil {
            let rel = "sheets/\(artId)/\(anim).png"
            if FileManager.default.fileExists(atPath: "\(rootDir)/art_source/sprites/\(rel)") {
                byAnim[anim] = ManifestEntry(file: rel, champion: artId, animation: anim, frames: frames, layout: layout, background: "auto")
            }
        }
    }

    // Count total animation frames (excluding cutin) to size the atlas.
    var totalFrames = 0
    for anim in ANIM_ORDER {
        if anim == "ultimate" {
            totalFrames += (byAnim["ultimate_1"]?.frames ?? 0) + (byAnim["ultimate_2"]?.frames ?? 0)
        } else {
            totalFrames += byAnim[anim]?.frames ?? 0
        }
    }
    let atlasRows = (totalFrames + ATLAS_COLS - 1) / ATLAS_COLS
    var atlas = RGBAImage(
        width: ATLAS_COLS * CELL_W,
        height: atlasRows * CELL_H,
        pixels: [UInt8](repeating: 0, count: ATLAS_COLS * CELL_W * atlasRows * CELL_H * 4)
    )

    var animCoords: [String: [(col: Int, row: Int)]] = [:]
    var nextCell = 0
    var targetBodyArea = 0.0

    func processSheet(_ entry: ManifestEntry, intoAnim targetAnim: String) {
        let srcPath = "\(rootDir)/art_source/sprites/\(entry.file)"
        guard var img = loadRGBA(path: srcPath) else {
            print("  WARN: failed to load \(srcPath)")
            return
        }
        removeBackground(&img)

        let rowCounts = rowCountsForLayout(entry.layout, frames: entry.frames)
        var crops: [FrameCrop]
        if let compCrops = extractFiguresByComponents(img, expectedFrames: entry.frames, rowCounts: rowCounts) {
            crops = compCrops
        } else {
            var rowBounds: [(Int, Int)] = []
            if rowCounts.count == 1 {
                rowBounds = [(0, img.height)]
            } else {
                let splitY = findHorizontalSplit(img)
                rowBounds = [(0, splitY), (splitY, img.height)]
            }
            crops = [FrameCrop]()
            for (rIdx, count) in rowCounts.enumerated() {
                let (y0, y1) = rowBounds[rIdx]
                let xSplits = findVerticalSplits(img, y0: y0, y1: y1, count: count)
                for cIdx in 0..<count {
                    if let crop = extractCellCrop(img, x0: xSplits[cIdx], y0: y0, x1: xSplits[cIdx + 1], y1: y1) {
                        crops.append(crop)
                    } else {
                        print("  WARN: empty cell in \(entry.file) row \(rIdx) col \(cIdx)")
                    }
                }
            }
        }
        let scales = scalesForAnimation(anim: entry.animation, crops: crops, standHeight: standHeight, targetBodyArea: targetBodyArea)
        if entry.animation == "idle" && !crops.isEmpty {
            let scaledAreas = zip(crops, scales).map { Double($0.0.pixelArea) * $0.1 * $0.1 }.sorted()
            targetBodyArea = scaledAreas[scaledAreas.count / 2]
        }
        var list = animCoords[targetAnim] ?? []
        for (idx, crop) in crops.enumerated() {
            let col = nextCell % ATLAS_COLS
            let row = nextCell / ATLAS_COLS
            blitFrameToAtlas(src: img, crop: crop, scale: scales[idx], atlas: &atlas, cellCol: col, cellRow: row)
            if artId == "simo" {
                applySimoSpriteCellMask(atlas: &atlas, cellCol: col, cellRow: row)
            }
            list.append((col, row))
            nextCell += 1
        }
        animCoords[targetAnim] = list
    }

    for anim in ANIM_ORDER {
        if anim == "ultimate" {
            if let u1 = byAnim["ultimate_1"] { processSheet(u1, intoAnim: "ultimate") }
            if let u2 = byAnim["ultimate_2"] { processSheet(u2, intoAnim: "ultimate") }
        } else if let e = byAnim[anim] {
            processSheet(e, intoAnim: anim)
        }
    }

    let outDir = "\(rootDir)/assets/sprites/champions/\(warriorId)"
    let sheetPath = "\(outDir)/sheet.png"
    let tresPath = "\(outDir)/\(warriorId)_frames.tres"
    let cutinPath = "\(outDir)/cutin.png"
    let sheetResPath = "res://assets/sprites/champions/\(warriorId)/sheet.png"

    _ = savePNG(image: atlas, path: sheetPath)
    writeSpriteFramesTres(warriorId: warriorId, sheetResPath: sheetResPath, animFrames: animCoords, outPath: tresPath)

    if let cutin = byAnim["cutin"] {
        processCutin(srcPath: "\(rootDir)/art_source/sprites/\(cutin.file)", dstPath: cutinPath, artId: artId)
    }

    print("OK \(artId) -> \(warriorId): \(nextCell) frames (\(ATLAS_COLS)x\(atlasRows) atlas) -> \(sheetResPath)")
}

// --- FX Sheet Processor (black-background additive/transparent FX sheets) ---

func removeBlackBackground(_ img: inout RGBAImage, hardCutout: Bool) {
    let n = img.width * img.height
    for idx in 0..<n {
        let p = idx * 4
        let r = Int(img.pixels[p])
        let g = Int(img.pixels[p + 1])
        let b = Int(img.pixels[p + 2])
        let mx = max(r, max(g, b))
        if hardCutout {
            // Solid physical objects (Roman Legionaries, Viking Axe, Hammer): crisp hard cutout!
            if mx < 24 {
                img.pixels[p] = 0; img.pixels[p + 1] = 0; img.pixels[p + 2] = 0; img.pixels[p + 3] = 0
            } else {
                img.pixels[p + 3] = 255
            }
        } else {
            // Luminous energy FX (lightning, slashes, fire, muzzle flashes, sparks, auras):
            // smooth black-to-alpha feathering so additive glow blooms seamlessly over any stage!
            if mx < 16 {
                img.pixels[p] = 0; img.pixels[p + 1] = 0; img.pixels[p + 2] = 0; img.pixels[p + 3] = 0
            } else if mx < 76 {
                let a = Int(Double(mx - 16) / 60.0 * 255.0)
                img.pixels[p + 3] = UInt8(max(0, min(255, a)))
            } else {
                img.pixels[p + 3] = 255
            }
        }
    }
}

func processFXSheets(entries: [ManifestEntry], rootDir: String) {
    let fxEntries = entries.filter { $0.champion == "fx" }
    let outDir = "\(rootDir)/assets/sprites/fx"
    try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

    let solidFX: Set<String> = ["caesar_legionary", "ragnar_axe_spin", "thor_hammer_spin"]
    for entry in fxEntries {
        let srcPath = "\(rootDir)/art_source/sprites/\(entry.file)"
        guard var img = loadRGBA(path: srcPath) else { continue }
        let name = entry.animation
        let isSolid = solidFX.contains(name)
        removeBlackBackground(&img, hardCutout: isSolid)

        let rowCounts = rowCountsForLayout(entry.layout, frames: entry.frames)
        var rowBounds: [(Int, Int)] = []
        if rowCounts.count == 1 {
            rowBounds = [(0, img.height)]
        } else {
            let splitY = img.height / 2
            rowBounds = [(0, splitY), (splitY, img.height)]
        }

        // High-detail crisp FX resolution for smooth glowing ultimates & impacts!
        let cellW: Int
        let cellH: Int
        if name == "zeus_sky_bolt" {
            cellW = 144; cellH = 256
        } else if name.hasPrefix("aura_") {
            cellW = 144; cellH = 144
        } else if name == "caesar_legionary" {
            cellW = 128; cellH = 128
        } else if name == "simo_tracer" {
            cellW = 224; cellH = 64
        } else {
            cellW = 144; cellH = 144
        }

        var strip = RGBAImage(
            width: cellW * entry.frames,
            height: cellH,
            pixels: [UInt8](repeating: 0, count: cellW * entry.frames * cellH * 4)
        )

        var frameIdx = 0
        for (rIdx, count) in rowCounts.enumerated() {
            let (y0, y1) = rowBounds[rIdx]
            let srcCellW = img.width / count
            let srcCellH = y1 - y0
            let scale = min(Double(cellW - 4) / Double(srcCellW), Double(cellH - 4) / Double(srcCellH))
            let outW = max(1, Int(round(Double(srcCellW) * scale)))
            let outH = max(1, Int(round(Double(srcCellH) * scale)))
            let offX = (cellW - outW) / 2
            let offY = (cellH - outH) / 2
            let inv = 1.0 / scale

            for cIdx in 0..<count {
                let sxBase = cIdx * srcCellW
                let dxBase = frameIdx * cellW + offX
                for ty in 0..<outH {
                    let sy = min(y1 - 1, y0 + Int(Double(ty) * inv))
                    for tx in 0..<outW {
                        let sx = min(img.width - 1, sxBase + Int(Double(tx) * inv))
                        let sp = (sy * img.width + sx) * 4
                        let a = img.pixels[sp + 3]
                        if a > 0 {
                            let dp = ((offY + ty) * strip.width + (dxBase + tx)) * 4
                            strip.pixels[dp] = img.pixels[sp]
                            strip.pixels[dp + 1] = img.pixels[sp + 1]
                            strip.pixels[dp + 2] = img.pixels[sp + 2]
                            strip.pixels[dp + 3] = a
                        }
                    }
                }
                frameIdx += 1
            }
        }

        let pngPath = "\(outDir)/\(name).png"
        let tresPath = "\(outDir)/\(name)_frames.tres"
        _ = savePNG(image: strip, path: pngPath)

        // Write clean SpriteFrames .tres for this FX
        let loopFX = name.hasPrefix("aura_") || name == "caesar_legionary" || name.hasSuffix("_spin") || name == "zeus_bolt_flight" || name == "zeus_ground_electricity" || name == "simo_tracer"
        let fps: Double = name.hasPrefix("hit_spark") || name == "block_spark" ? 18.0 : 12.0
        var lines = [String]()
        lines.append("[gd_resource type=\"SpriteFrames\" load_steps=\(entry.frames + 2) format=3]")
        lines.append("")
        lines.append("[ext_resource type=\"Texture2D\" path=\"res://assets/sprites/fx/\(name).png\" id=\"1_fx\"]")
        lines.append("")
        var fEntries = [String]()
        for i in 0..<entry.frames {
            let sid = "AtlasTexture_\(i + 1)"
            lines.append("[sub_resource type=\"AtlasTexture\" id=\"\(sid)\"]")
            lines.append("atlas = ExtResource(\"1_fx\")")
            lines.append("region = Rect2(\(i * cellW), 0, \(cellW), \(cellH))")
            lines.append("")
            fEntries.append("{\n\"duration\": 1.0,\n\"texture\": SubResource(\"\(sid)\")\n}")
        }
        lines.append("[resource]")
        lines.append("animations = [{\n\"frames\": [\(fEntries.joined(separator: ", "))],\n\"loop\": \(loopFX ? "true" : "false"),\n\"name\": &\"default\",\n\"speed\": \(fps)\n}]")
        lines.append("")
        try? lines.joined(separator: "\n").write(to: URL(fileURLWithPath: tresPath), atomically: true, encoding: .utf8)
    }
    print("OK FX: processed \(fxEntries.count) FX sheets -> assets/sprites/fx/")
}

// --- Main ---
let rootDir = FileManager.default.currentDirectoryPath
let manifest = parseManifest(path: "\(rootDir)/art_source/sprites/manifest.csv")
let args = Array(CommandLine.arguments.dropFirst())
if args.contains("fx") {
    processFXSheets(entries: manifest, rootDir: rootDir)
}
let filtered = args.filter { $0 != "fx" }
let targets: [String]
if filtered.isEmpty && args.contains("fx") {
    targets = []
} else if filtered.isEmpty || filtered.contains("playable") {
    targets = ["leonidas", "caesar", "ragnar", "musashi", "lapulapu", "simo", "naikhanomtom", "zeus"]
} else if filtered.contains("all") {
    targets = ["leonidas", "caesar", "ragnar", "musashi", "lapulapu", "simo", "naikhanomtom", "zeus", "thor", "susanoo", "anubis"]
} else {
    targets = filtered
}

for t in targets {
    processChampion(artId: t, entries: manifest, rootDir: rootDir)
}
