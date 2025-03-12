#include "daxa/daxa.inl"
#include "shared.inl"

// Push constant struct
[[vk::push_constant]] ComputePush p;

struct RayDesc {
    daxa_f32vec3 origin;
    daxa_f32vec3 direction;
    daxa_f32 t_min;
    daxa_f32 t_max;
};

// FIXME: pass this as a push constant or buffer
static Aabb box = Aabb(float3(-3.0, -3.0, -3.0), float3(3.0, 3.0, 3.0));
static PointLight light = PointLight(float3(0, 5, 4), float3(1, 1, 1));

func RayAabbIntersection(Ray ray, Aabb box) -> float{
    float3 inv_dir = 1.0f / ray.direction;
    float3 t0 = (box.min - ray.origin) * inv_dir;
    float3 t1 = (box.max - ray.origin) * inv_dir;
    float3 tmin = min(t0, t1);
    float3 tmax = max(t0, t1);
    float tmin_max = max(tmin.x, max(tmin.y, tmin.z));
    float tmax_min = min(tmax.x, min(tmax.y, tmax.z));
    return tmax_min > max(tmin_max, 0.0f) ? tmin_max : -1.0f;
}

func ComputeAabbNormal(float3 normal) -> float3 {
            // Cube normal calculation
    float3 abs_normal = abs(normal);
    float max_component = max(max(abs_normal.x, abs_normal.y), abs_normal.z);
    return (max_component == abs_normal.x) ? float3(sign(normal.x), 0, 0) : (max_component == abs_normal.y) ? float3(0, sign(normal.y), 0)
                                                                                                            : float3(0, 0, sign(normal.z));
}

RayDesc CreateRay(daxa_f32mat4x4 inv_view, daxa_f32mat4x4 inv_proj, daxa_u32vec2 thread_idx, daxa_u32vec2 rt_size, daxa_f32 tmin, daxa_f32 tmax)
{
  const daxa_f32vec2 pixel_center = daxa_f32vec2(thread_idx) + daxa_f32vec2(0.5);
  const daxa_f32vec2 inv_UV = pixel_center / daxa_f32vec2(rt_size);
  daxa_f32vec2 d = inv_UV * 2.0 - 1.0;

  daxa_f32vec4 origin = mul(inv_view, daxa_f32vec4(0, 0, 0, 1));
  daxa_f32vec4 target = mul(inv_proj, daxa_f32vec4(d.x, d.y, 1, 1));
  daxa_f32vec4 direction = mul(inv_view, daxa_f32vec4(normalize(target.xyz), 0));

  RayDesc ray;
  ray.origin = origin.xyz;
  ray.direction = direction.xyz;
  ray.t_min = tmin;
  ray.t_max = tmax;
  return ray;
}

func CalculateLighting(float3 hit_point, float3 normal, PointLight light) -> float4 {
    // Add some offset to avoid self-shadowing
    hit_point += normal * 0.1f; 
    Ray shadow_ray = Ray(hit_point, light.position - hit_point);
    float t = RayAabbIntersection(shadow_ray, box);
    if (t > 0.0f)
        return float4(0, 0, 0, 1);

    let color = light.emission * float3(1, 0, 0);
    return float4(color, 1);
}

// Entry point with HLSL semantics
[numthreads(8, 4, 1)] void entry_compute_shader(uint2 pixel_i : SV_DispatchThreadID) {
    // global histogram buffer
    uint2 res = p.res;
    if (pixel_i.x >= res.x || pixel_i.y >= res.y)
        return;

    let cam = (CameraView*)(p.cam);
    let t_min = 0.0001f;
    let t_max = 10000.0f;

    if(pixel_i.x == 0 && pixel_i.y == 0) {
        printf("cam.inv_view[0]: %f %f %f %f\n", cam.inv_view[0][0], cam.inv_view[0][1], cam.inv_view[0][2], cam.inv_view[0][3]);
        printf("cam.inv_view[1]: %f %f %f %f\n", cam.inv_view[1][0], cam.inv_view[1][1], cam.inv_view[1][2], cam.inv_view[1][3]);
        printf("cam.inv_view[2]: %f %f %f %f\n", cam.inv_view[2][0], cam.inv_view[2][1], cam.inv_view[2][2], cam.inv_view[2][3]);
        printf("cam.inv_view[3]: %f %f %f %f\n", cam.inv_view[3][0], cam.inv_view[3][1], cam.inv_view[3][2], cam.inv_view[3][3]);
        printf("cam.inv_proj[0]: %f %f %f %f\n", cam.inv_proj[0][0], cam.inv_proj[0][1], cam.inv_proj[0][2], cam.inv_proj[0][3]);
        printf("cam.inv_proj[1]: %f %f %f %f\n", cam.inv_proj[1][0], cam.inv_proj[1][1], cam.inv_proj[1][2], cam.inv_proj[1][3]);
        printf("cam.inv_proj[2]: %f %f %f %f\n", cam.inv_proj[2][0], cam.inv_proj[2][1], cam.inv_proj[2][2], cam.inv_proj[2][3]);
        printf("cam.inv_proj[3]: %f %f %f %f\n", cam.inv_proj[3][0], cam.inv_proj[3][1], cam.inv_proj[3][2], cam.inv_proj[3][3]);
    }

    let ray = CreateRay(cam.inv_view, cam.inv_proj, pixel_i, res, t_min, t_max);

    var color = float4(0.1, 0.1, 0.1, 1);
    float t = RayAabbIntersection(Ray(ray.origin, ray.direction), box);
    if (t > 0.0f) {
        // float3 hit_point = ray.origin + ray.direction * t;
        // float3 normal = ComputeAabbNormal(hit_point - box.center());
        // color = CalculateLighting(hit_point, normal, light);
        color = float4(1, 0, 0, 1);
    }

    // draw pixel
    p.swapchain.get()[pixel_i.xy] = color;
}