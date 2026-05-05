#include <gtest/gtest.h>
#include <gmock/gmock.h>
#include <native_systems.hpp>
#include <kernel_engine/kernel/world/world.h>
#include <kernel_engine/kernel/world/ecs.h>
#include <kernel_engine/kernel/world/components.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <stdlib.h>
#include "mocks.hpp"

using namespace kernel_engine::render::bgfx;

class NativeSystemsTest : public ::testing::Test {
protected:
    void SetUp() override {
        std::memset(&alloc, 0, sizeof(alloc));
        alloc.alloc = [](ke_allocator*, size_t s, size_t) { return std::malloc(s); };
        alloc.free  = [](ke_allocator*, void* p) { std::free(p); };

        ke_ecs_registry_create(&alloc, &registry);

        std::memset(&mock_world, 0, sizeof(mock_world));
        mock_world.get_registry = [](ke_world* self) {
            return (ke_ecs_registry*)self->handle;
        };
        mock_world.handle = registry;

        camera_cid    = ke_ecs_component_register(registry, "camera",    sizeof(ke_camera_component));
        transform_cid = ke_ecs_component_register(registry, "transform", sizeof(ke_transform_component));
        mesh_cid      = ke_ecs_component_register(registry, "mesh",      sizeof(ke_mesh_component));
        light_cid     = ke_ecs_component_register(registry, "light",     sizeof(ke_light_component));
        point_cid     = ke_ecs_component_register(registry, "point",     sizeof(ke_point_light_component));
        spot_cid      = ke_ecs_component_register(registry, "spot",      sizeof(ke_spot_light_component));

        cam_system    = CameraSystem::GetDescription(camera_cid, transform_cid);
        mesh_system   = MeshSystem::GetDescription(mesh_cid, transform_cid);
        light_system  = LightSystem::GetDescription(light_cid, point_cid, spot_cid, transform_cid);
    }

    void TearDown() override {
        if (cam_system.handle)   free(cam_system.handle);
        if (mesh_system.handle)  free(mesh_system.handle);
        if (light_system.handle) free(light_system.handle);
        ke_ecs_registry_destroy(registry);
    }

    ke_allocator alloc{};
    ke_ecs_registry* registry = nullptr;
    ke_world mock_world{};
    uint32_t camera_cid, transform_cid, mesh_cid, light_cid, point_cid, spot_cid;
    ke_system_desc cam_system{}, mesh_system{}, light_system{};
};

TEST_F(NativeSystemsTest, CameraSystem_Update_FillsCameraPositionX) {
    ke_entity cam_entity = ke_ecs_entity_create(registry);
    auto* tc = (ke_transform_component*)ke_ecs_component_add(registry, cam_entity, transform_cid);
    ke_ecs_component_add(registry, cam_entity, camera_cid);
    tc->position.x = 10.0f;

    ke_frame_packet packet{};
    cam_system.update(cam_system.handle, &mock_world, 0.016f, &packet);

    EXPECT_FLOAT_EQ(packet.camera.pos_x, 10.0f);
}

TEST_F(NativeSystemsTest, MeshSystem_Update_IncrementsDrawCount) {
    ke_entity ent = ke_ecs_entity_create(registry);
    auto* mc = (ke_mesh_component*)ke_ecs_component_add(registry, ent, mesh_cid);
    ke_ecs_component_add(registry, ent, transform_cid);
    mc->mesh_handle = {1};

    ke_frame_packet packet{};
    packet.draw_capacity = 10;
    packet.draw_commands = (ke_draw_command*)malloc(sizeof(ke_draw_command) * 10);
    packet.draw_count = 0;
    
    mesh_system.update(mesh_system.handle, &mock_world, 0.016f, &packet);

    EXPECT_EQ(packet.draw_count, 1);
    free(packet.draw_commands);
}

TEST_F(NativeSystemsTest, LightSystem_Update_SetsDirectionalIntensity) {
    ke_entity l_entity = ke_ecs_entity_create(registry);
    auto* lc = (ke_light_component*)ke_ecs_component_add(registry, l_entity, light_cid);
    lc->intensity = 5.0f;

    ke_frame_packet packet{};
    light_system.update(light_system.handle, &mock_world, 0.016f, &packet);

    EXPECT_FLOAT_EQ(packet.dir_light.intensity, 5.0f);
}
