#pragma once

#include "daxa/daxa.inl"

static daxa::f32 PI = 3.14159265359f;
static daxa::u32 ACCUMULATE_ON_FLAG = 1 << 0;

#ifdef __cplusplus
#define VOX_DDA_FUNC void
#define VOX_DDA_MUT_FUNC
#define VOX_DDA_TAN std::tan
#else
#define VOX_DDA_FUNC func
#define VOX_DDA_MUT_FUNC [mutating]
#define VOX_DDA_TAN tan
#endif // __cplusplus

#ifdef __cplusplus
daxa_f32vec2 operator/(daxa_f32vec2 a, daxa_f32vec2 b)
{
    return daxa_f32vec2(a.x / b.x, a.y / b.y);
}
daxa_f32vec2 operator*(daxa_f32vec2 a, daxa_f32 b)
{
    return daxa_f32vec2(a.x * b, a.y * b);
}
daxa_f32vec2 operator-(daxa_f32vec2 a, daxa_f32 b)
{
    return daxa_f32vec2(a.x - b, a.y - b);
}
daxa_f32vec3 operator-(daxa_f32vec3 a, daxa_f32vec3 b)
{
    return daxa_f32vec3(a.x - b.x, a.y - b.y, a.z - b.z);
}
daxa_f32vec3 operator/(daxa_f32vec3 a, daxa_f32 b)
{
    return daxa_f32vec3(a.x / b, a.y / b, a.z / b);
}
daxa_f32vec3 operator*(daxa_f32vec3 a, daxa_f32 b)
{
    return daxa_f32vec3(a.x * b, a.y * b, a.z * b);
}
daxa_f32vec3 operator+(daxa_f32vec3 a, daxa_f32vec3 b)
{
    return daxa_f32vec3(a.x + b.x, a.y + b.y, a.z + b.z);
}

f32 magnitude(daxa_f32vec3 a)
{
    return sqrt(a.x * a.x + a.y * a.y + a.z * a.z);
}
daxa_f32vec3 normalize(daxa_f32vec3 a)
{
    auto mag = magnitude(a);
    if (mag == 0.0f)
    {
        return a;
    }
    return a / mag;
}

#endif // __cplusplus

struct Ray
{
    daxa_f32vec3 origin;
    daxa_f32vec3 direction;
};

struct CameraView
{
    daxa_f32mat4x4 inv_view;
    daxa_f32mat4x4 inv_proj;
};

struct PointLight
{
    daxa_f32vec3 position;
    daxa_f32vec3 emission;
};

struct AreaLight
{
    daxa_f32vec3 position;
    daxa_f32vec3 normal;
    daxa_f32vec3 emission;
    daxa_f32vec2 size;
};

struct Aabb
{
    daxa_f32vec3 min;
    daxa_f32vec3 max;
    daxa_f32vec3 emission;

    daxa_f32vec3 center()
    {
        return (min + max) * 0.5f;
    }
};

struct ComputePush
{
    daxa_BufferPtr(CameraView) cam;
    daxa_u32vec2 res;
    daxa_u64 frame_index;
    daxa_u64 frame_count;
    daxa_u32 flags;
    daxa::RWTexture2DId<daxa_f32vec4> swapchain;
    daxa_BufferPtr(daxa_u32) voxel_buffer;
    daxa::RWTexture2DId<daxa_f32vec4> accumulation_previous_buffer;
    daxa::RWTexture2DId<daxa_f32vec4> accumulation_buffer;
};
