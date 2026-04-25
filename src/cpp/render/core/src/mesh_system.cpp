#include "../include/native_systems.hpp"
#include <kernel_engine/kernel/world/ecs.h>
#include <kernel_engine/kernel/world/components.h>
#include <stdatomic.h>
#include <stdlib.h>

namespace kernel_engine::render::bgfx
{

struct MeshSystemContext {
    uint32_t mesh_cid;
    uint32_t transform_cid;
    uint32_t reads[2];
};

void MeshSystem::Update(void* handle, ke_world* world, float dt, ke_frame_packet* packet)
{
    if (!world || !packet || !handle) return;

    MeshSystemContext* ctx = static_cast<MeshSystemContext*>(handle);
    ke_ecs_registry* reg = world->get_registry(world);

    ke_entity* entities;
    void* data;
    size_t count;
    ke_ecs_registry_query(reg, ctx->mesh_cid, &entities, &data, &count);

    ke_mesh_component* meshes = static_cast<ke_mesh_component*>(data);

    for (size_t i = 0; i < count; i++)
    {
        if (meshes[i].mesh_handle == 0xFFFFFFFF) continue;

        ke_transform_component* tc = static_cast<ke_transform_component*>(
            ke_ecs_component_get(reg, entities[i], ctx->transform_cid));

        if (tc)
        {
            uint32_t index = atomic_fetch_add((_Atomic uint32_t*)&packet->draw_count, 1);
            if (index < packet->draw_capacity)
            {
                ke_draw_command* cmd = &packet->draw_commands[index];
                cmd->mesh_handle     = meshes[i].mesh_handle;
                cmd->material_handle = meshes[i].material_handle;
                cmd->transform       = tc->world_matrix;
            }
        }
    }
}

ke_system_desc MeshSystem::GetDescription(uint32_t mesh_cid, uint32_t transform_cid)
{
    MeshSystemContext* ctx = (MeshSystemContext*)malloc(sizeof(MeshSystemContext));
    ctx->mesh_cid       = mesh_cid;
    ctx->transform_cid  = transform_cid;
    ctx->reads[0]       = mesh_cid;
    ctx->reads[1]       = transform_cid;

    ke_system_desc desc = {};
    desc.name        = "MeshSystem";
    desc.update      = MeshSystem::Update;
    desc.handle      = ctx;
    desc.reads       = ctx->reads;
    desc.read_count  = 2;
    desc.writes      = nullptr;
    desc.write_count = 0;
    return desc;
}

} // namespace kernel_engine::render::bgfx
