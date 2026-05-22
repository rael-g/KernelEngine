#pragma once

#include <cstdint>

namespace kernel_engine::render::core
{

// Pipeline view assignment. A "view" is just a numbered bucket to the GPU device
// (it takes uint16_t); these names are the render pipeline's layout, so they live
// in render-core, not the backend-agnostic device contract.
enum class ViewId : uint16_t
{
    Shadow     = 0,
    Scene      = 1,
    Ssao       = 2,
    BrightPass = 3,
    BlurH      = 4,
    BlurV      = 5,
    Tonemap    = 6,
};

constexpr uint16_t Id(ViewId view) { return static_cast<uint16_t>(view); }

} // namespace kernel_engine::render::core
