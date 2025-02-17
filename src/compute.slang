#include "daxa/daxa.inl"
#include "shared.inl"

// Push constant struct
[[vk::push_constant]] ComputePush p;

// Entry point with HLSL semantics
[numthreads(8, 4, 1)] void entry_compute_shader(uint2 pixel_i : SV_DispatchThreadID)
{
  // global histogram buffer
  uint2 res = p.res;
  if(pixel_i.x >= res.x || pixel_i.y >= res.y) return;

  // draw pixel
  p.image_id.get()[pixel_i.xy] = float4(1, 1, 1, 1);
}