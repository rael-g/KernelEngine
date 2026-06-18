#include <gtest/gtest.h>
#include <kernel_engine/physics/box2d/box2d_physics.h>

class Box2DPhysicsTest : public ::testing::Test {
protected:
    ke_physics_2d_handle physics_h{};
    ke_physics_2d* physics = nullptr;

    void SetUp() override {
        ke_physics_2d_box2d_params params{};
        params.logger = nullptr;
        params.gravity_x = 0;
        params.gravity_y = -9.81f;

        ke_result res = ke_physics_2d_box2d_create(&params, &physics_h, nullptr);
        ASSERT_EQ(res, KE_OK);
        physics = physics_h.ref;
        ASSERT_NE(physics, nullptr);
    }

    void TearDown() override {
        if (physics_h.ref) {
            physics_h.destroy(physics_h.ref);
        }
    }
};

TEST_F(Box2DPhysicsTest, Create_Works) {
    ASSERT_NE(physics, nullptr);
}

TEST_F(Box2DPhysicsTest, SetGravity_Works) {
    physics->set_gravity(physics, 0, -10.0f);
    // Verified by not crashing and later steps if we had a way to query gravity.
}

TEST_F(Box2DPhysicsTest, Step_Works) {
    physics->step(physics, 0.016f);
}

TEST_F(Box2DPhysicsTest, CreateBody_Works) {
    uint32_t id = 0;
    ke_result res = physics->create_body(physics, KE_BODY_TYPE_DYNAMIC, 0, 0, &id, nullptr);
    ASSERT_EQ(res, KE_OK);
    ASSERT_NE(id, 0);
}

TEST_F(Box2DPhysicsTest, AddBoxFixture_Works) {
    uint32_t id = 0;
    physics->create_body(physics, KE_BODY_TYPE_DYNAMIC, 0, 0, &id, nullptr);
    ke_result res = physics->add_box_fixture(physics, id, 1.0f, 1.0f, 1.0f, 0.3f, 0.1f, nullptr);
    ASSERT_EQ(res, KE_OK);
}

TEST_F(Box2DPhysicsTest, AddCircleFixture_Works) {
    uint32_t id = 0;
    physics->create_body(physics, KE_BODY_TYPE_DYNAMIC, 0, 0, &id, nullptr);
    ke_result res = physics->add_circle_fixture(physics, id, 1.0f, 1.0f, 0.3f, 0.1f, nullptr);
    ASSERT_EQ(res, KE_OK);
}

TEST_F(Box2DPhysicsTest, GetBodyState_Works) {
    uint32_t id = 0;
    physics->create_body(physics, KE_BODY_TYPE_DYNAMIC, 10.0f, 20.0f, &id, nullptr);
    
    ke_body_state_2d state{};
    physics->get_body_state(physics, id, &state);
    
    ASSERT_FLOAT_EQ(state.x, 10.0f);
    ASSERT_FLOAT_EQ(state.y, 20.0f);
}

TEST_F(Box2DPhysicsTest, SetBodyPosition_Works) {
    uint32_t id = 0;
    physics->create_body(physics, KE_BODY_TYPE_DYNAMIC, 0, 0, &id, nullptr);
    physics->set_body_position(physics, id, 5.0f, 5.0f, 0.78f);
    
    ke_body_state_2d state{};
    physics->get_body_state(physics, id, &state);
    ASSERT_FLOAT_EQ(state.x, 5.0f);
    ASSERT_FLOAT_EQ(state.y, 5.0f);
    ASSERT_FLOAT_EQ(state.angle, 0.78f);
}

TEST_F(Box2DPhysicsTest, SetBodyVelocity_Works) {
    uint32_t id = 0;
    physics->create_body(physics, KE_BODY_TYPE_DYNAMIC, 0, 0, &id, nullptr);
    physics->set_body_velocity(physics, id, 1.0f, 2.0f);
    
    ke_body_state_2d state{};
    physics->get_body_state(physics, id, &state);
    ASSERT_FLOAT_EQ(state.velocity_x, 1.0f);
    ASSERT_FLOAT_EQ(state.velocity_y, 2.0f);
}

TEST_F(Box2DPhysicsTest, ApplyImpulse_Works) {
    uint32_t id = 0;
    physics->create_body(physics, KE_BODY_TYPE_DYNAMIC, 0, 0, &id, nullptr);
    physics->add_box_fixture(physics, id, 1.0f, 1.0f, 1.0f, 0.3f, 0.1f, nullptr);
    physics->apply_impulse(physics, id, 10.0f, 10.0f);
    
    physics->step(physics, 0.016f);
    
    ke_body_state_2d state{};
    physics->get_body_state(physics, id, &state);
    ASSERT_GT(state.velocity_x, 0);
    ASSERT_GT(state.velocity_y, 0);
}

TEST_F(Box2DPhysicsTest, DestroyBody_Works) {
    uint32_t id = 0;
    physics->create_body(physics, KE_BODY_TYPE_DYNAMIC, 0, 0, &id, nullptr);
    physics->destroy_body(physics, id);
    // Should not crash when trying to use it (or we should check it fails)
}
