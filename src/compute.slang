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
static AreaLight area_light = AreaLight(float3(0, 5, 0), float3(0, -1, 0), float3(20, 20, 20), float2(2, 2));

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

func AreaLightSample(AreaLight area_light, inout uint seed, out float3 light_normal) -> float3{
    // Compute an orthonormal basis for the area light's plane.
    light_normal = normalize(area_light.normal);
    float3 tangent;
    if (abs(light_normal.x) > 0.1)
        tangent = normalize(cross(light_normal, float3(0, 1, 0)));
    else
        tangent = normalize(cross(light_normal, float3(1, 0, 0)));
    float3 bitangent = cross(light_normal, tangent);

    // Uniformly sample a point on the area light.
    // We generate offsets in the range [-0.5, 0.5] and then scale by the light's size.
    float u = rand(seed) - 0.5;
    float v = rand(seed) - 0.5;
    return area_light.position 
                        + tangent * (u * area_light.size.x)
                        + bitangent * (v * area_light.size.y);
}

func CalculateLightingArea(float3 hit_point, float3 surface_normal, float3 albedo, AreaLight area_light, inout uint seed, out float pdf_light, out float3 light_dir) -> float3 {
    
    pdf_light = 0.0f;

    // Sample a point on the area light.
    float3 light_normal = float3(0.0);
    float3 light_sample = AreaLightSample(area_light, seed, light_normal);

    // Compute the vector from the hit point to the sampled light position.
    float3 L = light_sample - hit_point;
    float distance2 = dot(L, L);
    float distance = sqrt(distance2);
    light_dir = normalize(L);

    // Compute cosine factors:
    // cos_theta: angle between light's normal (facing outwards) and the direction from the light sample to the hit point.
    // cos_phi: angle between the surface normal at the hit point and the direction to the light.
    float cos_theta = max(dot(-light_dir, light_normal), 0.0);
    float cos_phi   = max(dot(surface_normal, light_dir), 0.0);
    if (cos_phi <= 0.0 || cos_theta <= 0.0)
        return float3(0,0,0);

    // Geometry term: accounts for the foreshortening and inverse-square falloff.
    float G = (cos_theta * cos_phi) / distance2;

    // Compute the total area of the light's surface.
    float area_total = area_light.size.x * area_light.size.y;

    // Shadow test: cast a ray toward the light sample.
    Ray shadow_ray = Ray(hit_point + surface_normal * 0.001, light_dir);
    float t_shadow = RayAabbIntersection(shadow_ray, box);
    // If the shadow ray hits an object before reaching the light sample, block the light.
    float visibility = (t_shadow > 0.0 && t_shadow < distance) ? 0.0 : 1.0;

    pdf_light = (1.0 / area_total) * visibility;

    float3 brdf = albedo / PI;

    // The final contribution:
    // Note: when sampling uniformly over the area, the PDF is 1/area_total,
    // so multiplying by area_total cancels the division by the PDF.
    return area_light.emission * G * visibility * brdf * cos_phi * area_total;
}

// A simple pseudo-random generator based on a hash.
func rand(inout uint seed) -> float
{
    seed = seed * 1664525u + 1013904223u;
    return (seed & 0x00FFFFFFu) / float(0x01000000u);
}

// A hash function that takes two uints (pixel.x, pixel.y) and a u64 frame.
func hash_seed_u64(uint a, uint b, daxa_u64 frame) -> uint {
    // Split the 64-bit frame into two 32-bit values.
    uint frame_low = uint(frame & 0xFFFFFFFFu);
    uint frame_high = uint(frame >> 32u);
    
    uint h = a;
    h ^= b + 0x9e3779b9u + (h << 6) + (h >> 2);
    h ^= frame_low + 0x9e3779b9u + (h << 6) + (h >> 2);
    h ^= frame_high + 0x9e3779b9u + (h << 6) + (h >> 2);
    return h;
}

// Initialize the seed using the pixel coordinates and a 64-bit frame counter.
func init_seed(daxa_u32vec2 pixel, daxa_u64 frame) -> uint {
    return hash_seed_u64(pixel.x, pixel.y, frame);
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


func sample_lambertian(float3 normal, float3 albedo, out float3 out_dir, out float pdf, out float3 brdf, inout uint seed) -> float3
{
    out_dir = random_hemisphere(normal, seed);
    pdf = dot(out_dir, normal) / PI;
    brdf = albedo / PI;
    return out_dir;
}

[numthreads(8, 4, 1)] void entry_compute_shader(uint2 pixel_i : SV_DispatchThreadID)
{
    uint2 res = p.res;
    if (pixel_i.x >= res.x || pixel_i.y >= res.y)
        return;

    let cam = (CameraView *)(p.cam);
    let frame_count = p.frame_count;
    let t_min = 0.0001f;
    let t_max = 10000.0f;

    // Initialize a seed based on pixel coordinates (and optionally the frame number)
    uint seed = init_seed(pixel_i, frame_count);

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

        daxa::f32 pdf_light;
        daxa::f32vec3 light_dir;

        // FIXME: pass material properties
        float3 albedo = float3(1.0, 0.0, 0.0);

        float3 direct_light = CalculateLightingArea(hit_point, normal, albedo, area_light, seed, pdf_light, light_dir);

        if(pdf_light > 0.0f){
            // MIS: balance the direct and indirect contributions.
            float weight = 1.0f;
            if (bounce > 0)
            {
                float cos_theta = max(dot(normal, light_dir), 0.0f);
                float pdf_brdf = cos_theta / PI;
                weight = pdf_brdf / (pdf_brdf + pdf_light);
            }
            radiance += throughput * direct_light * weight;
        }
        
        float3 bounce_dir;
        float pdf_brdf;
        float3 brdf;

        // Update the ray for the next bounce: sample a new direction in the hemisphere.
        ray.origin = hit_point + normal * 0.001f;
        ray.direction = sample_lambertian(normal, albedo, bounce_dir, pdf_brdf, brdf, seed);

        // --- Indirect Bounce ---
        // Assume a diffuse (Lambertian) surface with constant albedo.
        float cos_theta = max(dot(normal, bounce_dir), 0.0f);
        throughput *= brdf * cos_theta / pdf_brdf;

        // Russian roulette termination.
        float p_rr = max(throughput.x, max(throughput.y, throughput.z));
        if (rand(seed) > p_rr)
        {
            break;
        }
        throughput /= p_rr;
    }

    p.swapchain.get()[pixel_i.xy] = float4(radiance, 1.0f);
}