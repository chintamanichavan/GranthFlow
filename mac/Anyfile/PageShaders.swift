// The page-turn shaders, as Metal source compiled when the app first turns a page. They live in
// Swift rather than a .metal file because Xcode 27 builds .metal files only with a separately
// downloaded Metal Toolchain; compiling at run time needs nothing beyond macOS.
enum PageShaders {
    static let source = """
// Drawing a page turn: the next page lies flat with the turning page's shadow on it, and the
// turning page is lit as it bends. The lighting is set so a page lying flat comes out exactly as
// printed, so the first and last frames match the real text underneath.
#include <metal_stdlib>
using namespace metal;

// Laid out as Swift lays out PageVertex: float3 takes 16 bytes, so a vertex is 48.
struct PageVertex {
    float3 position;
    float3 normal;
    float2 uv;
};

struct Uniforms {
    float4x4 viewProjection;
    float4 paper;          // the paper colour, for the back of the page
    float3 light;          // direction toward the light, normalised
    float aspect;          // page height / width
    float shadow;          // 0 at rest, up to 1 mid-turn
    int rows;              // entries in the edge buffer, minus one
};

struct Out {
    float4 position [[position]];
    float3 world;
    float3 normal;
    float2 uv;
};

vertex Out pageVertex(const device PageVertex *verts [[buffer(0)]], constant Uniforms &u [[buffer(1)]], uint id [[vertex_id]]) {
    PageVertex v = verts[id];
    Out o;
    // Lifted a hair above the next page, so the two never fight for the same pixel at rest.
    float3 p = v.position + float3(0, 0, 0.0005);
    o.position = u.viewProjection * float4(p, 1);
    o.world = p;
    o.normal = v.normal;
    o.uv = v.uv;
    return o;
}

fragment float4 pageFragment(Out in [[stage_in]], bool front [[front_facing]], constant Uniforms &u [[buffer(1)]],
                             texture2d<float> printed [[texture(0)]], sampler s [[sampler(0)]]) {
    float2 uv = float2(in.uv.x, 1 - in.uv.y);                 // images are stored top row first
    float4 ink = printed.sample(s, uv);
    float3 n = normalize(front ? in.normal : -in.normal);
    // 1 for a page lying flat, darker as it turns away from the light, a little brighter toward it.
    // Paper scatters light, so even a page edge-on to the light is not darker than about 0.7.
    float lit = dot(n, u.light) - u.light.z;
    float shade = front ? clamp(1 + 0.55 * lit, 0.7, 1.05) : clamp(0.97 + 0.35 * lit, 0.8, 1.02);
    // The back of the page is paper with the print showing faintly through.
    float3 colour = front ? ink.rgb : mix(ink.rgb, u.paper.rgb, 0.88);
    return float4(colour * shade, 1);
}

vertex Out flatVertex(uint id [[vertex_id]], constant Uniforms &u [[buffer(1)]]) {
    float2 corners[4] = { float2(0, 0), float2(1, 0), float2(0, 1), float2(1, 1) };
    float2 c = corners[id];
    Out o;
    float3 p = float3(c.x, c.y * u.aspect, 0);
    o.position = u.viewProjection * float4(p, 1);
    o.world = p;
    o.normal = float3(0, 0, 1);
    o.uv = c;
    return o;
}

fragment float4 flatFragment(Out in [[stage_in]], constant Uniforms &u [[buffer(1)]], const device float2 *edge [[buffer(2)]],
                             texture2d<float> printed [[texture(0)]], sampler s [[sampler(0)]]) {
    float4 ink = printed.sample(s, float2(in.uv.x, 1 - in.uv.y));
    // Where the turning page's outer edge is on this row, and how high it stands.
    float row = clamp(in.uv.y, 0.0, 1.0) * u.rows;
    int r0 = int(floor(row)), r1 = min(r0 + 1, u.rows);
    float2 e = mix(edge[r0], edge[r1], fract(row));
    // The shadow falls just beyond the edge, softer and wider the higher the page is lifted.
    float beyond = in.world.x - e.x;
    float softness = 0.01 + 0.12 * max(e.y, 0.0);
    float dark = beyond > 0 ? exp(-beyond / softness) : 1;
    dark *= u.shadow * clamp(e.y * 4, 0.0, 1.0) * 0.28;
    return float4(ink.rgb * (1 - dark), 1);
}
"""
}
