import Foundation

struct Table {
    var name: String
    var fileBytes: Int
    var columnNames: [String]
    var columns: [[Double]]
    var numericColumns: [Int]
    var rowCount: Int
    var loadSeconds: Double
}

enum LoadError: LocalizedError {
    case empty, noNumeric
    var errorDescription: String? {
        switch self {
        case .empty: return "파일이 비어 있어요."
        case .noNumeric: return "숫자로 된 열을 찾지 못했어요."
        }
    }
}

enum CSVLoader {
    /// 메모리 매핑 + 줄 경계로 청크를 나눠 병렬 파싱. 숫자가 아닌 칸은 NaN.
    /// MVP 한계: 따옴표 안의 구분자는 처리하지 않는다.
    static func load(url: URL) throws -> Table {
        let start = CFAbsoluteTimeGetCurrent()
        let data = try Data(contentsOf: url, options: .alwaysMapped)
        let n = data.count
        guard n > 0 else { throw LoadError.empty }

        var table: Table = try data.withUnsafeBytes { raw -> Table in
            let p = raw.bindMemory(to: UInt8.self).baseAddress!

            var lineStart = 0
            if n >= 3 && p[0] == 0xEF && p[1] == 0xBB && p[2] == 0xBF { lineStart = 3 }
            var firstEnd = lineStart
            while firstEnd < n && p[firstEnd] != 10 { firstEnd += 1 }
            var lineEnd = firstEnd
            if lineEnd > lineStart && p[lineEnd - 1] == 13 { lineEnd -= 1 }

            let delim = detectDelimiter(p, lineStart, lineEnd)
            let fields = splitFields(p, lineStart, lineEnd, delim)
            let k = max(fields.count, 1)
            let isHeader = fields.contains { $0.1 > $0.0 && parseDouble(p, $0.0, $0.1).isNaN }
            let names: [String] = isHeader
                ? fields.map { f in
                    String(decoding: UnsafeBufferPointer(start: p + f.0, count: f.1 - f.0), as: UTF8.self)
                        .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\"")))
                }
                : (1...k).map { "열 \($0)" }
            let bodyStart = isHeader ? min(firstEnd + 1, n) : lineStart
            let bodyLen = n - bodyStart

            let chunkCount = max(1, min(ProcessInfo.processInfo.activeProcessorCount * 4, bodyLen / (1 << 20) + 1))
            var bounds = [bodyStart]
            for c in 1..<max(chunkCount, 1) where chunkCount > 1 {
                var b = bodyStart + bodyLen * c / chunkCount
                while b < n && p[b - 1] != 10 { b += 1 }
                bounds.append(max(b, bounds.last!))
            }
            bounds.append(n)

            final class Box { var cols: [[Double]] = [] }
            let results = (0..<chunkCount).map { _ in Box() }
            let avgLine = max(4, firstEnd - lineStart + 1)

            DispatchQueue.concurrentPerform(iterations: chunkCount) { ci in
                let s = bounds[ci], e = bounds[ci + 1]
                var cols = [[Double]](repeating: [], count: k)
                for j in 0..<k { cols[j].reserveCapacity((e - s) / avgLine + 16) }
                var i = s
                while i < e {
                    var le = i
                    while le < e && p[le] != 10 { le += 1 }
                    var end = le
                    if end > i && p[end - 1] == 13 { end -= 1 }
                    if end > i {
                        var col = 0, fs = i, q = i
                        while q <= end {
                            if q == end || p[q] == delim {
                                if col < k { cols[col].append(parseDouble(p, fs, q)) }
                                col += 1
                                fs = q + 1
                            }
                            q += 1
                        }
                        while col < k { cols[col].append(.nan); col += 1 }
                    }
                    i = le + 1
                }
                results[ci].cols = cols
            }

            var columns = [[Double]](repeating: [], count: k)
            for j in 0..<k {
                columns[j].reserveCapacity(results.reduce(0) { $0 + $1.cols[j].count })
                for r in results { columns[j].append(contentsOf: r.cols[j]) }
            }
            let rows = columns.first?.count ?? 0
            let numeric = (0..<k).filter { j in
                var valid = 0
                for v in columns[j] where !v.isNaN { valid += 1 }
                return valid > 0 && valid * 2 >= rows
            }
            guard !numeric.isEmpty else { throw LoadError.noNumeric }

            var padded = names
            while padded.count < k { padded.append("열 \(padded.count + 1)") }
            return Table(name: url.lastPathComponent, fileBytes: n, columnNames: padded, columns: columns,
                         numericColumns: numeric, rowCount: rows, loadSeconds: 0)
        }
        table.loadSeconds = CFAbsoluteTimeGetCurrent() - start
        return table
    }

    private static func detectDelimiter(_ p: UnsafePointer<UInt8>, _ s: Int, _ e: Int) -> UInt8 {
        var counts: [UInt8: Int] = [44: 0, 9: 0, 59: 0, 124: 0]
        for i in s..<max(s, e) where counts[p[i]] != nil { counts[p[i]]! += 1 }
        let best = counts.max { $0.value < $1.value }!
        return best.value > 0 ? best.key : 44
    }

    private static func splitFields(_ p: UnsafePointer<UInt8>, _ s: Int, _ e: Int, _ d: UInt8) -> [(Int, Int)] {
        var out: [(Int, Int)] = []
        var fs = s
        for q in s...e where q == e || p[q] == d {
            out.append((fs, q))
            fs = q + 1
        }
        return out
    }

    private static let pow10Table: [Double] = (0...22).map { pow(10, Double($0)) }

    /// 빠른 숫자 파서. 실패하면 NaN.
    @inline(__always)
    static func parseDouble(_ p: UnsafePointer<UInt8>, _ s: Int, _ e: Int) -> Double {
        var i = s, end = e
        while i < end && (p[i] == 32 || p[i] == 34) { i += 1 }
        while end > i && (p[end - 1] == 32 || p[end - 1] == 34 || p[end - 1] == 13) { end -= 1 }
        if i >= end { return .nan }
        var neg = false
        if p[i] == 45 { neg = true; i += 1 } else if p[i] == 43 { i += 1 }
        var mant: UInt64 = 0
        var exp10 = 0
        var any = false
        while i < end {
            let d = p[i] &- 48
            if d >= 10 { break }
            any = true
            if mant < 100_000_000_000_000_000 { mant = mant &* 10 &+ UInt64(d) } else { exp10 += 1 }
            i += 1
        }
        if i < end && p[i] == 46 {
            i += 1
            while i < end {
                let d = p[i] &- 48
                if d >= 10 { break }
                any = true
                if mant < 100_000_000_000_000_000 { mant = mant &* 10 &+ UInt64(d); exp10 -= 1 }
                i += 1
            }
        }
        if !any { return .nan }
        if i < end && (p[i] == 101 || p[i] == 69) {
            i += 1
            var eneg = false
            if i < end && (p[i] == 45 || p[i] == 43) { eneg = p[i] == 45; i += 1 }
            var ev = 0
            var anyE = false
            while i < end {
                let d = p[i] &- 48
                if d >= 10 { break }
                anyE = true
                if ev < 10000 { ev = ev * 10 + Int(d) }
                i += 1
            }
            if !anyE { return .nan }
            exp10 += eneg ? -ev : ev
        }
        if i != end { return .nan }
        var v = Double(mant)
        if exp10 > 0 {
            v *= exp10 <= 22 ? pow10Table[exp10] : pow(10, Double(exp10))
        } else if exp10 < 0 {
            v /= -exp10 <= 22 ? pow10Table[-exp10] : pow(10, Double(-exp10))
        }
        return neg ? -v : v
    }

    // MARK: 예제 데이터

    static func synthetic(count: Int = 10_000_000) -> Table {
        let start = CFAbsoluteTimeGetCurrent()
        var xs = [Double](repeating: 0, count: count)
        var ys = [Double](repeating: 0, count: count)
        let cx: [Double] = [-6, -2, 3, 7, 1], cy: [Double] = [4, -3, 5, -1, 0]
        let sx: [Double] = [0.8, 0.4, 1.2, 0.3, 2.5], sy: [Double] = [0.5, 1.1, 0.4, 0.9, 2.5]
        let chunks = 64
        xs.withUnsafeMutableBufferPointer { xb in
            ys.withUnsafeMutableBufferPointer { yb in
                let xp = xb.baseAddress!, yp = yb.baseAddress!
                DispatchQueue.concurrentPerform(iterations: chunks) { c in
                    var rng = SplitMix(state: UInt64(c + 1) &* 0x9E37_79B9_7F4A_7C15)
                    for i in (count * c / chunks)..<(count * (c + 1) / chunks) {
                        let r = rng.unit()
                        let (g1, g2) = rng.gaussianPair()
                        if r < 0.5 {
                            let k = Int(rng.next() % 5)
                            xp[i] = cx[k] + g1 * sx[k]
                            yp[i] = cy[k] + g2 * sy[k]
                        } else if r < 0.85 {
                            let t = rng.unit() * 6 * .pi
                            let rad = 0.5 + t * 0.55
                            xp[i] = cos(t) * rad + g1 * 0.1
                            yp[i] = sin(t) * rad + g2 * 0.1
                        } else if r < 0.98 {
                            let x = rng.unit() * 24 - 12
                            xp[i] = x
                            yp[i] = sin(x * 1.3) * 2 - 10 + g1 * 0.12
                        } else {
                            xp[i] = rng.unit() * 28 - 14
                            yp[i] = rng.unit() * 28 - 14
                        }
                    }
                }
            }
        }
        return Table(name: "예제 데이터", fileBytes: count * 16, columnNames: ["x", "y"], columns: [xs, ys],
                     numericColumns: [0, 1], rowCount: count, loadSeconds: CFAbsoluteTimeGetCurrent() - start)
    }
}

struct SplitMix {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0) }
    mutating func gaussianPair() -> (Double, Double) {
        let u1 = max(unit(), 1e-300), u2 = unit()
        let r = (-2 * log(u1)).squareRoot()
        return (r * cos(2 * .pi * u2), r * sin(2 * .pi * u2))
    }
}
