// The shape of a page being turned, as a sheet held at the spine. Paper bends but does not
// stretch, so each row of the sheet is built by walking along it in equal steps, turning a little
// at each step: the outer edge leads the spine, and the bottom corner, where a finger lifts the
// page, leads the top. Units: the page is 1 wide and `aspect` tall, the spine is the line x = 0,
// the reader looks down the z axis at the page lying in z = 0.
import simd

struct PageVertex {
    var position: SIMD3<Float>
    var normal: SIMD3<Float>
    var uv: SIMD2<Float>          // 0...1 across the page, 0...1 up it
}

enum PageGeometry {
    static let columns = 48, rows = 24
    /// How far the bottom of the page runs ahead of the top at mid-turn, in turn progress.
    static let lead: Float = 0.22
    /// How much further the outer edge has turned than the spine at mid-turn, in radians.
    static let curl: Float = 1.1

    /// The progress of one row: the bottom row ahead, the top behind, equal at rest.
    static func rowProgress(_ p: Float, v: Float) -> Float {
        min(max(p + lead * sin(.pi * p) * (0.5 - v), 0), 1)
    }

    /// The angle of the sheet at distance `u` from the spine, for a row at progress `p`.
    static func angle(u: Float, rowProgress p: Float) -> Float {
        min(.pi * p + curl * sin(.pi * p) * pow(u, 1.5), .pi)
    }

    /// Every vertex of the sheet, row by row from the bottom, `columns + 1` to a row.
    static func vertices(progress: Float, aspect: Float) -> [PageVertex] {
        var out: [PageVertex] = []
        out.reserveCapacity((columns + 1) * (rows + 1))
        let step = 1 / Float(columns)
        for r in 0...rows {
            let v = Float(r) / Float(rows)
            let p = rowProgress(progress, v: v)
            var x: Float = 0, z: Float = 0
            for c in 0...columns {
                let u = Float(c) / Float(columns)
                if c > 0 {
                    // Walk one step along the paper in the direction of the middle of the step.
                    let a = angle(u: u - step / 2, rowProgress: p)
                    x += cos(a) * step
                    z += sin(a) * step
                }
                out.append(PageVertex(position: [x, v * aspect, z], normal: [0, 0, 1], uv: [u, v]))
            }
        }
        computeNormals(&out)
        return out
    }

    /// Two triangles per cell, wound counter-clockwise when the page faces the reader.
    static func indices() -> [UInt32] {
        var out: [UInt32] = []
        let stride = UInt32(columns + 1)
        for r in 0..<UInt32(rows) {
            for c in 0..<UInt32(columns) {
                let a = r * stride + c, b = a + 1, d = a + stride, e = d + 1
                out += [a, b, e, a, e, d]
            }
        }
        return out
    }

    /// Where the outer edge of each row is, as (x, height above the next page), for its shadow.
    static func edge(progress: Float, aspect: Float) -> [SIMD2<Float>] {
        let verts = vertices(progress: progress, aspect: aspect)
        return (0...rows).map { r in
            let p = verts[r * (columns + 1) + columns].position
            return [p.x, p.z]
        }
    }

    private static func computeNormals(_ verts: inout [PageVertex]) {
        let w = columns + 1
        for r in 0...rows {
            for c in 0...columns {
                let i = r * w + c
                let left = verts[r * w + max(c - 1, 0)].position, right = verts[r * w + min(c + 1, columns)].position
                let down = verts[max(r - 1, 0) * w + c].position, up = verts[min(r + 1, rows) * w + c].position
                let n = simd_cross(right - left, up - down)
                verts[i].normal = simd_length(n) > 0 ? simd_normalize(n) : [0, 0, 1]
            }
        }
    }
}
