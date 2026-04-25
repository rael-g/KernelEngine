#pragma once

#include <kernel_engine/kernel/world/system.h>
#include <kernel_engine/kernel/engine/frame_packet.h>
#include <kernel_engine/kernel/render/render.h>
#include <kernel_engine/kernel/world/world.h>
#include "render_export.h"

namespace kernel_engine::render::bgfx
{

/**
 * @brief Native implementation of the Mesh Rendering logic.
 */
class KE_RENDER_API MeshSystem
{
public:
    static void Update(void* handle, ke_world* world, float dt, ke_frame_packet* packet);
    static ke_system_desc GetDescription(uint32_t mesh_cid, uint32_t transform_cid);
};

/**
 * @brief Native implementation of the Light Rendering logic (Dir, Point, Spot).
 */
class KE_RENDER_API LightSystem
{
public:
    static void Update(void* handle, ke_world* world, float dt, ke_frame_packet* packet);
    static ke_system_desc GetDescription(uint32_t light_cid, uint32_t point_cid, uint32_t spot_cid, uint32_t transform_cid);
};

/**
 * @brief Native implementation of the Camera logic.
 */
class KE_RENDER_API CameraSystem
{
public:
    static void Update(void* handle, ke_world* world, float dt, ke_frame_packet* packet);
    static ke_system_desc GetDescription(uint32_t camera_cid, uint32_t transform_cid);
};

/**
 * @brief Native implementation of the Shadow Pass logic.
 */
class KE_RENDER_API ShadowSystem
{
public:
    static void Update(void* handle, ke_world* world, float dt, ke_frame_packet* packet);
    static ke_system_desc GetDescription(ke_render* renderer, uint32_t light_cid, uint32_t mesh_cid, uint32_t transform_cid);
};

/**
 * @brief Native implementation of the Skybox recording logic.
 */
class KE_RENDER_API SkyboxSystem
{
public:
    static void Update(void* handle, ke_world* world, float dt, ke_frame_packet* packet);
    static ke_system_desc GetDescription(uint32_t skybox_cid);
};

} // namespace kernel_engine::render::bgfx
