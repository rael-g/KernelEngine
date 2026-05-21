#pragma once

#include <cstdint>

namespace kernel_engine::render::core
{

// ── Constants and Limits ──────────────────────────────────────────────────
static constexpr uint16_t kInvalidHandle = UINT16_MAX;
static constexpr uint32_t kInvalidShadowHandle = UINT32_MAX;
static constexpr uint32_t kSsaoKernelSize = 16;

// ── bgfx view IDs ─────────────────────────────────────────────────────────
static constexpr uint8_t kShadowView    = 0; // depth-only shadow pass
static constexpr uint8_t kLightCullView = 1; // compute light culling
static constexpr uint8_t kDepthView     = 2; // depth-only prepass for culling
static constexpr uint8_t kPrepassView   = 3; // G-buffer (normals + linear depth)
static constexpr uint8_t kSsaoView      = 4; // SSAO occlusion raw
static constexpr uint8_t kSsaoBlurView  = 5; // SSAO 5x5 blur
static constexpr uint8_t kSkyboxView    = 7; // unused — skybox submits into kSceneView
static constexpr uint8_t kSceneView     = 6; // main forward pass (skybox + geometry)
static constexpr uint8_t kBrightView    = 8; // bloom bright-pass
static constexpr uint8_t kBlurHView     = 9; // bloom blur horizontal
static constexpr uint8_t kBlurVView     = 10; // bloom blur vertical
static constexpr uint8_t kTonemapView   = 11; // tonemap → backbuffer

} // namespace kernel_engine::render::core
