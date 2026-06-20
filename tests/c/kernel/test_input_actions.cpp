#include <gtest/gtest.h>
#include <kernel_engine/framework/input_actions.h>
#include <kernel_engine/framework/input_actions_create.h>
#include <kernel_engine/input/key.h>
#include <kernel_engine/input/snapshot.h>

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <string>

namespace fs = std::filesystem;

// Helpers ────────────────────────────────────────────────────────────────────

static fs::path WriteTempInputFile(const std::string &contents, const char *suffix)
{
    auto path = fs::temp_directory_path() / (std::string("ke_input_actions_test_") +
                                              std::to_string(::rand()) + suffix);
    std::ofstream(path) << contents;
    return path;
}

static void SetKeyDown(ke_input_snapshot &snap, int key)
{
    snap.keys_down[key / 64] |= (1ULL << (key % 64));
}

// ── Fixture ──────────────────────────────────────────────────────────────────

class InputActionsTest : public ::testing::Test
{
protected:
    ke_input_actions_handle actions_h{};
    ke_input_actions *actions   = nullptr;

    void SetUp() override
    {
        actions_h = ke_input_actions_create(NULL);
        ASSERT_NE(actions_h.ref, nullptr);
        actions = actions_h.ref;
    }
    void TearDown() override
    {
        if (actions_h.ref && actions_h.destroy) actions_h.destroy(actions_h.ref);
    }
};

// ── Loader smoke ─────────────────────────────────────────────────────────────

TEST_F(InputActionsTest, Load_MissingFile_ReturnsNotFound)
{
    EXPECT_FALSE(actions->load(actions, "C:/this/path/does/not/exist.input", NULL));
}

TEST_F(InputActionsTest, Load_AssignsSequentialIds)
{
    auto path = WriteTempInputFile(R"(
[action.Jump]
type = "Button"
bindings = [ { kind = "key", key = "Space" } ]

[action.Move]
type = "Axis1D"
bindings = [ { kind = "key_pair", negative = "S", positive = "W" } ]
)",
                                    ".input");
    ASSERT_TRUE(actions->load(actions, path.string().c_str(), NULL));
    EXPECT_EQ(actions->get_action_id(actions, "Jump"), 0);
    EXPECT_EQ(actions->get_action_id(actions, "Move"), 1);
    EXPECT_EQ(actions->get_action_id(actions, "Unknown"), -1);
    fs::remove(path);
}

// ── Button binding ──────────────────────────────────────────────────────────

TEST_F(InputActionsTest, ButtonBinding_ReportsPressedAndReleased)
{
    auto path = WriteTempInputFile(R"(
[action.Jump]
type = "Button"
bindings = [ { kind = "key", key = "Space" } ]
)",
                                    ".input");
    ASSERT_TRUE(actions->load(actions, path.string().c_str(), NULL));
    int32_t id = actions->get_action_id(actions, "Jump");

    ke_input_snapshot snap{};
    // First frame: not pressed.
    actions->evaluate(actions, &snap, nullptr, nullptr, nullptr);
    EXPECT_FALSE(actions->is_action_down(actions, id));
    EXPECT_FALSE(actions->was_action_pressed(actions, id));

    // Press Space.
    SetKeyDown(snap, KE_KEY_SPACE);
    actions->evaluate(actions, &snap, nullptr, nullptr, nullptr);
    EXPECT_TRUE(actions->is_action_down(actions, id));
    EXPECT_TRUE(actions->was_action_pressed(actions, id));

    // Hold Space → no longer "just pressed".
    actions->evaluate(actions, &snap, nullptr, nullptr, nullptr);
    EXPECT_TRUE(actions->is_action_down(actions, id));
    EXPECT_FALSE(actions->was_action_pressed(actions, id));

    // Release Space.
    snap = {};
    actions->evaluate(actions, &snap, nullptr, nullptr, nullptr);
    EXPECT_FALSE(actions->is_action_down(actions, id));
    EXPECT_TRUE(actions->was_action_released(actions, id));

    fs::remove(path);
}

// ── KeyPair binding (Axis1D) ────────────────────────────────────────────────

TEST_F(InputActionsTest, KeyPair_ReportsAxisValue)
{
    auto path = WriteTempInputFile(R"(
[action.Move]
type = "Axis1D"
bindings = [ { kind = "key_pair", negative = "S", positive = "W" } ]
)",
                                    ".input");
    ASSERT_TRUE(actions->load(actions, path.string().c_str(), NULL));
    int32_t id = actions->get_action_id(actions, "Move");

    ke_input_snapshot snap{};
    // W only → +1
    SetKeyDown(snap, KE_KEY_W);
    actions->evaluate(actions, &snap, nullptr, nullptr, nullptr);
    EXPECT_FLOAT_EQ(actions->get_axis1d(actions, id), 1.0f);

    // S only → -1
    snap = {};
    SetKeyDown(snap, KE_KEY_S);
    actions->evaluate(actions, &snap, nullptr, nullptr, nullptr);
    EXPECT_FLOAT_EQ(actions->get_axis1d(actions, id), -1.0f);

    // Both → 0
    snap = {};
    SetKeyDown(snap, KE_KEY_W);
    SetKeyDown(snap, KE_KEY_S);
    actions->evaluate(actions, &snap, nullptr, nullptr, nullptr);
    EXPECT_FLOAT_EQ(actions->get_axis1d(actions, id), 0.0f);

    fs::remove(path);
}

// ── KeyQuad binding (Axis2D) ────────────────────────────────────────────────

TEST_F(InputActionsTest, KeyQuad_ReportsAxis2D)
{
    auto path = WriteTempInputFile(R"(
[action.Move]
type = "Axis2D"
bindings = [ { kind = "key_quad", up = "W", down = "S", left = "A", right = "D" } ]
)",
                                    ".input");
    ASSERT_TRUE(actions->load(actions, path.string().c_str(), NULL));
    int32_t id = actions->get_action_id(actions, "Move");

    ke_input_snapshot snap{};
    SetKeyDown(snap, KE_KEY_W); // up
    SetKeyDown(snap, KE_KEY_D); // right
    actions->evaluate(actions, &snap, nullptr, nullptr, nullptr);
    float x = 0, y = 0;
    actions->get_axis2d(actions, id, &x, &y);
    EXPECT_FLOAT_EQ(x, 1.0f);   // right - left
    EXPECT_FLOAT_EQ(y, 1.0f);   // up - down

    fs::remove(path);
}

// ── Mouse binding ───────────────────────────────────────────────────────────

TEST_F(InputActionsTest, MouseBinding_DrivesButtonAction)
{
    auto path = WriteTempInputFile(R"(
[action.Fire]
type = "Button"
bindings = [ { kind = "mouse", button = "Left" } ]
)",
                                    ".input");
    ASSERT_TRUE(actions->load(actions, path.string().c_str(), NULL));
    int32_t id = actions->get_action_id(actions, "Fire");

    ke_input_snapshot snap{};
    snap.mouse_buttons_down = (1u << KE_MOUSE_BUTTON_LEFT);
    actions->evaluate(actions, &snap, nullptr, nullptr, nullptr);
    EXPECT_TRUE(actions->is_action_down(actions, id));

    fs::remove(path);
}

// ── on_event callback ──────────────────────────────────────────────────────

TEST_F(InputActionsTest, Evaluate_FiresStartedAndCanceledEvents)
{
    auto path = WriteTempInputFile(R"(
[action.Jump]
type = "Button"
bindings = [ { kind = "key", key = "Space" } ]
)",
                                    ".input");
    ASSERT_TRUE(actions->load(actions, path.string().c_str(), NULL));
    int32_t id = actions->get_action_id(actions, "Jump");

    struct Counter { int started = 0, canceled = 0, performed = 0; } c;
    auto cb = +[](void *ctx, ke_input_action_event ev) {
        auto *cnt = static_cast<Counter *>(ctx);
        if (ev.phase == KE_ACTION_PHASE_STARTED)   cnt->started++;
        if (ev.phase == KE_ACTION_PHASE_CANCELED)  cnt->canceled++;
        if (ev.phase == KE_ACTION_PHASE_PERFORMED) cnt->performed++;
    };

    ke_input_snapshot snap{};
    actions->evaluate(actions, &snap, cb, &c, nullptr); // no-op
    EXPECT_EQ(c.started, 0);

    SetKeyDown(snap, KE_KEY_SPACE);
    actions->evaluate(actions, &snap, cb, &c, nullptr); // start
    EXPECT_EQ(c.started, 1);
    // Button never fires Performed (Started conveys the press; matches C# dispatcher).
    EXPECT_EQ(c.performed, 0);

    actions->evaluate(actions, &snap, cb, &c, nullptr); // still down → no new start, no performed
    EXPECT_EQ(c.started, 1);
    EXPECT_EQ(c.performed, 0);

    snap = {};
    actions->evaluate(actions, &snap, cb, &c, nullptr); // cancel
    EXPECT_EQ(c.canceled, 1);

    (void)id;
    fs::remove(path);
}

// ── Programmatic registration ────────────────────────────────────────────────

TEST_F(InputActionsTest, AddAction_AssignsSequentialIds)
{
    EXPECT_EQ(actions->add_action(actions, "Jump",   KE_ACTION_TYPE_BUTTON), 0);
    EXPECT_EQ(actions->add_action(actions, "Move",   KE_ACTION_TYPE_AXIS2D), 1);
    EXPECT_EQ(actions->add_action(actions, "Look",   KE_ACTION_TYPE_AXIS2D), 2);
    EXPECT_EQ(actions->get_action_id(actions, "Jump"), 0);
    EXPECT_EQ(actions->get_action_id(actions, "Move"), 1);
    EXPECT_EQ(actions->get_action_id(actions, "Look"), 2);
}

TEST_F(InputActionsTest, AddAction_RejectsDuplicateAndInvalidNames)
{
    EXPECT_EQ(actions->add_action(actions, "Jump", KE_ACTION_TYPE_BUTTON), 0);
    EXPECT_EQ(actions->add_action(actions, "Jump", KE_ACTION_TYPE_BUTTON), -1);
    EXPECT_EQ(actions->add_action(actions, "",     KE_ACTION_TYPE_BUTTON), -1);
    EXPECT_EQ(actions->add_action(actions, nullptr,KE_ACTION_TYPE_BUTTON), -1);
}

TEST_F(InputActionsTest, BindKey_DrivesButtonActive)
{
    int32_t jump = actions->add_action(actions, "Jump", KE_ACTION_TYPE_BUTTON);
    ASSERT_TRUE(actions->bind_key(actions, jump, KE_KEY_SPACE, NULL));

    ke_input_snapshot snap{};
    SetKeyDown(snap, KE_KEY_SPACE);
    ASSERT_TRUE(actions->evaluate(actions, &snap, nullptr, nullptr, nullptr));
    EXPECT_TRUE(actions->is_action_down(actions, jump));
    EXPECT_TRUE(actions->was_action_pressed(actions, jump));
}

TEST_F(InputActionsTest, BindKeyPair_ProducesAxis1D)
{
    int32_t strafe = actions->add_action(actions, "Strafe", KE_ACTION_TYPE_AXIS1D);
    ASSERT_TRUE(actions->bind_key_pair(actions, strafe, KE_KEY_A, KE_KEY_D, NULL));

    ke_input_snapshot snap{};
    SetKeyDown(snap, KE_KEY_D);
    ASSERT_TRUE(actions->evaluate(actions, &snap, nullptr, nullptr, nullptr));
    EXPECT_FLOAT_EQ(actions->get_axis1d(actions, strafe), 1.0f);

    snap = {};
    SetKeyDown(snap, KE_KEY_A);
    ASSERT_TRUE(actions->evaluate(actions, &snap, nullptr, nullptr, nullptr));
    EXPECT_FLOAT_EQ(actions->get_axis1d(actions, strafe), -1.0f);
}

TEST_F(InputActionsTest, BindKeyQuad_ProducesAxis2D)
{
    int32_t move = actions->add_action(actions, "Move", KE_ACTION_TYPE_AXIS2D);
    ASSERT_TRUE(actions->bind_key_quad(actions, move,
                                      KE_KEY_W, KE_KEY_S, KE_KEY_A, KE_KEY_D, NULL));

    ke_input_snapshot snap{};
    SetKeyDown(snap, KE_KEY_W);
    SetKeyDown(snap, KE_KEY_D);
    ASSERT_TRUE(actions->evaluate(actions, &snap, nullptr, nullptr, nullptr));
    float x = 0, y = 0;
    actions->get_axis2d(actions, move, &x, &y);
    EXPECT_FLOAT_EQ(x,  1.0f);
    EXPECT_FLOAT_EQ(y,  1.0f);
}

TEST_F(InputActionsTest, BindMouseButton_DrivesButtonActive)
{
    int32_t fire = actions->add_action(actions, "Fire", KE_ACTION_TYPE_BUTTON);
    ASSERT_TRUE(actions->bind_mouse_button(actions, fire, KE_MOUSE_BUTTON_LEFT, NULL));

    ke_input_snapshot snap{};
    snap.mouse_buttons_down = 1u << KE_MOUSE_BUTTON_LEFT;
    ASSERT_TRUE(actions->evaluate(actions, &snap, nullptr, nullptr, nullptr));
    EXPECT_TRUE(actions->is_action_down(actions, fire));
}

TEST_F(InputActionsTest, BindOnUnknownActionId_ReturnsNotFound)
{
    EXPECT_FALSE(actions->bind_key(actions, 99, KE_KEY_SPACE, NULL));
    EXPECT_FALSE(actions->bind_key_pair(actions, 99, KE_KEY_A, KE_KEY_D, NULL));
}

TEST_F(InputActionsTest, Create_ReturnsValidHandle)
{
    ke_input_actions_handle h = ke_input_actions_create(NULL);
    EXPECT_NE(h.ref, nullptr);
    if (h.ref && h.destroy) h.destroy(h.ref);
}

TEST_F(InputActionsTest, GetAxis3D_Works)
{
    int32_t id = actions->add_action(actions, "Move", KE_ACTION_TYPE_AXIS3D);
    // No easy way to drive 3D axis via keys/mouse currently in implementation, 
    // but we can check the default value.
    float x = 0, y = 0, z = 0;
    actions->get_axis3d(actions, id, &x, &y, &z);
    EXPECT_FLOAT_EQ(x, 0.0f);
    EXPECT_FLOAT_EQ(y, 0.0f);
    EXPECT_FLOAT_EQ(z, 0.0f);
}

TEST_F(InputActionsTest, Evaluate_ReturnsInvalidArgument_OnNullArgs)
{
    EXPECT_FALSE(actions->evaluate(actions, nullptr, nullptr, nullptr, nullptr));
}

TEST_F(InputActionsTest, WasActionPressed_FalseWhenNotInitialPress)
{
    int32_t id = actions->add_action(actions, "Jump", KE_ACTION_TYPE_BUTTON);
    actions->bind_key(actions, id, KE_KEY_SPACE, nullptr);
    
    ke_input_snapshot snap{};
    SetKeyDown(snap, KE_KEY_SPACE);
    actions->evaluate(actions, &snap, nullptr, nullptr, nullptr);
    EXPECT_TRUE(actions->was_action_pressed(actions, id));
    
    actions->evaluate(actions, &snap, nullptr, nullptr, nullptr); // Second frame with key down
    EXPECT_FALSE(actions->was_action_pressed(actions, id));
}
