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
static Aabb box = Aabb(float3(-4.0, -4.0, -4.0), float3(4.0, 4.0, 4.0), float3(0.0));
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

// Returns (t_entry, t_exit) for the ray–AABB intersection.
// If the ray does not intersect, returns float2(-1, -1).
func RayAabbIntersectionRange(Ray ray, Aabb box) -> float2
{
    float3 inv_dir = 1.0f / ray.direction;
    float3 t0 = (box.min - ray.origin) * inv_dir;
    float3 t1 = (box.max - ray.origin) * inv_dir;

    float3 tmin = min(t0, t1);
    float3 tmax = max(t0, t1);

    float t_entry = max(tmin.x, max(tmin.y, tmin.z));
    float t_exit  = min(tmax.x, min(tmax.y, tmax.z));

    // If t_exit < 0, the entire box is behind the ray.
    if (t_exit < 0.0f) {
        return float2(-1.0f, -1.0f);
    }

    // If the ray starts inside the box, t_entry can be negative.
    // Clamp it to 0 so we start "now."
    if (t_entry < 0.0f) {
        t_entry = 0.0f;
    }

    // If after clamping t_entry we still have t_entry > t_exit, no intersection.
    if (t_entry > t_exit) {
        return float2(-1.0f, -1.0f);
    }

    return float2(t_entry, t_exit);
}

func ComputeBoxFaceNormal(float3 hit_point, Aabb aabb) -> float3
{
    float3 d = hit_point - BoxCenter(aabb);
    float3 abs_d = abs(d);
    if (abs_d.x >= abs_d.y && abs_d.x >= abs_d.z)
        return float3(sign(d.x), 0, 0);
    else if (abs_d.y >= abs_d.z)
        return float3(0, sign(d.y), 0);
    else
        return float3(0, 0, sign(d.z));
}

struct DDAHit {
    float t;
    float3 normal;
};

// DDA traversal function that returns the distance along the ray when a voxel is hit,
// or -1.0 if no voxel is hit.
func DDATraverse(Ray ray, Aabb box, uint* voxel_buffer) -> DDAHit {
    // FIXME: assume an 8x8x8 grid:
    const int grid_dim = 8;
    // Compute cell (voxel) size.
    float3 grid_size = box.max - box.min;
    float3 cell_size = grid_size / float3(grid_dim, grid_dim, grid_dim);

    // Get the entry point (t_entry) into the AABB.
    float2 t_range = RayAabbIntersectionRange(ray, box);
    float t_entry = t_range.x;
    float t_exit = t_range.y;
    if (t_entry < 0.0) {
        // Ray misses the grid.
        return DDAHit(-1.0, float3(0.0));
    }

    // Compute starting point inside the grid.
    float3 pos = ray.origin + ray.direction * (t_entry);

    // Determine initial voxel coordinates.
    int3 voxel;
    voxel.x = int(clamp(floor((pos.x - box.min.x) / cell_size.x), 0.0, float(grid_dim - 1)));
    voxel.y = int(clamp(floor((pos.y - box.min.y) / cell_size.y), 0.0, float(grid_dim - 1)));
    voxel.z = int(clamp(floor((pos.z - box.min.z) / cell_size.z), 0.0, float(grid_dim - 1)));

    // Compute the step direction.
    int3 step;
    step.x = (ray.direction.x >= 0.0) ? 1 : -1;
    step.y = (ray.direction.y >= 0.0) ? 1 : -1;
    step.z = (ray.direction.z >= 0.0) ? 1 : -1;

    // Compute t_delta: distance along ray to cross one cell.
    float3 t_delta;
    t_delta.x = (ray.direction.x != 0.0) ? cell_size.x / abs(ray.direction.x) : 1e10;
    t_delta.y = (ray.direction.y != 0.0) ? cell_size.y / abs(ray.direction.y) : 1e10;
    t_delta.z = (ray.direction.z != 0.0) ? cell_size.z / abs(ray.direction.z) : 1e10;

    // Compute t_max: distance along ray to first voxel boundary.
    float3 voxel_boundary;
    if (step.x > 0)
        voxel_boundary.x = box.min.x + (voxel.x + 1) * cell_size.x;
    else
        voxel_boundary.x = box.min.x + (voxel.x) * cell_size.x;
    if (step.y > 0)
        voxel_boundary.y = box.min.y + (voxel.y + 1) * cell_size.y;
    else
        voxel_boundary.y = box.min.y + (voxel.y) * cell_size.y;
    if (step.z > 0)
        voxel_boundary.z = box.min.z + (voxel.z + 1) * cell_size.z;
    else
        voxel_boundary.z = box.min.z + (voxel.z) * cell_size.z;

    float3 t_max;
    t_max.x = (ray.direction.x != 0.0) ? (voxel_boundary.x - pos.x) / ray.direction.x : 1e10;
    t_max.y = (ray.direction.y != 0.0) ? (voxel_boundary.y - pos.y) / ray.direction.y : 1e10;
    t_max.z = (ray.direction.z != 0.0) ? (voxel_boundary.z - pos.z) / ray.direction.z : 1e10;

    // Loop through the voxel grid.
    while ( (voxel.x >= 0 && voxel.x < grid_dim) &&
            (voxel.y >= 0 && voxel.y < grid_dim) &&
            (voxel.z >= 0 && voxel.z < grid_dim) ) {
        // Compute 1D index from 3D voxel coordinate.
        let index = voxel.z * grid_dim * grid_dim + voxel.y * grid_dim + voxel.x;

        // If the current voxel is occupied:
        if ((voxel_buffer[index >> 5] & (1u << (index & 31))) != 0) {
            // 1) We know the voxel coordinates (voxel.x, voxel.y, voxel.z).
            float3 voxel_min = box.min + float3(voxel) * cell_size;
            float3 voxel_max = voxel_min + cell_size;

            // 2) Intersect the ray with the voxel’s bounding box:
            float t_voxel = RayAabbIntersection(ray, Aabb(voxel_min, voxel_max));
            if (t_voxel >= 0.0f) {
                // 3) The normal is whichever face the ray hits on that bounding box.
                float3 normal = ComputeBoxFaceNormal(ray.origin + ray.direction * t_voxel, Aabb(voxel_min, voxel_max));

                // Return the intersection distance and normal
                return DDAHit(t_voxel, normal);
            }
        }

        // Step to next voxel:
        if (t_max.x < t_max.y) {
            if (t_max.x < t_max.z) {
                voxel.x += step.x;
                t_max.x += t_delta.x;
            } else {
                voxel.z += step.z;
                t_max.z += t_delta.z;
            }
        } else {
            if (t_max.y < t_max.z) {
                voxel.y += step.y;
                t_max.y += t_delta.y;
            } else {
                voxel.z += step.z;
                t_max.z += t_delta.z;
            }
        }
    }

    // If we exit the grid without a hit, return -1.
    return DDAHit(-1.0, float3(0.0));
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

func CalculateLightingArea(float3 hit_point, float3 surface_normal, float3 albedo, AreaLight area_light, uint* voxel_buffer, inout uint seed, out float pdf_light, out float3 light_dir) -> float3 {
    
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
    DDAHit t_shadow = DDATraverse(shadow_ray, box, voxel_buffer);
    // If the shadow ray hits an object before reaching the light sample, block the light.
    float visibility = (t_shadow.t > 0.0 && t_shadow.t < distance) ? 0.0 : 1.0;

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
    let frame_index = p.frame_index;
    let t_min = 0.0001f;
    let t_max = 10000.0f;
    let flags = p.flags;
    let frame_count = p.frame_count;

    uint* voxel_data = (uint *)(p.voxel_buffer);

    // Initialize a seed based on pixel coordinates (and optionally the frame number)
    uint seed = init_seed(pixel_i, frame_index);

    // Create the initial camera ray.
    RayDesc ray = CreateRay(cam.inv_view, cam.inv_proj, pixel_i, res, t_min, t_max, seed);

    float3 radiance = float3(0, 0, 0);
    float3 throughput = float3(1, 1, 1);
    const int max_bounces = 4;
    float3 background = float3(0.1, 0.1, 0.1);

    // Path tracing loop: for each bounce, sample the surface and accumulate lighting.
    for (int bounce = 0; bounce < max_bounces; bounce++)
    {
        DDAHit hit = DDATraverse(Ray(ray.origin, ray.direction), box, voxel_data);
        if (hit.t < 0.0f)
        {
            // No hit: add background radiance and terminate.
            radiance += throughput * background;
            break;
        }

        // add emissive light
        radiance += throughput * box.emission;

        float3 hit_point = ray.origin + ray.direction * hit.t;
        float3 normal = hit.normal;

        float pdf_light;
        float3 light_dir;

        // FIXME: pass material properties
        float3 albedo = float3(1.0, 0.0, 0.0);

        float3 direct_light = CalculateLightingArea(hit_point, normal, albedo, area_light, voxel_data, seed, pdf_light, light_dir);

        if(pdf_light > 0.0f) 
        {
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

    float3 gamma_corrected_average = 0.0f;

    if((flags & ACCUMULATE_ON_FLAG) != 0) 
    {
        // Get the accumulated color
        let accumulated_color = p.accumulation_previous_buffer.get()[pixel_i.xy];

        // Update the accumulated color by frame_count and add the new radiance
        let average_radiance = (accumulated_color.rgb * float(frame_count) + radiance) / float(frame_count + 1);

        // Write the averaged color to the accumulation buffer
        p.accumulation_buffer.get()[pixel_i.xy] = float4(average_radiance, 1.0);

        // Apply gamma correction to the average radiance
        gamma_corrected_average = pow(average_radiance, float(1.0 / 2.2));
    }
    else 
    {
        // Apply gamma correction to the radiance
        gamma_corrected_average = pow(radiance, float(1.0 / 2.2));
    }
    
    p.swapchain.get()[pixel_i.xy] = float4(gamma_corrected_average, 1.0f);
}