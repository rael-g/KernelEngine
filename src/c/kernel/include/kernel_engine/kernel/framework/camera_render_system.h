#ifndef KERNEL_ENGINE_FRAMEWORK_CAMERA_RENDER_SYSTEM_H_
#define KERNEL_ENGINE_FRAMEWORK_CAMERA_RENDER_SYSTEM_H_

// ke_camera_render_system — native port of C# CameraRenderSystem.
//
// Owns the CameraComponent cid (registered against the world's ECS) and a
// ke_system_params that the caller installs on the world. On every tick the
// system reads the first CameraComponent + its TransformComponent.world_matrix,
// builds view = inverse(world_matrix) and projection (perspective or ortho) via
// GLM in the active backend's NDC convention, then writes both into
// ke_frame_packet.camera.

#include <kernel_engine/kernel/framework/framework_export.h>
#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/world/ecs.h>
#include <kernel_engine/kernel/world/system.h>
#include <stdint.h>

struct ke_world;

#ifdef __cplusplus
extern "C"
{
#endif

    /// Layout MUST mirror KernelEngine.Framework.CameraComponent (System.Numerics
    /// sequential layout): four floats then a single byte. The C# binding adds
    /// the component via the cid this system owns.
    typedef struct ke_camera_component
    {
        float   fov;
        float   near_plane;
        float   far_plane;
        float   orthographic_size;
        uint8_t orthographic; // 0 = perspective, non-zero = ortho
    } ke_camera_component;

    typedef struct ke_camera_render_system_params
    {
        struct ke_world *world;
        ke_allocator    *allocator;
        /// Renderer NDC: Vulkan reports y_flip=1, all D3D/Vulkan use zero_to_one_depth=1,
        /// OpenGL uses both = 0. Passed in because the framework plugin doesn't link the
        /// renderer plugin — caller queries ke_render->get_ndc_convention.
        int              ndc_y_flip;
        int              ndc_zero_to_one_depth;
        /// Window aspect. C# CameraRenderSystem hard-codes 1.77 today; we mirror that
        /// while waiting for a window-size feedback channel.
        float            aspect;
    } ke_camera_render_system_params;

    typedef struct ke_camera_render_system ke_camera_render_system;

    KE_FRAMEWORK_API ke_result ke_camera_render_system_create(
        const ke_camera_render_system_params *params,
        ke_camera_render_system             **out_system);

    KE_FRAMEWORK_API void ke_camera_render_system_destroy(ke_camera_render_system *system);

    /// Returns the cid the system registered for ke_camera_component. Bindings use this
    /// to attach the component to entities. Stable for the lifetime of the system.
    KE_FRAMEWORK_API ke_component_id ke_camera_render_system_component_id(
        const ke_camera_render_system *system);

    /// Writes a ke_system_params suitable for ke_world.add_system into `out_params`.
    /// Pointer fields stay valid for the system's lifetime. (Output is via pointer
    /// rather than struct return-by-value so LuaJIT FFI consumers can read the
    /// callback fields reliably; the MSVC x64 ABI passes >16-byte struct returns
    /// through a hidden pointer that LuaJIT mishandles.)
    KE_FRAMEWORK_API void ke_camera_render_system_get_system_params(
        ke_camera_render_system *system,
        ke_system_params        *out_params);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_FRAMEWORK_CAMERA_RENDER_SYSTEM_H_
