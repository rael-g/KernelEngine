#include <gtest/gtest.h>
#include <kernel_engine/framework/input_actions.h>
#include <kernel_engine/framework/input_actions_create.h>
#include <kernel_engine/framework/scene_loader.h>
#include <kernel_engine/framework/scene_loader_create.h>
#include <kernel_engine/framework/scene_tree.h>
#include <kernel_engine/framework/scene_tree_create.h>
#include <kernel_engine/allocator/allocator.h>
#include <kernel_engine/kernel/ecs/world.h>
#include <filesystem>
#include <fstream>

namespace fs = std::filesystem;

class FrameworkIntegrationTest : public ::testing::Test {
protected:
    ke_allocator* alloc = nullptr;
    ke_world* world = nullptr;
    ke_scene_tree* tree = nullptr;

    void SetUp() override {
        alloc = ke_allocator_malloc_create();
        ke_world_params params = { alloc };
        ke_world_create(&params, &world);
        ke_scene_tree_create(world, alloc, &tree);
    }

    void TearDown() override {
        tree->destroy(tree);
        world->destroy(world);
        alloc->destroy(alloc);
    }

    fs::path WriteTempFile(const std::string& suffix, const std::string& content) {
        auto path = fs::temp_directory_path() / (std::string("ke_fw_test_") + std::to_string(rand()) + suffix);
        std::ofstream(path) << content;
        return path;
    }
};

TEST_F(FrameworkIntegrationTest, SceneLoader_FullLoad_Works) {
    auto path = WriteTempFile(".scene.toml", R"(
[[entity]]
name = "Root"
[entity.transform]
position = [1, 2, 3]

[[entity]]
name = "Child"
parent = "Root"
[entity.transform]
scale = [2, 2, 2]
)");

    ke_scene_loader* loader = nullptr;
    ASSERT_EQ(ke_scene_loader_create(alloc, world, tree, ".", &loader), KE_OK);
    
    ASSERT_EQ(loader->load(loader, path.string().c_str()), KE_OK);
    
    ke_entity e_root = tree->find_node(tree, "Root");
    ASSERT_NE(e_root, 0ULL);
    
    ke_entity e_child = tree->find_node(tree, "Root/Child");
    ASSERT_NE(e_child, 0ULL);
    
    loader->destroy(loader);
    fs::remove(path);
}

#include <kernel_engine/kernel/framework/camera_render_system.h>
#include <kernel_engine/framework/camera_render_system_create.h>
#include <kernel_engine/kernel/framework/light_render_system.h>
#include <kernel_engine/framework/light_render_system_create.h>
#include <kernel_engine/render/frame_packet.h>

TEST_F(FrameworkIntegrationTest, CameraSystem_Update_Works) {
    ke_camera_render_system_params params{};
    params.world = world;
    params.allocator = alloc;
    params.aspect = 1.0f;
    
    ke_camera_render_system* sys = nullptr;
    ASSERT_EQ(ke_camera_render_system_create(&params, &sys), KE_OK);
    
    ke_entity cam = ke_ecs_entity_create(world->get_registry(world));
    auto cam_id = ke_camera_render_system_component_id(sys);
    auto* cam_data = (ke_camera_component*)ke_ecs_component_add(world->get_registry(world), cam, cam_id);
    cam_data->fov = 1.0f;
    cam_data->near_plane = 0.1f;
    cam_data->far_plane = 100.0f;
    
    auto t_id = world->transform_id(world);
    auto* t_data = (ke_transform_component*)ke_ecs_component_add(world->get_registry(world), cam, t_id);
    t_data->position = {0, 0, 10};
    t_data->world_matrix = {1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,10,1};

    ke_system_params sys_params;
    ke_camera_render_system_get_system_params(sys, &sys_params);
    
    ke_frame_packet packet{};
    sys_params.update(sys, world, 0.016f, &packet);
    
    // Position should be copied to packet
    EXPECT_FLOAT_EQ(packet.camera.pos_z, 10.0f);
    
    ke_camera_render_system_destroy(sys);
}

#include <kernel_engine/asset/mesh_shape.h>

TEST_F(FrameworkIntegrationTest, MeshShape_Bake_ReturnsOom_WhenAllocFails) {
    ke_allocator fa{};
    fa.alloc = +[](ke_allocator*, size_t, size_t) -> void* { return nullptr; };
    fa.free  = +[](ke_allocator*, void*) {};
    
    ke_mesh_shape_data data{};
    EXPECT_EQ(ke_mesh_shape_bake(&fa, KE_MESH_PRIMITIVE_CUBE, 0, &data), KE_ERROR_OUT_OF_MEMORY);
}

#include <kernel_engine/kernel/framework/mesh_render_system.h>
#include <kernel_engine/framework/mesh_render_system_create.h>

TEST_F(FrameworkIntegrationTest, MeshRenderSystem_Update_Works) {
    ke_mesh_render_system_params params{};
    params.world = world;
    params.allocator = alloc;
    
    ke_mesh_render_system* sys = nullptr;
    ASSERT_EQ(ke_mesh_render_system_create(&params, &sys), KE_OK);
    
    auto reg = world->get_registry(world);
    ke_entity e = ke_ecs_entity_create(reg);
    auto m_id = ke_mesh_render_system_component_id(sys);
    auto* m_data = (ke_mesh_component*)ke_ecs_component_add(reg, e, m_id);
    m_data->mesh.idx = 10;
    m_data->material.idx = 20;
    
    auto t_id = world->transform_id(world);
    auto* t_data = (ke_transform_component*)ke_ecs_component_add(reg, e, t_id);
    t_data->world_matrix = {1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1};

    ke_system_params sys_params;
    ke_mesh_render_system_get_system_params(sys, &sys_params);
    
    ke_frame_packet packet{};
    packet.draw_capacity = 1;
    packet.draw_commands = (ke_draw_command*)malloc(sizeof(ke_draw_command));
    packet.draw_count = 0;
    
    sys_params.update(sys, world, 0.016f, &packet);
    
    ASSERT_EQ(packet.draw_count, 1u);
    EXPECT_EQ(packet.draw_commands[0].mesh_handle.idx, 10u);
    EXPECT_EQ(packet.draw_commands[0].material_handle.idx, 20u);
    
    free(packet.draw_commands);
    ke_mesh_render_system_destroy(sys);
}

#include <kernel_engine/kernel/framework/mesh_asset_system.h>
#include <kernel_engine/framework/mesh_asset_system_create.h>
#include <kernel_engine/kernel/framework/mesh_render_system.h>
#include <kernel_engine/framework/mesh_render_system_create.h>

#include <kernel_engine/render/render.h>
#include <kernel_engine/render/material.h>
#include <kernel_engine/render/mesh.h>

TEST_F(FrameworkIntegrationTest, LightSystem_Ids_Works) {
    ke_light_render_system_params params = { world, alloc };
    ke_light_render_system* sys = nullptr;
    ke_light_render_system_create(&params, &sys);
    
    EXPECT_NE(ke_light_render_system_directional_id(sys), 0u);
    EXPECT_NE(ke_light_render_system_point_id(sys), 0u);
    EXPECT_NE(ke_light_render_system_spot_id(sys), 0u);
    
    ke_light_render_system_destroy(sys);
}

TEST_F(FrameworkIntegrationTest, SceneLoader_RecursiveLoad_Works) {
    auto child_path = WriteTempFile(".scene.toml", "[[entity]]\nname = \"Grandchild\"");
    
    std::string child_path_str = child_path.string();
    std::replace(child_path_str.begin(), child_path_str.end(), '\\', '/');

    auto parent_path = WriteTempFile(".scene.toml", "[[entity]]\nname = \"Child\"\n[entity.scene]\npath = \"" + child_path_str + "\"");

    ke_scene_loader* loader = nullptr;
    ke_scene_loader_create(alloc, world, tree, ".", &loader);
    
    ASSERT_EQ(loader->load(loader, parent_path.string().c_str()), KE_OK);
    
    // Sub-scene root is renamed to "Child".
    EXPECT_NE(tree->find_node(tree, "Child"), 0ULL);
    
    loader->destroy(loader);
    fs::remove(child_path);
    fs::remove(parent_path);
}
