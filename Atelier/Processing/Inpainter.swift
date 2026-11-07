import Foundation
import simd

/// Content-aware fill: multi-scale PatchMatch + EM voting (Wexler / Barnes style).
/// Runs on the CPU, in a cropped region around the hole.
enum Inpainter {
    static let r = 3              // patch radius → 7x7 patches
    static let maxWorkPixels = 1_800_000

    // MARK: - Public entry

    static func inpaint(_ input: RGBABuffer, mask: [UInt8], progress: @escaping @Sendable (Double) -> Void) -> RGBABuffer {
        let W = input.width, H = input.height
        guard W > 0, H > 0, mask.count == W * H else { return input }

        var hole = [Bool](repeating: false, count: W * H)
        for i in 0..<(W * H) where mask[i] > 8 { hole[i] = true }
        hole = dilate(hole, w: W, h: H, radius: 2)

        var minX = W, minY = H, maxX = -1, maxY = -1
        for y in 0..<H {
            let row = y * W
            for x in 0..<W where hole[row + x] {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= 0 else { return input }

        let bw = maxX - minX + 1, bh = maxY - minY + 1
        let margin = max(48, Int(Double(max(bw, bh)) * 0.9))
        let rx0 = max(0, minX - margin), ry0 = max(0, minY - margin)
        let rx1 = min(W - 1, maxX + margin), ry1 = min(H - 1, maxY + margin)
        let rw = rx1 - rx0 + 1, rh = ry1 - ry0 + 1

        // Work resolution
        let k = max(1, Int(ceil(sqrt(Double(rw * rh) / Double(maxWorkPixels)))))
        let lw = (rw + k - 1) / k, lh = (rh + k - 1) / k
        let base = Level(w: lw, h: lh)
        let inv: Float = 1.0 / 255.0
        for ly in 0..<lh {
            for lx in 0..<lw {
                var acc = SIMD4<Float>(repeating: 0)
                var n: Float = 0
                var anyHole = false
                for dy in 0..<k {
                    let y = ly * k + dy
                    if y >= rh { break }
                    for dx in 0..<k {
                        let x = lx * k + dx
                        if x >= rw { break }
                        let si = (y + ry0) * W + (x + rx0)
                        if hole[si] { anyHole = true; continue }
                        let pi = si * 4
                        acc += SIMD4<Float>(Float(input.pixels[pi]), Float(input.pixels[pi + 1]),
                                            Float(input.pixels[pi + 2]), Float(input.pixels[pi + 3])) * inv
                        n += 1
                    }
                }
                let li = ly * lw + lx
                base.hole[li] = anyHole
                if n > 0 {
                    let v = acc / n
                    base.img[li * 4] = v.x
                    base.img[li * 4 + 1] = v.y
                    base.img[li * 4 + 2] = v.z
                    base.img[li * 4 + 3] = v.w
                }
            }
        }

        let result = solve(base, progress: progress)

        // Write back
        var out = input
        for y in 0..<rh {
            for x in 0..<rw {
                let si = (y + ry0) * W + (x + rx0)
                guard hole[si] else { continue }
                let v: SIMD4<Float>
                if k == 1 {
                    v = result.pixel(x, y)
                } else {
                    let fx = (Float(x) + 0.5) / Float(k) - 0.5
                    let fy = (Float(y) + 0.5) / Float(k) - 0.5
                    v = result.bilinear(fx, fy)
                }
                let a = min(max(v.w, 0), 1)
                let pi = si * 4
                out.pixels[pi] = UInt8((min(max(v.x, 0), a) * 255).rounded())
                out.pixels[pi + 1] = UInt8((min(max(v.y, 0), a) * 255).rounded())
                out.pixels[pi + 2] = UInt8((min(max(v.z, 0), a) * 255).rounded())
                out.pixels[pi + 3] = UInt8((a * 255).rounded())
            }
        }
        progress(1)
        return out
    }

    // MARK: - Level

    final class Level {
        let w: Int
        let h: Int
        var img: [Float]
        var hole: [Bool]
        var valid: [Bool] = []
        var validList: [Int32] = []
        var targets: [Int32] = []

        init(w: Int, h: Int) {
            self.w = w
            self.h = h
            img = [Float](repeating: 0, count: w * h * 4)
            hole = [Bool](repeating: false, count: w * h)
        }

        func pixel(_ x: Int, _ y: Int) -> SIMD4<Float> {
            let i = (y * w + x) * 4
            return SIMD4<Float>(img[i], img[i + 1], img[i + 2], img[i + 3])
        }

        func bilinear(_ fx: Float, _ fy: Float) -> SIMD4<Float> {
            let cx = min(max(fx, 0), Float(w - 1))
            let cy = min(max(fy, 0), Float(h - 1))
            let x0 = Int(cx), y0 = Int(cy)
            let x1 = min(x0 + 1, w - 1), y1 = min(y0 + 1, h - 1)
            let tx = cx - Float(x0), ty = cy - Float(y0)
            let top = pixel(x0, y0) * (1 - tx) + pixel(x1, y0) * tx
            let bottom = pixel(x0, y1) * (1 - tx) + pixel(x1, y1) * tx
            return top * (1 - ty) + bottom * ty
        }

        /// Computes valid source centers (patch fully known & inside) and target centers (patch touches hole).
        func prepare() {
            let r = Inpainter.r
            let iw = w + 1
            var integ = [Int32](repeating: 0, count: (w + 1) * (h + 1))
            for y in 0..<h {
                var rowSum: Int32 = 0
                for x in 0..<w {
                    if hole[y * w + x] { rowSum += 1 }
                    integ[(y + 1) * iw + x + 1] = integ[y * iw + x + 1] + rowSum
                }
            }
            valid = [Bool](repeating: false, count: w * h)
            validList = []
            targets = []
            for y in 0..<h {
                let y0 = max(0, y - r), y1 = min(h - 1, y + r)
                for x in 0..<w {
                    let x0 = max(0, x - r), x1 = min(w - 1, x + r)
                    let s = integ[(y1 + 1) * iw + x1 + 1] - integ[y0 * iw + x1 + 1]
                          - integ[(y1 + 1) * iw + x0] + integ[y0 * iw + x0]
                    let idx = y * w + x
                    if s > 0 {
                        targets.append(Int32(idx))
                    } else if x >= r && y >= r && x < w - r && y < h - r {
                        valid[idx] = true
                        validList.append(Int32(idx))
                    }
                }
            }
        }
    }

    // MARK: - Solver

    static func solve(_ base: Level, progress: @escaping @Sendable (Double) -> Void) -> Level {
        base.prepare()
        if base.validList.count < 4 || base.targets.isEmpty {
            diffusionFill(base)
            return base
        }

        var levels = [base]
        while levels.count < 10 {
            let last = levels[levels.count - 1]
            if min(last.w, last.h) < 4 * r + 8 { break }
            let next = downsample(last)
            next.prepare()
            if next.validList.count < 200 { break }
            levels.append(next)
            var holeCount = 0
            for b in next.hole where b { holeCount += 1 }
            if holeCount <= 16 { break }
        }

        // Iteration schedule
        func emIters(_ li: Int) -> Int { li == 0 ? 2 : (li == 1 ? 3 : 5) }
        func pmIters(_ li: Int) -> Int { li == 0 ? 2 : 4 }
        var totalWork = 0.0
        for li in 0..<levels.count { totalWork += Double(emIters(li) * levels[li].targets.count * pmIters(li)) }
        var doneWork = 0.0

        var rng = XorShift(seed: 0x9E37_79B9_7F4A_7C15)
        let coarsest = levels[levels.count - 1]
        diffusionFill(coarsest)
        var nnf = [Int32](repeating: -1, count: coarsest.w * coarsest.h)
        var dist = [Float](repeating: .infinity, count: coarsest.w * coarsest.h)
        for t in coarsest.targets {
            nnf[Int(t)] = coarsest.validList[rng.next(coarsest.validList.count)]
        }

        for li in stride(from: levels.count - 1, through: 0, by: -1) {
            let L = levels[li]
            if li != levels.count - 1 {
                let C = levels[li + 1]
                nnf = upsample(nnf, from: C, to: L, rng: &rng)
                dist = [Float](repeating: .infinity, count: L.w * L.h)
                vote(L, nnf: nnf, dist: dist)
            }
            for _ in 0..<emIters(li) {
                patchMatch(L, nnf: &nnf, dist: &dist, iterations: pmIters(li), rng: &rng)
                vote(L, nnf: nnf, dist: dist)
                doneWork += Double(L.targets.count * pmIters(li))
                progress(min(0.99, doneWork / max(1, totalWork)))
            }
        }
        return levels[0]
    }

    static func downsample(_ f: Level) -> Level {
        let cw = (f.w + 1) / 2, ch = (f.h + 1) / 2
        let c = Level(w: cw, h: ch)
        for cy in 0..<ch {
            for cx in 0..<cw {
                var acc = SIMD4<Float>(repeating: 0)
                var n: Float = 0
                var anyHole = false
                for dy in 0..<2 {
                    let y = cy * 2 + dy
                    if y >= f.h { continue }
                    for dx in 0..<2 {
                        let x = cx * 2 + dx
                        if x >= f.w { continue }
                        let i = y * f.w + x
                        if f.hole[i] { anyHole = true; continue }
                        acc += f.pixel(x, y)
                        n += 1
                    }
                }
                let ci = cy * cw + cx
                c.hole[ci] = anyHole
                if n > 0 {
                    let v = acc / n
                    c.img[ci * 4] = v.x
                    c.img[ci * 4 + 1] = v.y
                    c.img[ci * 4 + 2] = v.z
                    c.img[ci * 4 + 3] = v.w
                }
            }
        }
        return c
    }

    /// Onion-peel fill used as initial guess at the coarsest level.
    static func diffusionFill(_ L: Level) {
        let w = L.w, h = L.h
        var known = L.hole.map { !$0 }
        var pending: [Int] = []
        for i in 0..<(w * h) where L.hole[i] { pending.append(i) }
        while !pending.isEmpty {
            var updates: [(Int, SIMD4<Float>)] = []
            var still: [Int] = []
            for i in pending {
                let x = i % w, y = i / w
                var acc = SIMD4<Float>(repeating: 0)
                var n: Float = 0
                for dy in -1...1 {
                    let yy = y + dy
                    if yy < 0 || yy >= h { continue }
                    for dx in -1...1 {
                        if dx == 0 && dy == 0 { continue }
                        let xx = x + dx
                        if xx < 0 || xx >= w { continue }
                        if known[yy * w + xx] {
                            acc += L.pixel(xx, yy)
                            n += 1
                        }
                    }
                }
                if n > 0 { updates.append((i, acc / n)) } else { still.append(i) }
            }
            if updates.isEmpty { break }
            for (i, v) in updates {
                L.img[i * 4] = v.x
                L.img[i * 4 + 1] = v.y
                L.img[i * 4 + 2] = v.z
                L.img[i * 4 + 3] = v.w
                known[i] = true
            }
            pending = still
        }
    }

    static func upsample(_ cnnf: [Int32], from C: Level, to F: Level, rng: inout XorShift) -> [Int32] {
        var nnf = [Int32](repeating: -1, count: F.w * F.h)
        for t in F.targets {
            let p = Int(t)
            let x = p % F.w, y = p / F.w
            let cx = min(x / 2, C.w - 1), cy = min(y / 2, C.h - 1)
            let cq = Int(cnnf[cy * C.w + cx])
            var q = -1
            if cq >= 0 {
                let qx = ((cq % C.w) * 2 + (x & 1)).clamped(r, F.w - 1 - r)
                let qy = ((cq / C.w) * 2 + (y & 1)).clamped(r, F.h - 1 - r)
                let cand = qy * F.w + qx
                if cand >= 0 && cand < F.w * F.h && F.valid[cand] { q = cand }
            }
            if q < 0 { q = Int(F.validList[rng.next(F.validList.count)]) }
            nnf[p] = Int32(q)
        }
        return nnf
    }

    // MARK: - PatchMatch

    @inline(__always)
    static func patchDistance(_ img: UnsafePointer<Float>, w: Int, h: Int,
                              px: Int, py: Int, qx: Int, qy: Int, cutoff: Float) -> Float {
        var d: Float = 0
        for dy in -r...r {
            let yy = py + dy
            if yy < 0 || yy >= h { continue }
            let prow = yy * w
            let qrow = (qy + dy) * w
            for dx in -r...r {
                let xx = px + dx
                if xx < 0 || xx >= w { continue }
                let a = (prow + xx) * 4
                let b = (qrow + qx + dx) * 4
                let d0 = img[a] - img[b]
                let d1 = img[a + 1] - img[b + 1]
                let d2 = img[a + 2] - img[b + 2]
                let d3 = img[a + 3] - img[b + 3]
                d += d0 * d0 + d1 * d1 + d2 * d2 + d3 * d3
            }
            if d >= cutoff { return d }
        }
        return d
    }

    static func patchMatch(_ L: Level, nnf: inout [Int32], dist: inout [Float], iterations: Int, rng: inout XorShift) {
        let w = L.w, h = L.h
        let targets = L.targets
        let count = targets.count
        guard count > 0, !L.validList.isEmpty else { return }
        let maxRadius = max(w, h)
        var localRng = rng

        L.img.withUnsafeBufferPointer { imgBuf in
            L.valid.withUnsafeBufferPointer { validBuf in
                nnf.withUnsafeMutableBufferPointer { nn in
                    dist.withUnsafeMutableBufferPointer { ds in
                        guard let img = imgBuf.baseAddress else { return }

                        // Refresh distances for the current image estimate.
                        for k in 0..<count {
                            let p = Int(targets[k])
                            let q = Int(nn[p])
                            ds[p] = patchDistance(img, w: w, h: h, px: p % w, py: p / w,
                                                  qx: q % w, qy: q / w, cutoff: .infinity)
                        }

                        for it in 0..<iterations {
                            let forward = it % 2 == 0
                            for k in 0..<count {
                                let p = Int(forward ? targets[k] : targets[count - 1 - k])
                                let px = p % w, py = p / w
                                var best = Int(nn[p])
                                var bestD = ds[p]

                                func consider(_ qx: Int, _ qy: Int) {
                                    if qx < r || qy < r || qx >= w - r || qy >= h - r { return }
                                    let q = qy * w + qx
                                    if q == best || !validBuf[q] { return }
                                    let d = patchDistance(img, w: w, h: h, px: px, py: py, qx: qx, qy: qy, cutoff: bestD)
                                    if d < bestD {
                                        bestD = d
                                        best = q
                                    }
                                }

                                // Propagation
                                if forward {
                                    if px > 0 {
                                        let n = Int(nn[p - 1])
                                        if n >= 0 { consider(n % w + 1, n / w) }
                                    }
                                    if py > 0 {
                                        let n = Int(nn[p - w])
                                        if n >= 0 { consider(n % w, n / w + 1) }
                                    }
                                } else {
                                    if px < w - 1 {
                                        let n = Int(nn[p + 1])
                                        if n >= 0 { consider(n % w - 1, n / w) }
                                    }
                                    if py < h - 1 {
                                        let n = Int(nn[p + w])
                                        if n >= 0 { consider(n % w, n / w - 1) }
                                    }
                                }

                                // Random search
                                var radius = maxRadius
                                while radius >= 1 {
                                    let bx = best % w, by = best / w
                                    let qx = (bx + localRng.range(radius)).clamped(r, w - 1 - r)
                                    let qy = (by + localRng.range(radius)).clamped(r, h - 1 - r)
                                    consider(qx, qy)
                                    radius /= 2
                                }

                                nn[p] = Int32(best)
                                ds[p] = bestD
                            }
                        }
                    }
                }
            }
        }
        rng = localRng
    }

    // MARK: - Voting

    static func vote(_ L: Level, nnf: [Int32], dist: [Float]) {
        let w = L.w, h = L.h
        var acc = [Float](repeating: 0, count: w * h * 4)
        var wsum = [Float](repeating: 0, count: w * h)

        var total: Double = 0
        var n = 0
        for t in L.targets {
            let d = dist[Int(t)]
            if d.isFinite { total += Double(d); n += 1 }
        }
        let meanD: Float = n > 0 ? max(Float(total / Double(n)), 1e-6) : 1

        L.img.withUnsafeBufferPointer { imgB in
            L.hole.withUnsafeBufferPointer { hb in
                acc.withUnsafeMutableBufferPointer { ac in
                    wsum.withUnsafeMutableBufferPointer { ws in
                        for t in L.targets {
                            let p = Int(t)
                            let q = Int(nnf[p])
                            if q < 0 { continue }
                            let d = dist[p]
                            let wt: Float = d.isFinite ? max(expf(-d / meanD), 1e-4) : 1
                            let px = p % w, py = p / w, qx = q % w, qy = q / w
                            for dy in -r...r {
                                let yy = py + dy
                                if yy < 0 || yy >= h { continue }
                                for dx in -r...r {
                                    let xx = px + dx
                                    if xx < 0 || xx >= w { continue }
                                    let x = yy * w + xx
                                    if !hb[x] { continue }
                                    let s = ((qy + dy) * w + qx + dx) * 4
                                    let o = x * 4
                                    ac[o] += wt * imgB[s]
                                    ac[o + 1] += wt * imgB[s + 1]
                                    ac[o + 2] += wt * imgB[s + 2]
                                    ac[o + 3] += wt * imgB[s + 3]
                                    ws[x] += wt
                                }
                            }
                        }
                    }
                }
            }
        }

        for i in 0..<(w * h) where L.hole[i] && wsum[i] > 0 {
            let inv = 1 / wsum[i]
            L.img[i * 4] = acc[i * 4] * inv
            L.img[i * 4 + 1] = acc[i * 4 + 1] * inv
            L.img[i * 4 + 2] = acc[i * 4 + 2] * inv
            L.img[i * 4 + 3] = acc[i * 4 + 3] * inv
        }
    }

    // MARK: - Helpers

    static func dilate(_ m: [Bool], w: Int, h: Int, radius: Int) -> [Bool] {
        var tmp = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            let row = y * w
            for x in 0..<w where m[row + x] {
                for xx in max(0, x - radius)...min(w - 1, x + radius) { tmp[row + xx] = true }
            }
        }
        var out = tmp
        for y in 0..<h {
            for x in 0..<w where tmp[y * w + x] {
                for yy in max(0, y - radius)...min(h - 1, y + radius) { out[yy * w + x] = true }
            }
        }
        return out
    }
}

struct XorShift {
    private var s: UInt64

    init(seed: UInt64) { s = seed == 0 ? 0x1234_5678 : seed }

    mutating func next() -> UInt64 {
        s ^= s << 13
        s ^= s >> 7
        s ^= s << 17
        return s
    }

    /// Uniform in 0..<n
    mutating func next(_ n: Int) -> Int { Int(next() % UInt64(max(1, n))) }

    /// Uniform in -radius...radius
    mutating func range(_ radius: Int) -> Int { Int(next() % UInt64(2 * radius + 1)) - radius }
}
