#include "daxa/daxa.inl"
#include "shared.inl"

// Push constant struct
[[vk::push_constant]] ComputePush p;

// FIXME: pass this as a push constant or buffer
static Aabb box = Aabb(float3(-0.1f, -0.1f, -0.1f), float3(0.1f, 0.1f, 0.1f));
static PointLight light = PointLight(float3(5, 2, -3), float3(1, 1, 1));

func RayAabbIntersection(Ray ray, Aabb box, out float distance) -> bool{
    float3 inv_dir = 1.0f / ray.direction;
    float3 t0 = (box.min - ray.origin) * inv_dir;
    float3 t1 = (box.max - ray.origin) * inv_dir;
    float3 tmin = min(t0, t1);
    float3 tmax = max(t0, t1);
    distance = max(tmin.x, max(tmin.y, tmin.z));
    float tmax_min = min(tmax.x, min(tmax.y, tmax.z));
    return distance <= tmax_min;
}

func ComputeAabbNormal(float3 normal) -> float3 {
            // Cube normal calculation
    float3 abs_normal = abs(normal);
    float max_component = max(max(abs_normal.x, abs_normal.y), abs_normal.z);
    return (max_component == abs_normal.x) ? float3(sign(normal.x), 0, 0) : (max_component == abs_normal.y) ? float3(0, sign(normal.y), 0)
                                                                                                            : float3(0, 0, sign(normal.z));
}

func CalculateLighting(float3 hit_point, float3 normal, PointLight light) -> float4 {
    // Add some offset to avoid self-shadowing
    hit_point += normal * 0.15f; 
    Ray shadow_ray = Ray(hit_point, light.position - hit_point);
    float distance;
    if (RayAabbIntersection(shadow_ray, box, distance))
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

    Camera cam = p.cam;

    let ray = cam.get_ray(pixel_i, float2(res));

    var color = float4(0.1, 0.1, 0.1, 1);
    float distance;
    if (RayAabbIntersection(ray, box, distance))
    {
        float3 hit_point = ray.origin + ray.direction * distance;
        float3 normal = ComputeAabbNormal(hit_point - box.center());
        color = CalculateLighting(hit_point, normal, light);
    }

    // draw pixel
    p.image_id.get()[pixel_i.xy] = color;
}