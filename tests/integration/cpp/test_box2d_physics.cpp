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

        physics_h = ke_physics_2d_box2d_create(&params, nullptr);
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
    id = physics->create_body(physics, KE_BODY_TYPE_DYNAMIC, 0, 0, nullptr);
    ASSERT_NE(id, 0u);
}

TEST_F(Box2DPhysicsTest, AddBoxFixture_Works) {
    uint32_t id = 0;
    id = physics->create_body(physics, KE_BODY_TYPE_DYNAMIC, 0, 0, nullptr);
    bool res = physics->add_box_fixture(physics, id, 1.0f, 1.0f, 1.0f, 0.3f, 0.1f, nullptr);
    ASSERT_TRUE(res);
}

TEST_F(Box2DPhysicsTest, AddCircleFixture_Works) {
    uint32_t id = 0;
    id = physics->create_body(physics, KE_BODY_TYPE_DYNAMIC, 0, 0, nullptr);
    bool res = physics->add_circle_fixture(physics, id, 1.0f, 1.0f, 0.3f, 0.1f, nullptr);
    ASSERT_TRUE(res);
}

TEST_F(Box2DPhysicsTest, GetBodyState_Works) {
    uint32_t id = 0;
    id = physics->create_body(physics, KE_BODY_TYPE_DYNAMIC, 10.0f, 20.0f, nullptr);
    
    ke_body_state_2d state{};
    physics->get_body_state(physics, id, &state);
    
    ASSERT_FLOAT_EQ(state.x, 10.0f);
    ASSERT_FLOAT_EQ(state.y, 20.0f);
}

TEST_F(Box2DPhysicsTest, SetBodyPosition_Works) {
    uint32_t id = 0;
    id = physics->create_body(physics, KE_BODY_TYPE_DYNAMIC, 0, 0, nullptr);
    physics->set_body_position(physics, id, 5.0f, 5.0f, 0.78f);
    
    ke_body_state_2d state{};
    physics->get_body_state(physics, id, &state);
    ASSERT_FLOAT_EQ(state.x, 5.0f);
    ASSERT_FLOAT_EQ(state.y, 5.0f);
    ASSERT_FLOAT_EQ(state.angle, 0.78f);
}

TEST_F(Box2DPhysicsTest, SetBodyVelocity_Works) {
    uint32_t id = 0;
    id = physics->create_body(physics, KE_BODY_TYPE_DYNAMIC, 0, 0, nullptr);
    physics->set_body_velocity(physics, id, 1.0f, 2.0f);
    
    ke_body_state_2d state{};
    physics->get_body_state(physics, id, &state);
    ASSERT_FLOAT_EQ(state.velocity_x, 1.0f);
    ASSERT_FLOAT_EQ(state.velocity_y, 2.0f);
}

TEST_F(Box2DPhysicsTest, ApplyImpulse_Works) {
    uint32_t id = 0;
    id = physics->create_body(physics, KE_BODY_TYPE_DYNAMIC, 0, 0, nullptr);
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
    id = physics->create_body(physics, KE_BODY_TYPE_DYNAMIC, 0, 0, nullptr);
    physics->destroy_body(physics, id);
    // Should not crash when trying to use it (or we should check it fails)
}

// A box bouncing head-on is where Box2D v3 differs from v2: its two-point
// manifold resolves the contact points sequentially, so an otherwise symmetric
// hit leaves a net torque. Locking rotation is the engine-level answer, and
// this is the Pong ball's exact setup — frictionless box, full restitution.
TEST_F(Box2DPhysicsTest, FixedRotation_KeepsABouncingBoxFromSpinning) {
    physics->set_gravity(physics, 0.0f, 0.0f);

    ke_body_2d wall = physics->create_body(physics, KE_BODY_TYPE_STATIC, 2.0f, 0.0f, nullptr);
    ASSERT_NE(wall, KE_BODY_2D_INVALID);
    ASSERT_TRUE(physics->add_box_fixture(physics, wall, 0.25f, 4.0f, 1.0f, 0.0f, 1.0f, nullptr));

    ke_body_2d ball = physics->create_body(physics, KE_BODY_TYPE_DYNAMIC, 0.0f, 0.0f, nullptr);
    ASSERT_NE(ball, KE_BODY_2D_INVALID);
    ASSERT_TRUE(physics->add_box_fixture(physics, ball, 0.18f, 0.18f, 1.0f, 0.0f, 1.0f, nullptr));
    physics->set_body_fixed_rotation(physics, ball, true);
    physics->set_body_velocity(physics, ball, 6.0f, 0.0f);

    ke_body_state_2d st{};
    for (int i = 0; i < 120; ++i) {
        physics->step(physics, 1.0f / 60.0f);
        physics->get_body_state(physics, ball, &st);
        ASSERT_NEAR(st.angular_velocity, 0.0f, 1e-5f)
            << "a rotation-locked body must never pick up spin (step " << i << ")";
    }
    EXPECT_NEAR(st.angle, 0.0f, 1e-5f);
    // The lock must not have cost the bounce: the box has to come back.
    EXPECT_LT(st.velocity_x, 0.0f);
}

// Companion to the box case: a frictionless circle has no way to pick up spin
// from a head-on bounce, so this isolates a contact-manifold asymmetry (box
// only) from a body mass/inertia problem (both shapes).
TEST_F(Box2DPhysicsTest, FrictionlessCircle_HeadOnBounce_DoesNotSpin) {
    physics->set_gravity(physics, 0.0f, 0.0f);

    ke_body_2d wall = physics->create_body(physics, KE_BODY_TYPE_STATIC, 2.0f, 0.0f, nullptr);
    ASSERT_TRUE(physics->add_box_fixture(physics, wall, 0.25f, 4.0f, 1.0f, 0.0f, 1.0f, nullptr));

    ke_body_2d ball = physics->create_body(physics, KE_BODY_TYPE_DYNAMIC, 0.0f, 0.0f, nullptr);
    ASSERT_TRUE(physics->add_circle_fixture(physics, ball, 0.18f, 1.0f, 0.0f, 1.0f, nullptr));
    physics->set_body_velocity(physics, ball, 6.0f, 0.0f);

    ke_body_state_2d st{};
    for (int i = 0; i < 120; ++i) {
        physics->step(physics, 1.0f / 60.0f);
        physics->get_body_state(physics, ball, &st);
        ASSERT_NEAR(st.angular_velocity, 0.0f, 1e-3f) << "step " << i;
    }
}
