#include "../include/native_systems.hpp"
#include <kernel_engine/kernel/world/ecs.h>
#include <kernel_engine/kernel/world/components.h>
#include <stdlib.h>

namespace kernel_engine::render::bgfx
{

struct SkyboxSystemContext {
    uint32_t skybox_cid;
};

void SkyboxSystem::Update(void* handle, ke_world* world, float dt, ke_frame_packet* packet)
{
    if (!world || !packet || !handle) return;
    
    SkyboxSystemContext* ctx = static_cast<SkyboxSystemContext*>(handle);
    ke_ecs_registry* reg = world->get_registry(world);

    ke_entity* entities; void* data; size_t count;
    ke_ecs_registry_query(reg, ctx->skybox_cid, &entities, &data, &count);

    if (count > 0)
    {
        ke_skybox_component* skyboxes = static_cast<ke_skybox_component*>(data);
        if (skyboxes[0].cubemap_handle != 0xFFFFFFFF)
        {
            packet->skybox_handle = skyboxes[0].cubemap_handle;
            packet->has_skybox = true;
        }
    }
}

ke_system_desc SkyboxSystem::GetDescription(uint32_t skybox_cid)
{
    SkyboxSystemContext* ctx = (SkyboxSystemContext*)malloc(sizeof(SkyboxSystemContext));
    ctx->skybox_cid = skybox_cid;

    static uint32_t reads[1];
    reads[0] = skybox_cid;

    ke_system_desc desc = {};
    desc.name = "SkyboxSystem";
    desc.update = SkyboxSystem::Update;
    desc.handle = ctx;
    desc.reads = reads;
    desc.read_count = 1;
    
    return desc;
}

} // namespace kernel_engine::render::bgfx
