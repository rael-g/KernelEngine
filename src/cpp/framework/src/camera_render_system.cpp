#include <kernel_engine/kernel/framework/camera_render_system.h>
#include <kernel_engine/framework/camera_render_system_create.h>
#include <kernel_engine/kernel/ecs/world.h>
#include <kernel_engine/kernel/ecs/components.h>
#include <kernel_engine/kernel/engine/frame_packet.h>

#define GLM_FORCE_DEPTH_ZERO_TO_ONE
#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>
#include <glm/gtc/type_ptr.hpp>

#include <cstring>
#include <cstdlib>

// ── Internal state ───────────────────────────────────────────────────────────

struct ke_camera_render_system
{
    ke_world         *world;
    ke_allocator     *allocator;
    ke_ecs_registry  *registry;
    ke_component_id   camera_cid;
    ke_component_id   transform_cid;
    int               ndc_y_flip;
    int               ndc_zero_to_one_depth;
    float             aspect;

    // Stable storage for ke_system_params.reads (returned by get_system_params).
    uint32_t          reads[2];
};

// ── Update tick ──────────────────────────────────────────────────────────────
//
// Ported from C# CameraRenderSystem.Update. Differences worth flagging:
//   * GLM matrices are column-major; we memcpy raw bytes into ke_mat4 (which the
//     renderer also treats column-major). Same double-blit identity the C# code
//     relies on with System.Numerics.
//   * View = inverse(world_matrix). TransformComponent.world_matrix is written
//     by the TransformSystem each tick in the engine's row-major+row-vector
//     convention; glm::inverse on a column-major reinterpretation is the
//     transpose of the real inverse — but we feed it BACK as a column-major
//     view matrix, so the transposes cancel (same trick CameraRenderSystem.cs
//     leans on with Matrix4x4.Invert).

static void camera_update(void *handle, ke_world *world, float /*dt*/, ke_frame_packet *packet)
{
    if (!packet || !handle) return;
    auto *self = static_cast<ke_camera_render_system *>(handle);

    ke_entity *entities = nullptr;
    void      *data     = nullptr;
    size_t     count    = 0;
    ke_ecs_registry_query(self->registry, self->camera_cid, &entities, &data, &count);
    if (count == 0) return;

    auto *cameras = static_cast<ke_camera_component *>(data);
    ke_entity cam_entity = entities[0];
    const ke_camera_component cam = cameras[0];

    auto *transform = static_cast<ke_transform_component *>(
        ke_ecs_component_get(self->registry, cam_entity, self->transform_cid));
    if (!transform) return;

    // Reinterpret the byte buffer as a glm::mat4 (column-major). See note above.
    glm::mat4 world_mat;
    std::memcpy(&world_mat, &transform->world_matrix, sizeof(world_mat));
    glm::mat4 view = glm::inverse(world_mat);

    glm::mat4 proj;
    if (cam.orthographic != 0) {
        float right_extent = self->aspect * cam.orthographic_size;
        float top_extent   = cam.orthographic_size;
        // GLM_FORCE_DEPTH_ZERO_TO_ONE enables _ZO variants by default; we still
        // dispatch explicitly to honour the runtime ndc_zero_to_one_depth flag.
        proj = self->ndc_zero_to_one_depth
            ? glm::orthoRH_ZO(-right_extent, right_extent, -top_extent, top_extent, cam.near_plane, cam.far_plane)
            : glm::orthoRH_NO(-right_extent, right_extent, -top_extent, top_extent, cam.near_plane, cam.far_plane);
    } else {
        proj = self->ndc_zero_to_one_depth
            ? glm::perspectiveRH_ZO(cam.fov, self->aspect, cam.near_plane, cam.far_plane)
            : glm::perspectiveRH_NO(cam.fov, self->aspect, cam.near_plane, cam.far_plane);
    }

    if (self->ndc_y_flip) {
        // bgfx Vulkan path expects a Y-flipped clip space; GLM's _NO/_ZO builders
        // don't bake that flip. Mirror what ViewProjection.cs does by scaling Y.
        proj[1][1] = -proj[1][1];
    }

    std::memcpy(&packet->camera.view, &view, sizeof(view));
    std::memcpy(&packet->camera.proj, &proj, sizeof(proj));
    packet->camera.pos_x = transform->position.x;
    packet->camera.pos_y = transform->position.y;
    packet->camera.pos_z = transform->position.z;
    (void)world;
}

// ── Factory ──────────────────────────────────────────────────────────────────

extern "C" ke_result ke_camera_render_system_create(
    const ke_camera_render_system_params *params,
    ke_camera_render_system             **out_system)
{
    if (!params || !params->world || !params->allocator || !out_system) {
        return KE_ERROR_INVALID_ARGUMENT;
    }
    ke_ecs_registry *registry = params->world->get_registry(params->world);
    if (!registry) return KE_ERROR_NOT_INITIALIZED;

    auto *self = static_cast<ke_camera_render_system *>(
        params->allocator->alloc(params->allocator, sizeof(ke_camera_render_system), 0));
    if (!self) return KE_ERROR_OUT_OF_MEMORY;
    new (self) ke_camera_render_system{};

    self->world         = params->world;
    self->allocator     = params->allocator;
    self->registry      = registry;
    // Phase 2 of ECS-pure nodes: register with field metadata so the new
    // SceneLoader path can write into the component without per-binding code.
    // Short snake_case name matches the [entity.components.camera] TOML key
    // (design decision #6).
    static const ke_component_field kCameraFields[] = {
        {"fov",               KE_VARIANT_FLOAT, (uint32_t)offsetof(ke_camera_component, fov)},
        {"near",              KE_VARIANT_FLOAT, (uint32_t)offsetof(ke_camera_component, near_plane)},
        {"far",               KE_VARIANT_FLOAT, (uint32_t)offsetof(ke_camera_component, far_plane)},
        {"orthographic_size", KE_VARIANT_FLOAT, (uint32_t)offsetof(ke_camera_component, orthographic_size)},
        {"orthographic",      KE_VARIANT_BOOL,  (uint32_t)offsetof(ke_camera_component, orthographic)},
    };
    self->camera_cid    = ke_ecs_component_register_v2(
        registry, "camera", sizeof(ke_camera_component),
        kCameraFields, sizeof(kCameraFields) / sizeof(kCameraFields[0]));
    self->transform_cid = params->world->transform_id(params->world);
    self->ndc_y_flip    = params->ndc_y_flip;
    self->ndc_zero_to_one_depth = params->ndc_zero_to_one_depth;
    self->aspect        = params->aspect > 0.0f ? params->aspect : 1.77f;
    self->reads[0]      = self->camera_cid;
    self->reads[1]      = self->transform_cid;

    *out_system = self;
    return KE_OK;
}

extern "C" void ke_camera_render_system_destroy(ke_camera_render_system *system)
{
    if (!system) return;
    ke_allocator *alloc = system->allocator;
    system->~ke_camera_render_system();
    alloc->free(alloc, system);
}

extern "C" ke_component_id ke_camera_render_system_component_id(
    const ke_camera_render_system *system)
{
    return system ? system->camera_cid : 0u;
}

extern "C" void ke_camera_render_system_get_system_params(
    ke_camera_render_system *system, ke_system_params *out_params)
{
    if (!out_params) return;
    *out_params = ke_system_params{};
    if (!system) return;
    out_params->name        = "ke_camera_render_system";
    out_params->update      = camera_update;
    out_params->handle      = system;
    out_params->reads       = system->reads;
    out_params->read_count  = 2;
    out_params->writes      = nullptr;
    out_params->write_count = 0;
}
