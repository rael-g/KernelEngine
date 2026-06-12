#include <kernel_engine/kernel/framework/mesh_render_system.h>
#include <kernel_engine/framework/mesh_render_system_create.h>
#include <kernel_engine/kernel/world/world.h>
#include <kernel_engine/kernel/world/components.h>
#include <kernel_engine/kernel/engine/frame_packet.h>

#include <cstring>
#include <new>

// ── Internal state ───────────────────────────────────────────────────────────

struct ke_mesh_render_system
{
    ke_world         *world;
    ke_allocator     *allocator;
    ke_ecs_registry  *registry;
    ke_component_id   mesh_cid;
    ke_component_id   transform_cid;
    uint32_t          reads[2];
};

// ── Update tick ──────────────────────────────────────────────────────────────
//
// Mirrors C# MeshRenderSystem.Update: iterate the contiguous MeshComponent
// query, skip entries with KE_HANDLE_NONE mesh, fetch the transform per entity,
// append a ke_draw_command into the frame packet until capacity. The transform
// is byte-copied — ke_transform_component.world_matrix is already in the same
// layout as ke_draw_command.transform (ke_mat4).

static void mesh_update(void *handle, ke_world * /*world*/, float /*dt*/, ke_frame_packet *packet)
{
    if (!packet || !handle || !packet->draw_commands) return;
    auto *self = static_cast<ke_mesh_render_system *>(handle);

    ke_entity *entities = nullptr;
    void      *data     = nullptr;
    size_t     count    = 0;
    ke_ecs_registry_query(self->registry, self->mesh_cid, &entities, &data, &count);
    if (count == 0) return;

    auto *meshes = static_cast<const ke_mesh_component *>(data);
    for (size_t i = 0; i < count; ++i) {
        if (packet->draw_count >= packet->draw_capacity) break;
        const ke_mesh_component &m = meshes[i];
        if (m.mesh.idx == KE_HANDLE_NONE) continue;

        auto *transform = static_cast<const ke_transform_component *>(
            ke_ecs_component_get(self->registry, entities[i], self->transform_cid));
        if (!transform) continue;

        ke_draw_command *cmd = &packet->draw_commands[packet->draw_count++];
        cmd->mesh_handle     = m.mesh;
        cmd->material_handle = m.material;
        std::memcpy(&cmd->transform, &transform->world_matrix, sizeof(cmd->transform));
    }
}

// ── Factory ──────────────────────────────────────────────────────────────────

extern "C" ke_result ke_mesh_render_system_create(
    const ke_mesh_render_system_params *params,
    ke_mesh_render_system             **out_system)
{
    if (!params || !params->world || !params->allocator || !out_system) {
        return KE_ERROR_INVALID_ARGUMENT;
    }
    ke_ecs_registry *registry = params->world->get_registry(params->world);
    if (!registry) return KE_ERROR_NOT_INITIALIZED;

    auto *self = static_cast<ke_mesh_render_system *>(
        params->allocator->alloc(params->allocator, sizeof(ke_mesh_render_system), 0));
    if (!self) return KE_ERROR_OUT_OF_MEMORY;
    new (self) ke_mesh_render_system{};

    self->world         = params->world;
    self->allocator     = params->allocator;
    self->registry      = registry;
    // Phase 3 of ECS-pure nodes: the mesh component carries both resolved
    // handles AND the bake-request fields. The SceneLoader writes primitive
    // (string, copied into a 32-byte buffer so it survives the variant's
    // transient pointer) and color (vec4 over the four sequential floats).
    // ke_mesh_asset_system later reads those and fills the handles.
    static const ke_component_field kMeshFields[] = {
        {"primitive", KE_VARIANT_STRING, (uint32_t)offsetof(ke_mesh_component, primitive), 32},
        {"color",     KE_VARIANT_VEC4,   (uint32_t)offsetof(ke_mesh_component, color),      0},
    };
    self->mesh_cid      = ke_ecs_component_register_v2(
        registry, "mesh", sizeof(ke_mesh_component),
        kMeshFields, sizeof(kMeshFields) / sizeof(kMeshFields[0]));
    self->transform_cid = params->world->transform_id(params->world);
    self->reads[0]      = self->mesh_cid;
    self->reads[1]      = self->transform_cid;

    *out_system = self;
    return KE_OK;
}

extern "C" void ke_mesh_render_system_destroy(ke_mesh_render_system *system)
{
    if (!system) return;
    ke_allocator *alloc = system->allocator;
    system->~ke_mesh_render_system();
    alloc->free(alloc, system);
}

extern "C" ke_component_id ke_mesh_render_system_component_id(
    const ke_mesh_render_system *system)
{
    return system ? system->mesh_cid : 0u;
}

extern "C" void ke_mesh_render_system_get_system_params(
    ke_mesh_render_system *system, ke_system_params *out_params)
{
    if (!out_params) return;
    *out_params = ke_system_params{};
    if (!system) return;
    out_params->name        = "ke_mesh_render_system";
    out_params->update      = mesh_update;
    out_params->handle      = system;
    out_params->reads       = system->reads;
    out_params->read_count  = 2;
    out_params->writes      = nullptr;
    out_params->write_count = 0;
}
