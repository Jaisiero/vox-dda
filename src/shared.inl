#pragma once

#include "daxa/daxa.inl"

struct ComputePush
{
  daxa_u32vec2 res;
  daxa::RWTexture2DId<daxa_f32vec4> image_id;
  daxa::BufferId voxel_buffer;
};
