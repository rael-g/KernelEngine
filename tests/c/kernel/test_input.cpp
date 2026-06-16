#include <gtest/gtest.h>
#include <kernel_engine/input/input.h>

class InputTest : public ::testing::Test {
protected:
    ke_input* input = nullptr;

    void SetUp() override {
        ke_result res = ke_input_create(nullptr, &input);
        ASSERT_EQ(res, KE_OK);
    }

    void TearDown() override {
        if (input) input->destroy(input);
    }
};

// --- Creation Tests ---

TEST(InputInitTest, Create_NullOutInput_ReturnsInvalidArgument) {
    ASSERT_EQ(ke_input_create(nullptr, nullptr), KE_ERROR_INVALID_ARGUMENT);
}

// --- Destroy Tests ---

TEST(InputDestroyTest, Destroy_NullInput_DoesNotCrash) {
    ke_input* i = nullptr;
    ke_input_create(nullptr, &i);
    auto destroy_fn = i->destroy;
    i->destroy(i);
    destroy_fn(nullptr);
    SUCCEED();
}

TEST_F(InputTest, Destroy_WorksNormally) {
    input->destroy(input);
    input = nullptr;
    SUCCEED();
}

// --- Update and State Tests ---

TEST_F(InputTest, Update_NullSelf_ReturnsInvalidArgument) {
    auto update_fn = input->update;
    ASSERT_EQ(update_fn(nullptr), KE_ERROR_INVALID_ARGUMENT);
}

TEST_F(InputTest, KeyPressed_IsDetected) {
    input->update(input);        // clear previous frame
    input->on_key(input, 65, 1); // 'A' press event arrives
    ASSERT_TRUE(input->is_key_pressed(input, 65));
}

TEST_F(InputTest, Snapshot_KeyIsCaptured) {
    input->on_key(input, 65, 1);
    ke_input_snapshot snapshot;
    input->get_snapshot(input, &snapshot);
    
    int word = 65 / 64;
    uint64_t bit = (1ULL << (65 % 64));
    ASSERT_TRUE(snapshot.keys_pressed[word] & bit);
}

TEST_F(InputTest, MouseMove_CalculatesDelta) {
    input->update(input); // reset to (0,0) with no delta
    input->on_mouse_move(input, 100.0f, 200.0f);
    input->on_mouse_move(input, 150.0f, 180.0f);
    ke_input_snapshot snapshot;
    input->get_snapshot(input, &snapshot);
    // Initial jump to (100,200) + movement to (150,180) = 150 cumulative delta in this frame
    ASSERT_FLOAT_EQ(snapshot.mouse_dx, 150.0f);
    ASSERT_FLOAT_EQ(snapshot.mouse_dy, 180.0f);
}

TEST_F(InputTest, MouseButton_IsDetected) {
    input->update(input);
    input->on_mouse_button(input, 0, 1); // Left Down
    ke_input_snapshot snapshot;
    input->get_snapshot(input, &snapshot);
    ASSERT_TRUE(snapshot.mouse_buttons_pressed & (1u << 0));
    ASSERT_TRUE(snapshot.mouse_buttons_down & (1u << 0));
}

TEST_F(InputTest, MouseScroll_IsDetected) {
    input->on_mouse_scroll(input, 1.5f, -2.5f);
    ke_input_snapshot snapshot;
    input->get_snapshot(input, &snapshot);
    ASSERT_FLOAT_EQ(snapshot.scroll_dx, 1.5f);
    ASSERT_FLOAT_EQ(snapshot.scroll_dy, -2.5f);
}

TEST_F(InputTest, DrainEvents_Works) {
    input->on_key(input, 65, 1); // Down
    input->on_key(input, 65, 0); // Up
    
    ke_input_event events[10];
    uint32_t count = input->drain_events(input, events, 10);
    
    ASSERT_EQ(count, 2);
    ASSERT_EQ(events[0].kind, KE_INPUT_EVENT_KEY_DOWN);
    ASSERT_EQ(events[1].kind, KE_INPUT_EVENT_KEY_UP);
}

TEST_F(InputTest, DrainEvents_CapsAtCapacity) {
    input->on_key(input, 65, 1);
    input->on_key(input, 66, 1);
    
    ke_input_event events[1];
    uint32_t count = input->drain_events(input, events, 1);
    
    ASSERT_EQ(count, 1);
}

TEST_F(InputTest, EventQueue_Overflow_IsHandled) {
    // Capacity is 512
    for(int i=0; i<600; ++i) {
        input->on_mouse_scroll(input, 1, 1);
    }
    
    ke_input_event events[10];
    uint32_t count = input->drain_events(input, events, 10);
    // Should have drained the first 10 and cleared the overflow flag
    ASSERT_EQ(count, 10);
}

TEST_F(InputTest, IsKeyDown_WorksAcrossUpdate) {
    input->on_key(input, 10, 1);
    ASSERT_TRUE(input->is_key_down(input, 10));
    
    input->update(input);
    ASSERT_TRUE(input->is_key_down(input, 10)); // Still down
    ASSERT_FALSE(input->is_key_pressed(input, 10)); // But not pressed this frame
    
    input->on_key(input, 10, 0);
    ASSERT_FALSE(input->is_key_down(input, 10));
    ASSERT_TRUE(input->is_key_released(input, 10));
}

TEST_F(InputTest, OnKey_InvalidCode_IsSafe) {
    input->on_key(input, -1, 1);
    input->on_key(input, 999, 1);
    SUCCEED();
}

TEST_F(InputTest, IsKeyDown_NullSelf_ReturnsFalse) {
    auto is_down_fn = input->is_key_down;
    ASSERT_FALSE(is_down_fn(nullptr, 65));
}

TEST_F(InputTest, IsKeyPressed_NullSelf_ReturnsFalse) {
    auto is_pressed_fn = input->is_key_pressed;
    ASSERT_FALSE(is_pressed_fn(nullptr, 65));
}

TEST_F(InputTest, IsKeyReleased_NullSelf_ReturnsFalse) {
    auto is_released_fn = input->is_key_released;
    ASSERT_FALSE(is_released_fn(nullptr, 65));
}

TEST_F(InputTest, GetSnapshot_NullArgs_DoesNotCrash) {
    input->get_snapshot(nullptr, nullptr);
    ke_input_snapshot snapshot;
    input->get_snapshot(nullptr, &snapshot);
    input->get_snapshot(input, nullptr);
    SUCCEED();
}

TEST_F(InputTest, DrainEvents_NullArgs_ReturnsZero) {
    ke_input_event events[1];
    ASSERT_EQ(input->drain_events(nullptr, events, 1), 0u);
    ASSERT_EQ(input->drain_events(input, nullptr, 1), 0u);
}

TEST_F(InputTest, OnMouseMove_NullSelf_IsSafe) {
    auto on_move_fn = input->on_mouse_move;
    on_move_fn(nullptr, 1, 1);
    SUCCEED();
}

