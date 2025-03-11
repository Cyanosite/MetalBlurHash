//
//  Shaders.metal
//  MetalBlurHash
//
//  Created by Zsombor Szenyán on 2025. 03. 08..
//

#include <metal_stdlib>
using namespace metal;

struct EncodeParams {
    uint width;
    uint height;
    uint bytesPerRow;
    uint cx;
    uint cy;
};

static inline float srgbChannelToLinear(uchar c) {
    float s = float(c) / 255.0;
    if (s <= 0.04045) {
        return s / 12.92;
    } else {
        return pow((s + 0.055)/1.055, 2.4);
    }
}

// MARK: - ENCODE

kernel void encodeBlurHash(
    constant uchar4*         image,
    device   float4*         result,
    constant EncodeParams&   params,
    uint2                    tid        [[ thread_position_in_threadgroup ]],
    uint2                    gid        [[ thread_position_in_grid ]],
    uint2                    groupSize  [[ threads_per_threadgroup ]],
    uint2                    gridSize   [[ threads_per_grid ]],
    uint2                    tg_id      [[ threadgroup_position_in_grid ]]
) {
    float4 localSum = float4(0.0);

    for (uint y = gid.y; y < params.height; y += gridSize.y) {
        for (uint x = gid.x; x < params.width; x += gridSize.x) {
            uint index = y * (params.bytesPerRow / 4) + x;
            uchar4 px = image[index];

            float r = srgbChannelToLinear(px.r);
            float g = srgbChannelToLinear(px.g);
            float b = srgbChannelToLinear(px.b);

            float basisX = cos(M_PI_F * float(params.cx) * float(x) / float(params.width));
            float basisY = cos(M_PI_F * float(params.cy) * float(y) / float(params.height));
            float basis = basisX * basisY;

            localSum.x += r * basis;
            localSum.y += g * basis;
            localSum.z += b * basis;
        }
    }

    threadgroup float4 sharedData[256];
    uint linearID = tid.y * groupSize.x + tid.x;
    sharedData[linearID] = localSum;
    threadgroup_barrier(mem_flags::mem_threadgroup);

    // Binary reduction within the threadgroup
    uint halfCount = (groupSize.x * groupSize.y) / 2;
    while (halfCount > 0) {
        if (linearID < halfCount) {
            sharedData[linearID] += sharedData[linearID + halfCount];
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
        halfCount /= 2;
    }

    if (linearID == 0) {
        uint numThreadgroupsX = gridSize.x / groupSize.x;
        uint threadgroupIndex = tg_id.y * numThreadgroupsX + tg_id.x;
        result[threadgroupIndex] = sharedData[0];
    }
}

struct DecodeParams {
    uint width;
    uint height;
    uint componentsY;
    uint componentsX;
    uint bytesPerRow;
};

static inline uint3 linearTosRGB(float3 color) {
    float3 v = clamp(color, float3(0.0), float3(1.0));
    float3 lower = v * 12.92 * 255.0 + 0.5;
    constexpr float RECIPROCAL = 1/2.4; // 1/2.4
    float3 upper = (1.055 * pow(v, RECIPROCAL) - 0.055) * 255.0 + 0.5;
    float3 mask = step(0.0031308, v);
    float3 result = mix(lower, upper, mask);
    return uint3(result);
}

// MARK: - DECODE
kernel void decodeBlurHash (
    constant float3* colors,
    device uchar4* pixels,
    constant DecodeParams& params,
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.width || gid.y >= params.height) {
        return;
    }
    
    float3 color = float3(0);
    float fX = M_PI_F * float(gid.x) / float(params.width);
    float fY = M_PI_F * float(gid.y) / float(params.height);
    for(uint j = 0; j < params.componentsY; ++j) {
        float cosY = cos(fY * float(j));
        for(uint i = 0; i < params.componentsX; ++i) {
            float basis = cos(fX * float(i)) * cosY;
            color += colors[i + j * params.componentsX] * basis;
        }
    }
    uint4 sRGBcolor = uint4(linearTosRGB(color), 255);
    uint index = gid.x + gid.y * (params.bytesPerRow / 4);
    pixels[index] = uchar4(sRGBcolor);
}
