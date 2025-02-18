#pragma once

#include "daxa/daxa.inl"

static daxa::f32 PI = 3.14159265359f;

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
f32 magnitude(daxa_f32vec3 a)
{
    return sqrt(a.x * a.x + a.y * a.y + a.z * a.z);
}
daxa_f32vec3 normalize(daxa_f32vec3 a)
{
  auto mag = magnitude(a);
  if(mag == 0.0f)
  {
    return a;
  }
  return a / mag;
}

#endif // __cplusplus

struct Ray {
    daxa_f32vec3 origin;
    daxa_f32vec3 direction;
};

struct Camera
{
    daxa_f32vec3 position;
    daxa_f32 distance;
    VOX_DDA_MUT_FUNC void calculate_camera_distance(daxa_f32 fov)
    {   
        distance = 1.0f / VOX_DDA_TAN(fov * 0.5f * PI / 180.0f);
    };
    
    Ray get_ray(daxa_f32vec2 uv, daxa_f32vec2 res) 
    {
        daxa_f32vec2 uv_res = uv / res * 2.0f - 1.0f;
        daxa_f32vec3 ray_target = daxa_f32vec3(uv_res.x, uv_res.y, distance);
        daxa_f32 aspect_ratio = res.x / res.y;
        ray_target.y /= aspect_ratio;
        return Ray(position, normalize(ray_target - position));
    };
};

struct PointLight
{
    daxa_f32vec3 position;
    daxa_f32vec3 emission;
};

struct Aabb
{
    daxa_f32vec3 min;
    daxa_f32vec3 max;

    daxa_f32vec3 center()
    {
        return (min + max) * 0.5f;
    }
};

struct ComputePush
{
  daxa_u32vec2 res;
  Camera cam;
  daxa::RWTexture2DId<daxa_f32vec4> image_id;
  daxa::BufferId voxel_buffer;
};
