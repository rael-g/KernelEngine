// Default implementation of ke_input_actions backed by tomlplusplus for
// parsing `.input` files. Schema (TOML 1.0):
//
//     [action.NAME]
//     type = "Button" | "Axis1D" | "Axis2D" | "Axis3D"
//     bindings = [
//         { kind = "key",        key      = "Space" },
//         { kind = "key_pair",   negative = "S",      positive = "W" },
//         { kind = "key_quad",   up = "W", down = "S", left = "A", right = "D" },
//         { kind = "mouse",      button   = "Left" },
//     ]
//
// Action ids are assigned in order of appearance (first action = 0, second = 1, …).
// Callers cache them after load() via get_action_id() and reuse across frames.

#include <kernel_engine/framework/input_actions.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/input/key.h>

#include <toml++/toml.hpp>

#include <cstring>
#include <new>
#include <string>
#include <unordered_map>
#include <vector>

namespace
{

// ── Name → enum lookup tables ────────────────────────────────────────────────

const std::unordered_map<std::string_view, ke_key> &key_table()
{
    static const std::unordered_map<std::string_view, ke_key> table = {
        {"Unknown",        KE_KEY_UNKNOWN},
        {"Space",          KE_KEY_SPACE},
        {"Apostrophe",     KE_KEY_APOSTROPHE},
        {"Comma",          KE_KEY_COMMA},
        {"Minus",          KE_KEY_MINUS},
        {"Period",         KE_KEY_PERIOD},
        {"Slash",          KE_KEY_SLASH},
        {"Number0",        KE_KEY_NUMBER_0},
        {"Number1",        KE_KEY_NUMBER_1},
        {"Number2",        KE_KEY_NUMBER_2},
        {"Number3",        KE_KEY_NUMBER_3},
        {"Number4",        KE_KEY_NUMBER_4},
        {"Number5",        KE_KEY_NUMBER_5},
        {"Number6",        KE_KEY_NUMBER_6},
        {"Number7",        KE_KEY_NUMBER_7},
        {"Number8",        KE_KEY_NUMBER_8},
        {"Number9",        KE_KEY_NUMBER_9},
        {"Semicolon",      KE_KEY_SEMICOLON},
        {"Equal",          KE_KEY_EQUAL},
        {"A", KE_KEY_A}, {"B", KE_KEY_B}, {"C", KE_KEY_C}, {"D", KE_KEY_D},
        {"E", KE_KEY_E}, {"F", KE_KEY_F}, {"G", KE_KEY_G}, {"H", KE_KEY_H},
        {"I", KE_KEY_I}, {"J", KE_KEY_J}, {"K", KE_KEY_K}, {"L", KE_KEY_L},
        {"M", KE_KEY_M}, {"N", KE_KEY_N}, {"O", KE_KEY_O}, {"P", KE_KEY_P},
        {"Q", KE_KEY_Q}, {"R", KE_KEY_R}, {"S", KE_KEY_S}, {"T", KE_KEY_T},
        {"U", KE_KEY_U}, {"V", KE_KEY_V}, {"W", KE_KEY_W}, {"X", KE_KEY_X},
        {"Y", KE_KEY_Y}, {"Z", KE_KEY_Z},
        {"LeftBracket",    KE_KEY_LEFT_BRACKET},
        {"BackSlash",      KE_KEY_BACKSLASH},
        {"RightBracket",   KE_KEY_RIGHT_BRACKET},
        {"GraveAccent",    KE_KEY_GRAVE_ACCENT},
        {"World1",         KE_KEY_WORLD_1},
        {"World2",         KE_KEY_WORLD_2},
        {"Escape",         KE_KEY_ESCAPE},
        {"Enter",          KE_KEY_ENTER},
        {"Tab",            KE_KEY_TAB},
        {"Backspace",      KE_KEY_BACKSPACE},
        {"Insert",         KE_KEY_INSERT},
        {"Delete",         KE_KEY_DELETE},
        {"Right",          KE_KEY_RIGHT},
        {"Left",           KE_KEY_LEFT},
        {"Down",           KE_KEY_DOWN},
        {"Up",             KE_KEY_UP},
        {"PageUp",         KE_KEY_PAGE_UP},
        {"PageDown",       KE_KEY_PAGE_DOWN},
        {"Home",           KE_KEY_HOME},
        {"End",            KE_KEY_END},
        {"CapsLock",       KE_KEY_CAPS_LOCK},
        {"ScrollLock",     KE_KEY_SCROLL_LOCK},
        {"NumLock",        KE_KEY_NUM_LOCK},
        {"PrintScreen",    KE_KEY_PRINT_SCREEN},
        {"Pause",          KE_KEY_PAUSE},
        {"F1", KE_KEY_F1}, {"F2", KE_KEY_F2}, {"F3", KE_KEY_F3}, {"F4", KE_KEY_F4},
        {"F5", KE_KEY_F5}, {"F6", KE_KEY_F6}, {"F7", KE_KEY_F7}, {"F8", KE_KEY_F8},
        {"F9", KE_KEY_F9}, {"F10", KE_KEY_F10}, {"F11", KE_KEY_F11}, {"F12", KE_KEY_F12},
        {"F13", KE_KEY_F13}, {"F14", KE_KEY_F14}, {"F15", KE_KEY_F15}, {"F16", KE_KEY_F16},
        {"F17", KE_KEY_F17}, {"F18", KE_KEY_F18}, {"F19", KE_KEY_F19}, {"F20", KE_KEY_F20},
        {"F21", KE_KEY_F21}, {"F22", KE_KEY_F22}, {"F23", KE_KEY_F23}, {"F24", KE_KEY_F24},
        {"F25", KE_KEY_F25},
        {"Keypad0", KE_KEY_KEYPAD_0}, {"Keypad1", KE_KEY_KEYPAD_1}, {"Keypad2", KE_KEY_KEYPAD_2},
        {"Keypad3", KE_KEY_KEYPAD_3}, {"Keypad4", KE_KEY_KEYPAD_4}, {"Keypad5", KE_KEY_KEYPAD_5},
        {"Keypad6", KE_KEY_KEYPAD_6}, {"Keypad7", KE_KEY_KEYPAD_7}, {"Keypad8", KE_KEY_KEYPAD_8},
        {"Keypad9", KE_KEY_KEYPAD_9},
        {"KeypadDecimal",  KE_KEY_KEYPAD_DECIMAL},
        {"KeypadDivide",   KE_KEY_KEYPAD_DIVIDE},
        {"KeypadMultiply", KE_KEY_KEYPAD_MULTIPLY},
        {"KeypadSubtract", KE_KEY_KEYPAD_SUBTRACT},
        {"KeypadAdd",      KE_KEY_KEYPAD_ADD},
        {"KeypadEnter",    KE_KEY_KEYPAD_ENTER},
        {"KeypadEqual",    KE_KEY_KEYPAD_EQUAL},
        {"ShiftLeft",      KE_KEY_SHIFT_LEFT},
        {"ControlLeft",    KE_KEY_CONTROL_LEFT},
        {"AltLeft",        KE_KEY_ALT_LEFT},
        {"SuperLeft",      KE_KEY_SUPER_LEFT},
        {"ShiftRight",     KE_KEY_SHIFT_RIGHT},
        {"ControlRight",   KE_KEY_CONTROL_RIGHT},
        {"AltRight",       KE_KEY_ALT_RIGHT},
        {"SuperRight",     KE_KEY_SUPER_RIGHT},
        {"Menu",           KE_KEY_MENU},
    };
    return table;
}

const std::unordered_map<std::string_view, ke_mouse_button> &mouse_table()
{
    static const std::unordered_map<std::string_view, ke_mouse_button> table = {
        {"Left",   KE_MOUSE_BUTTON_LEFT},
        {"Right",  KE_MOUSE_BUTTON_RIGHT},
        {"Middle", KE_MOUSE_BUTTON_MIDDLE},
    };
    return table;
}

ke_key lookup_key(std::string_view name)
{
    const auto &t = key_table();
    auto it = t.find(name);
    return it == t.end() ? KE_KEY_UNKNOWN : it->second;
}

int lookup_mouse_button(std::string_view name)
{
    const auto &t = mouse_table();
    auto it = t.find(name);
    return it == t.end() ? -1 : static_cast<int>(it->second);
}

ke_action_type parse_action_type(std::string_view s)
{
    if (s == "Button") return KE_ACTION_TYPE_BUTTON;
    if (s == "Axis1D") return KE_ACTION_TYPE_AXIS1D;
    if (s == "Axis2D") return KE_ACTION_TYPE_AXIS2D;
    if (s == "Axis3D") return KE_ACTION_TYPE_AXIS3D;
    return KE_ACTION_TYPE_BUTTON;
}

// ── Internal model ──────────────────────────────────────────────────────────

enum class BindingKind { Key, KeyPair, KeyQuad, MouseButton };

struct Binding
{
    BindingKind kind = BindingKind::Key;
    int         k0 = -1, k1 = -1, k2 = -1, k3 = -1; // key codes (or mouse button id in k0 for MouseButton)
};

struct Action
{
    std::string           name;
    ke_action_type        type = KE_ACTION_TYPE_BUTTON;
    std::vector<Binding>  bindings;

    // Sampled state for the current frame.
    float curr_x = 0, curr_y = 0, curr_z = 0;
    bool  curr_active = false;
    bool  prev_active = false;
};

struct InputActionsImpl
{
    ke_input_actions             api{};
    ke_allocator                *allocator = nullptr;
    std::vector<Action>          actions;
    std::unordered_map<std::string, int32_t> name_to_id;
};

// ── Snapshot helpers ─────────────────────────────────────────────────────────

bool is_key_down(const ke_input_snapshot *snap, int key)
{
    if (key < 0 || key >= 512) return false;
    return (snap->keys_down[key / 64] >> (key % 64)) & 1ULL;
}

bool is_mouse_down(const ke_input_snapshot *snap, int button)
{
    if (button < 0) return false;
    return (snap->mouse_buttons_down >> button) & 1u;
}

// Returns the binding's combined value into out_x/y/z. Returns true if the
// binding is currently active (>= one component is non-zero), false otherwise.
bool sample_binding(const Binding &b, const ke_input_snapshot *snap,
                    float &out_x, float &out_y, float &out_z)
{
    out_x = out_y = out_z = 0.0f;
    switch (b.kind) {
    case BindingKind::Key:
        out_x = is_key_down(snap, b.k0) ? 1.0f : 0.0f;
        break;
    case BindingKind::MouseButton:
        out_x = is_mouse_down(snap, b.k0) ? 1.0f : 0.0f;
        break;
    case BindingKind::KeyPair: {
        // k0 = negative, k1 = positive
        float pos = is_key_down(snap, b.k1) ? 1.0f : 0.0f;
        float neg = is_key_down(snap, b.k0) ? 1.0f : 0.0f;
        out_x = pos - neg;
        break;
    }
    case BindingKind::KeyQuad: {
        // k0=up, k1=down, k2=left, k3=right
        float up    = is_key_down(snap, b.k0) ? 1.0f : 0.0f;
        float down  = is_key_down(snap, b.k1) ? 1.0f : 0.0f;
        float left  = is_key_down(snap, b.k2) ? 1.0f : 0.0f;
        float right = is_key_down(snap, b.k3) ? 1.0f : 0.0f;
        out_x = right - left;
        out_y = up - down;
        break;
    }
    }
    return out_x != 0.0f || out_y != 0.0f || out_z != 0.0f;
}

// ── vtable: load ────────────────────────────────────────────────────────────

ke_result impl_load(ke_input_actions *self, const char *path)
{
    if (!self || !self->handle || !path) return KE_ERROR_INVALID_ARGUMENT;
    auto *impl = static_cast<InputActionsImpl *>(self->handle);
    impl->actions.clear();
    impl->name_to_id.clear();

    toml::table tbl;
    try {
        tbl = toml::parse_file(path);
    } catch (const toml::parse_error &) {
        return KE_ERROR_NOT_FOUND;
    }

    auto action_section = tbl["action"];
    if (!action_section.is_table()) return KE_OK; // file present but no actions defined

    int32_t next_id = 0;
    for (auto &&[key, value] : *action_section.as_table()) {
        const std::string action_name(key.str());
        const auto *action_tbl = value.as_table();
        if (!action_tbl) continue;

        Action act;
        act.name = action_name;
        if (auto type_node = (*action_tbl)["type"].value<std::string_view>())
            act.type = parse_action_type(*type_node);

        if (const auto *bindings_node = (*action_tbl)["bindings"].as_array()) {
            for (const auto &binding_node : *bindings_node) {
                const auto *binding_tbl = binding_node.as_table();
                if (!binding_tbl) continue;
                auto kind = (*binding_tbl)["kind"].value<std::string_view>();
                if (!kind) continue;

                Binding b;
                if (*kind == "key") {
                    if (auto k = (*binding_tbl)["key"].value<std::string_view>()) {
                        b.kind = BindingKind::Key;
                        b.k0 = lookup_key(*k);
                    } else continue;
                } else if (*kind == "key_pair") {
                    auto n = (*binding_tbl)["negative"].value<std::string_view>();
                    auto p = (*binding_tbl)["positive"].value<std::string_view>();
                    if (!n || !p) continue;
                    b.kind = BindingKind::KeyPair;
                    b.k0 = lookup_key(*n);
                    b.k1 = lookup_key(*p);
                } else if (*kind == "key_quad") {
                    auto up    = (*binding_tbl)["up"].value<std::string_view>();
                    auto down  = (*binding_tbl)["down"].value<std::string_view>();
                    auto left  = (*binding_tbl)["left"].value<std::string_view>();
                    auto right = (*binding_tbl)["right"].value<std::string_view>();
                    if (!up || !down || !left || !right) continue;
                    b.kind = BindingKind::KeyQuad;
                    b.k0 = lookup_key(*up);
                    b.k1 = lookup_key(*down);
                    b.k2 = lookup_key(*left);
                    b.k3 = lookup_key(*right);
                } else if (*kind == "mouse") {
                    if (auto btn = (*binding_tbl)["button"].value<std::string_view>()) {
                        b.kind = BindingKind::MouseButton;
                        b.k0 = lookup_mouse_button(*btn);
                    } else continue;
                } else {
                    continue;
                }
                act.bindings.push_back(b);
            }
        }

        impl->name_to_id[act.name] = next_id;
        impl->actions.push_back(std::move(act));
        next_id++;
    }

    return KE_OK;
}

// ── vtable: get_action_id ────────────────────────────────────────────────────

int32_t impl_get_action_id(ke_input_actions *self, const char *name)
{
    if (!self || !self->handle || !name) return -1;
    auto *impl = static_cast<InputActionsImpl *>(self->handle);
    auto it = impl->name_to_id.find(name);
    return it == impl->name_to_id.end() ? -1 : it->second;
}

// ── vtable: evaluate ─────────────────────────────────────────────────────────

ke_result impl_evaluate(ke_input_actions *self,
                         const ke_input_snapshot *snapshot,
                         ke_input_action_event_func on_event,
                         void *event_ctx)
{
    if (!self || !self->handle || !snapshot) return KE_ERROR_INVALID_ARGUMENT;
    auto *impl = static_cast<InputActionsImpl *>(self->handle);

    for (int32_t id = 0; id < static_cast<int32_t>(impl->actions.size()); id++) {
        Action &a = impl->actions[id];
        a.prev_active = a.curr_active;

        // Combine all bindings — last non-zero wins for axes, OR for buttons.
        float x = 0, y = 0, z = 0;
        bool any_active = false;
        for (const auto &b : a.bindings) {
            float bx, by, bz;
            bool active = sample_binding(b, snapshot, bx, by, bz);
            if (active) {
                any_active = true;
                if (a.type == KE_ACTION_TYPE_BUTTON) {
                    x = 1.0f;
                } else {
                    // For axes, prefer the highest-magnitude contribution.
                    if (std::abs(bx) > std::abs(x)) x = bx;
                    if (std::abs(by) > std::abs(y)) y = by;
                    if (std::abs(bz) > std::abs(z)) z = bz;
                }
            }
        }
        a.curr_x = x;
        a.curr_y = y;
        a.curr_z = z;
        a.curr_active = any_active;

        if (on_event && a.curr_active != a.prev_active) {
            ke_input_action_event ev{};
            ev.action_id = id;
            ev.type      = a.type;
            ev.phase     = a.curr_active ? KE_ACTION_PHASE_STARTED : KE_ACTION_PHASE_CANCELED;
            ev.x = x; ev.y = y; ev.z = z;
            on_event(event_ctx, ev);
        }
        if (on_event && a.curr_active) {
            ke_input_action_event ev{};
            ev.action_id = id;
            ev.type      = a.type;
            ev.phase     = KE_ACTION_PHASE_PERFORMED;
            ev.x = x; ev.y = y; ev.z = z;
            on_event(event_ctx, ev);
        }
    }
    return KE_OK;
}

// ── vtable: polling ──────────────────────────────────────────────────────────

const Action *get_action(const InputActionsImpl *impl, int32_t id)
{
    if (id < 0 || id >= static_cast<int32_t>(impl->actions.size())) return nullptr;
    return &impl->actions[id];
}

bool impl_is_action_down(ke_input_actions *self, int32_t id)
{
    auto *impl = static_cast<InputActionsImpl *>(self->handle);
    const Action *a = get_action(impl, id);
    return a && a->curr_active;
}

bool impl_was_action_pressed(ke_input_actions *self, int32_t id)
{
    auto *impl = static_cast<InputActionsImpl *>(self->handle);
    const Action *a = get_action(impl, id);
    return a && a->curr_active && !a->prev_active;
}

bool impl_was_action_released(ke_input_actions *self, int32_t id)
{
    auto *impl = static_cast<InputActionsImpl *>(self->handle);
    const Action *a = get_action(impl, id);
    return a && !a->curr_active && a->prev_active;
}

float impl_get_axis1d(ke_input_actions *self, int32_t id)
{
    auto *impl = static_cast<InputActionsImpl *>(self->handle);
    const Action *a = get_action(impl, id);
    return a ? a->curr_x : 0.0f;
}

void impl_get_axis2d(ke_input_actions *self, int32_t id, float *out_x, float *out_y)
{
    auto *impl = static_cast<InputActionsImpl *>(self->handle);
    const Action *a = get_action(impl, id);
    if (out_x) *out_x = a ? a->curr_x : 0.0f;
    if (out_y) *out_y = a ? a->curr_y : 0.0f;
}

void impl_get_axis3d(ke_input_actions *self, int32_t id, float *out_x, float *out_y, float *out_z)
{
    auto *impl = static_cast<InputActionsImpl *>(self->handle);
    const Action *a = get_action(impl, id);
    if (out_x) *out_x = a ? a->curr_x : 0.0f;
    if (out_y) *out_y = a ? a->curr_y : 0.0f;
    if (out_z) *out_z = a ? a->curr_z : 0.0f;
}

void impl_destroy(ke_input_actions *self)
{
    if (!self || !self->handle) return;
    auto *impl = static_cast<InputActionsImpl *>(self->handle);
    ke_allocator *alloc = impl->allocator;
    impl->~InputActionsImpl();
    alloc->free(alloc, impl);
}

} // namespace

// ── Factory ──────────────────────────────────────────────────────────────────

extern "C" ke_result ke_input_actions_create(ke_allocator *alloc, ke_input_actions **out_actions)
{
    if (!alloc || !out_actions) return KE_ERROR_INVALID_ARGUMENT;

    void *mem = alloc->alloc(alloc, sizeof(InputActionsImpl), alignof(InputActionsImpl));
    if (!mem) return KE_ERROR_OUT_OF_MEMORY;
    auto *impl = new (mem) InputActionsImpl();
    impl->allocator = alloc;

    impl->api.handle              = impl;
    impl->api.load                = impl_load;
    impl->api.get_action_id       = impl_get_action_id;
    impl->api.evaluate            = impl_evaluate;
    impl->api.is_action_down      = impl_is_action_down;
    impl->api.was_action_pressed  = impl_was_action_pressed;
    impl->api.was_action_released = impl_was_action_released;
    impl->api.get_axis1d          = impl_get_axis1d;
    impl->api.get_axis2d          = impl_get_axis2d;
    impl->api.get_axis3d          = impl_get_axis3d;
    impl->api.destroy             = impl_destroy;

    *out_actions = &impl->api;
    return KE_OK;
}
