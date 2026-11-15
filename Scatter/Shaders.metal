#include <metal_stdlib>
using namespace metal;

// Swift의 Uniforms와 레이아웃이 같아야 한다 (24바이트).
struct Uniforms {
    float2 viewMin;   // 화면 왼쪽 아래의 데이터 좌표 (열 최소값 기준 상대값)
    float2 scale;     // 데이터 단위 → NDC 배율 (2 / 보이는 범위)
    float  pointSize;
    float  pad;
};

// 점 하나당 해당 픽셀 카운터에 1을 더한다 (래스터 파이프라인·타일 분류를 거치지 않음).
kernel void splat(const device float2 *points [[buffer(0)]],
                  constant Uniforms &u [[buffer(1)]],
                  device atomic_uint *counts [[buffer(2)]],
                  constant uint2 &size [[buffer(3)]],
                  constant uint &count [[buffer(4)]],
                  uint id [[thread_position_in_grid]]) {
    if (id >= count) return;
    float2 ndc = (points[id] - u.viewMin) * u.scale - 1.0;
    float2 f = (ndc * 0.5 + 0.5) * float2(size);
    if (f.x < 0.0 || f.y < 0.0 || f.x >= float(size.x) || f.y >= float(size.y)) return;
    uint x = uint(f.x);
    uint y = size.y - 1 - uint(f.y);   // 화면 픽셀은 위에서 아래로
    atomic_fetch_add_explicit(&counts[y * size.x + x], 1u, memory_order_relaxed);
}

// 카운터 최대값.
kernel void maxReduce(const device uint *counts [[buffer(0)]],
                      device atomic_uint *outMax [[buffer(1)]],
                      constant uint &total [[buffer(2)]],
                      uint id [[thread_position_in_grid]],
                      uint lane [[thread_index_in_simdgroup]]) {
    uint v = id < total ? counts[id] : 0u;
    uint m = simd_max(v);
    if (lane == 0 && m > 0) {
        atomic_fetch_max_explicit(outMax, m, memory_order_relaxed);
    }
}

struct FSOut {
    float4 position [[position]];
};

vertex FSOut fullscreenVertex(uint vid [[vertex_id]]) {
    float2 p = float2((vid << 1) & 2, vid & 2);
    FSOut o;
    o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    return o;
}

// inferno 컬러맵 다항식 근사
static float3 inferno(float t) {
    const float3 c0 = float3(0.0002189403691192265, 0.001651004631001012, -0.01948089843709184);
    const float3 c1 = float3(0.1065134194856116, 0.5639564367884091, 3.932712388889277);
    const float3 c2 = float3(11.60249308247187, -3.972853965665698, -15.9423941062914);
    const float3 c3 = float3(-41.70399613139459, 17.43639888205313, 44.35414519872813);
    const float3 c4 = float3(77.162935699427, -33.40235894210092, -81.80730925738993);
    const float3 c5 = float3(-71.31942824499214, 32.62606426397723, 73.20951985803202);
    const float3 c6 = float3(25.13112622477341, -12.24266895238567, -23.07032500287172);
    return c0 + t * (c1 + t * (c2 + t * (c3 + t * (c4 + t * (c5 + t * c6)))));
}

fragment float4 colormapFragment(FSOut in [[stage_in]],
                                 const device uint *counts [[buffer(0)]],
                                 const device uint *maxCount [[buffer(1)]],
                                 constant uint2 &size [[buffer(2)]]) {
    uint2 px = min(uint2(in.position.xy), size - 1);
    float c = float(counts[px.y * size.x + px.x]);
    float3 bg = float3(0.055, 0.06, 0.075);
    if (c <= 0.0) {
        return float4(bg, 1.0);
    }
    float m = max(float(maxCount[0]), 1.0);
    float t = log(1.0 + c) / log(1.0 + m);
    t = 0.28 + 0.72 * saturate(t);
    return float4(saturate(inferno(t)), 1.0);
}
