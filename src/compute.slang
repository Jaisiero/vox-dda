#include "daxa/daxa.inl"
#include "shared.inl"

// Push constant struct
[[vk::push_constant]] ComputePush p;

struct RayDesc
{
    daxa_f32vec3 origin;
    daxa_f32vec3 direction;
    daxa_f32 t_min;
    daxa_f32 t_max;
};

// FIXME: pass this as a push constant or buffer
static Aabb box = Aabb(float3(-3.0, -3.0, -3.0), float3(3.0, 3.0, 3.0));
static PointLight light = PointLight(float3(5, 5, -5), float3(20, 20, 20));

func BoxCenter(Aabb box) -> float3
{
    return (box.min + box.max) * 0.5f;
}

func RayAabbIntersection(Ray ray, Aabb box) -> float
{
    float3 inv_dir = 1.0f / ray.direction;
    float3 t0 = (box.min - ray.origin) * inv_dir;
    float3 t1 = (box.max - ray.origin) * inv_dir;
    float3 tmin = min(t0, t1);
    float3 tmax = max(t0, t1);
    float tmin_max = max(tmin.x, max(tmin.y, tmin.z));
    float tmax_min = min(tmax.x, min(tmax.y, tmax.z));
    return tmax_min > max(tmin_max, 0.0f) ? tmin_max : -1.0f;
}

func ComputeAabbNormal(float3 hit_point, Aabb box) -> float3
{
    float3 d = hit_point - BoxCenter(box);
    float3 abs_d = abs(d);
    if (abs_d.x >= abs_d.y && abs_d.x >= abs_d.z)
        return float3(sign(d.x), 0, 0);
    else if (abs_d.y >= abs_d.z)
        return float3(0, sign(d.y), 0);
    else
        return float3(0, 0, sign(d.z));
}

func CreateRay(daxa_f32mat4x4 inv_view, daxa_f32mat4x4 inv_proj, daxa_u32vec2 thread_idx, daxa_u32vec2 rt_size, daxa_f32 tmin, daxa_f32 tmax, inout uint seed) -> RayDesc
{
    // Compute a jitter offset in the range [-0.5, 0.5] in pixel space.
    daxa_f32vec2 jitter = daxa_f32vec2(rand(seed) - 0.5, rand(seed) - 0.5);
    // Add jitter to the pixel center.
    daxa_f32vec2 pixel_center = daxa_f32vec2(thread_idx) + daxa_f32vec2(0.5) + jitter;
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

func CalculateLighting(float3 hit_point, float3 normal, PointLight light) -> float3
{
    // --- Direct Lighting (Optional) ---
    // Here we compute a direct lighting contribution from the point light.
    float3 light_dir = normalize(light.position - hit_point);
    float diff = max(dot(normal, light_dir), 0.0f);
    float distance = length(light.position - hit_point);
    float attenuation = 1.0f / (distance * distance);
    // Cast a shadow ray to check if the light is visible.
    Ray shadow_ray = Ray(hit_point + normal * 0.001f, light_dir);
    float shadow_t = RayAabbIntersection(shadow_ray, box);
    float direct = (shadow_t < 0.0f) ? 1.0f : 0.0f;
    return light.emission * diff * attenuation * direct;
}

// A simple pseudo-random generator based on a hash.
func rand(inout uint seed) -> float
{
    seed = seed * 1664525u + 1013904223u;
    return (seed & 0x00FFFFFFu) / float(0x01000000u);
}

// Sample a cosine-weighted direction in the hemisphere about the normal.
func random_hemisphere(float3 normal, inout uint seed) -> float3
{
    float u1 = rand(seed);
    float u2 = rand(seed);
    float r = sqrt(1.0 - u1 * u1);
    float phi = 2.0 * PI * u2;
    float3 tangent;
    if (abs(normal.x) > 0.1)
        tangent = normalize(cross(normal, float3(0, 1, 0)));
    else
        tangent = normalize(cross(normal, float3(1, 0, 0)));
    float3 bitangent = cross(normal, tangent);
    return normalize(u1 * normal + r * cos(phi) * tangent + r * sin(phi) * bitangent);
}

[numthreads(8, 4, 1)] void entry_compute_shader(uint2 pixel_i : SV_DispatchThreadID)
{
    uint2 res = p.res;
    if (pixel_i.x >= res.x || pixel_i.y >= res.y)
        return;

    let cam = (CameraView *)(p.cam);
    let t_min = 0.0001f;
    let t_max = 10000.0f;

    // Initialize a seed based on pixel coordinates (and optionally the frame number)
    uint seed = pixel_i.x * 1973u + pixel_i.y * 9277u + 1234u; // 1234u could be replaced by a per-frame value

    // Create the initial camera ray.
    RayDesc ray = CreateRay(cam.inv_view, cam.inv_proj, pixel_i, res, t_min, t_max, seed);

    float3 radiance = float3(0, 0, 0);
    float3 throughput = float3(1, 1, 1);
    const int maxBounces = 4;
    float3 background = float3(0.1, 0.1, 0.1);

    // Path tracing loop: for each bounce, sample the surface and accumulate lighting.
    for (int bounce = 0; bounce < maxBounces; bounce++)
    {
        float t = RayAabbIntersection(Ray(ray.origin, ray.direction), box);
        if (t < 0.0f)
        {
            // No hit: add background radiance and terminate.
            radiance += throughput * background;
            break;
        }

        float3 hit_point = ray.origin + ray.direction * t;
        float3 normal = ComputeAabbNormal(hit_point, box);

        float3 direct_light = CalculateLighting(hit_point, normal, light);
        radiance += throughput * direct_light;

        // --- Indirect Bounce ---
        // Assume a diffuse (Lambertian) surface with constant albedo.
        float3 albedo = float3(1.0, 0.0, 0.0);
        throughput *= albedo;

        // Russian roulette termination.
        float p_rr = max(throughput.x, max(throughput.y, throughput.z));
        if (rand(seed) > p_rr)
        {
            break;
        }
        throughput /= p_rr;

        // Update the ray for the next bounce: sample a new direction in the hemisphere.
        ray.origin = hit_point + normal * 0.001f;
        ray.direction = random_hemisphere(normal, seed);
    }

    p.swapchain.get()[pixel_i.xy] = float4(radiance, 1.0f);
}