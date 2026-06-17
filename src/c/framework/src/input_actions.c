// ke_input_actions impl — pure C. Parses `.input` TOML files into an internal
// table of actions + bindings, evaluates them against ke_input_snapshot per
// frame, exposes polling + event paths. Schema:
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
// Action ids are assigned in declaration order (first action = 0). Callers
// cache them via get_action_id() after load and reuse across frames.

#include <kernel_engine/framework/input_actions_create.h>
#include <kernel_engine/common/error.h>
#include <kernel_engine/allocator/allocator.h>
#include <kernel_engine/input/key.h>

#include "../third_party/tomlc99/toml.h"

#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// ── Name → enum lookup tables ───────────────────────────────────────────────
//
// Linear-scan arrays. The table is consulted only at .input parse time, never
// in the per-frame evaluate path, so we don't pay for a hash. Order doesn't
// matter — strcmp lookup.

typedef struct key_name_entry { const char *name; int code; } key_name_entry;

static const key_name_entry kKeyTable[] = {
    {"Unknown", KE_KEY_UNKNOWN}, {"Space", KE_KEY_SPACE},
    {"Apostrophe", KE_KEY_APOSTROPHE}, {"Comma", KE_KEY_COMMA},
    {"Minus", KE_KEY_MINUS}, {"Period", KE_KEY_PERIOD}, {"Slash", KE_KEY_SLASH},
    {"Number0", KE_KEY_NUMBER_0}, {"Number1", KE_KEY_NUMBER_1},
    {"Number2", KE_KEY_NUMBER_2}, {"Number3", KE_KEY_NUMBER_3},
    {"Number4", KE_KEY_NUMBER_4}, {"Number5", KE_KEY_NUMBER_5},
    {"Number6", KE_KEY_NUMBER_6}, {"Number7", KE_KEY_NUMBER_7},
    {"Number8", KE_KEY_NUMBER_8}, {"Number9", KE_KEY_NUMBER_9},
    {"Semicolon", KE_KEY_SEMICOLON}, {"Equal", KE_KEY_EQUAL},
    {"A", KE_KEY_A}, {"B", KE_KEY_B}, {"C", KE_KEY_C}, {"D", KE_KEY_D},
    {"E", KE_KEY_E}, {"F", KE_KEY_F}, {"G", KE_KEY_G}, {"H", KE_KEY_H},
    {"I", KE_KEY_I}, {"J", KE_KEY_J}, {"K", KE_KEY_K}, {"L", KE_KEY_L},
    {"M", KE_KEY_M}, {"N", KE_KEY_N}, {"O", KE_KEY_O}, {"P", KE_KEY_P},
    {"Q", KE_KEY_Q}, {"R", KE_KEY_R}, {"S", KE_KEY_S}, {"T", KE_KEY_T},
    {"U", KE_KEY_U}, {"V", KE_KEY_V}, {"W", KE_KEY_W}, {"X", KE_KEY_X},
    {"Y", KE_KEY_Y}, {"Z", KE_KEY_Z},
    {"LeftBracket", KE_KEY_LEFT_BRACKET}, {"BackSlash", KE_KEY_BACKSLASH},
    {"RightBracket", KE_KEY_RIGHT_BRACKET}, {"GraveAccent", KE_KEY_GRAVE_ACCENT},
    {"World1", KE_KEY_WORLD_1}, {"World2", KE_KEY_WORLD_2},
    {"Escape", KE_KEY_ESCAPE}, {"Enter", KE_KEY_ENTER},
    {"Tab", KE_KEY_TAB}, {"Backspace", KE_KEY_BACKSPACE},
    {"Insert", KE_KEY_INSERT}, {"Delete", KE_KEY_DELETE},
    {"Right", KE_KEY_RIGHT}, {"Left", KE_KEY_LEFT},
    {"Down", KE_KEY_DOWN}, {"Up", KE_KEY_UP},
    {"PageUp", KE_KEY_PAGE_UP}, {"PageDown", KE_KEY_PAGE_DOWN},
    {"Home", KE_KEY_HOME}, {"End", KE_KEY_END},
    {"CapsLock", KE_KEY_CAPS_LOCK}, {"ScrollLock", KE_KEY_SCROLL_LOCK},
    {"NumLock", KE_KEY_NUM_LOCK}, {"PrintScreen", KE_KEY_PRINT_SCREEN},
    {"Pause", KE_KEY_PAUSE},
    {"F1", KE_KEY_F1}, {"F2", KE_KEY_F2}, {"F3", KE_KEY_F3}, {"F4", KE_KEY_F4},
    {"F5", KE_KEY_F5}, {"F6", KE_KEY_F6}, {"F7", KE_KEY_F7}, {"F8", KE_KEY_F8},
    {"F9", KE_KEY_F9}, {"F10", KE_KEY_F10}, {"F11", KE_KEY_F11}, {"F12", KE_KEY_F12},
    {"F13", KE_KEY_F13}, {"F14", KE_KEY_F14}, {"F15", KE_KEY_F15}, {"F16", KE_KEY_F16},
    {"F17", KE_KEY_F17}, {"F18", KE_KEY_F18}, {"F19", KE_KEY_F19}, {"F20", KE_KEY_F20},
    {"F21", KE_KEY_F21}, {"F22", KE_KEY_F22}, {"F23", KE_KEY_F23}, {"F24", KE_KEY_F24},
    {"F25", KE_KEY_F25},
    {"Keypad0", KE_KEY_KEYPAD_0}, {"Keypad1", KE_KEY_KEYPAD_1},
    {"Keypad2", KE_KEY_KEYPAD_2}, {"Keypad3", KE_KEY_KEYPAD_3},
    {"Keypad4", KE_KEY_KEYPAD_4}, {"Keypad5", KE_KEY_KEYPAD_5},
    {"Keypad6", KE_KEY_KEYPAD_6}, {"Keypad7", KE_KEY_KEYPAD_7},
    {"Keypad8", KE_KEY_KEYPAD_8}, {"Keypad9", KE_KEY_KEYPAD_9},
    {"KeypadDecimal", KE_KEY_KEYPAD_DECIMAL},
    {"KeypadDivide", KE_KEY_KEYPAD_DIVIDE},
    {"KeypadMultiply", KE_KEY_KEYPAD_MULTIPLY},
    {"KeypadSubtract", KE_KEY_KEYPAD_SUBTRACT},
    {"KeypadAdd", KE_KEY_KEYPAD_ADD},
    {"KeypadEnter", KE_KEY_KEYPAD_ENTER},
    {"KeypadEqual", KE_KEY_KEYPAD_EQUAL},
    {"ShiftLeft", KE_KEY_SHIFT_LEFT}, {"ControlLeft", KE_KEY_CONTROL_LEFT},
    {"AltLeft", KE_KEY_ALT_LEFT},     {"SuperLeft", KE_KEY_SUPER_LEFT},
    {"ShiftRight", KE_KEY_SHIFT_RIGHT}, {"ControlRight", KE_KEY_CONTROL_RIGHT},
    {"AltRight", KE_KEY_ALT_RIGHT},   {"SuperRight", KE_KEY_SUPER_RIGHT},
    {"Menu", KE_KEY_MENU},
};
static const size_t kKeyTableLen = sizeof(kKeyTable) / sizeof(kKeyTable[0]);

typedef struct mouse_name_entry { const char *name; int code; } mouse_name_entry;
static const mouse_name_entry kMouseTable[] = {
    {"Left",   KE_MOUSE_BUTTON_LEFT},
    {"Right",  KE_MOUSE_BUTTON_RIGHT},
    {"Middle", KE_MOUSE_BUTTON_MIDDLE},
};
static const size_t kMouseTableLen = sizeof(kMouseTable) / sizeof(kMouseTable[0]);

static int lookup_key(const char *name) {
    if (!name) return KE_KEY_UNKNOWN;
    for (size_t i = 0; i < kKeyTableLen; ++i) {
        if (strcmp(kKeyTable[i].name, name) == 0) return kKeyTable[i].code;
    }
    return KE_KEY_UNKNOWN;
}

static int lookup_mouse_button(const char *name) {
    if (!name) return -1;
    for (size_t i = 0; i < kMouseTableLen; ++i) {
        if (strcmp(kMouseTable[i].name, name) == 0) return kMouseTable[i].code;
    }
    return -1;
}

static ke_action_type parse_action_type(const char *s) {
    if (!s) return KE_ACTION_TYPE_BUTTON;
    if (strcmp(s, "Button") == 0) return KE_ACTION_TYPE_BUTTON;
    if (strcmp(s, "Axis1D") == 0) return KE_ACTION_TYPE_AXIS1D;
    if (strcmp(s, "Axis2D") == 0) return KE_ACTION_TYPE_AXIS2D;
    if (strcmp(s, "Axis3D") == 0) return KE_ACTION_TYPE_AXIS3D;
    return KE_ACTION_TYPE_BUTTON;
}

// ── Internal model ──────────────────────────────────────────────────────────

typedef enum binding_kind { BK_KEY, BK_KEY_PAIR, BK_KEY_QUAD, BK_MOUSE_BUTTON } binding_kind;

typedef struct binding {
    binding_kind kind;
    int          k0, k1, k2, k3;  // key codes; k0 holds mouse button id for BK_MOUSE_BUTTON
} binding;

#define KE_ACTION_NAME_MAX 64

typedef struct action {
    char            name[KE_ACTION_NAME_MAX];
    ke_action_type  type;
    binding        *bindings;
    uint32_t        binding_count;
    uint32_t        binding_capacity;

    // Sampled state.
    float curr_x, curr_y, curr_z;
    float prev_x, prev_y, prev_z;
    bool  curr_active;
    bool  prev_active;
} action;

typedef struct input_actions_state {
    ke_input_actions  api;
    ke_allocator     *allocator;
    action           *actions;
    uint32_t          action_count;
    uint32_t          action_capacity;
} input_actions_state;

// ── Dynamic-array helpers ───────────────────────────────────────────────────

static bool ensure_action_capacity(input_actions_state *s, uint32_t needed) {
    if (s->action_capacity >= needed) return true;
    uint32_t cap = s->action_capacity ? s->action_capacity : 8;
    while (cap < needed) cap *= 2;
    action *new_buf = (action *)s->allocator->alloc(
        s->allocator, sizeof(action) * cap, 8);
    if (!new_buf) return false;
    if (s->actions) {
        memcpy(new_buf, s->actions, sizeof(action) * s->action_count);
        s->allocator->free(s->allocator, s->actions);
    }
    s->actions = new_buf;
    s->action_capacity = cap;
    return true;
}

static bool ensure_binding_capacity(input_actions_state *s, action *a, uint32_t needed) {
    if (a->binding_capacity >= needed) return true;
    uint32_t cap = a->binding_capacity ? a->binding_capacity : 4;
    while (cap < needed) cap *= 2;
    binding *new_buf = (binding *)s->allocator->alloc(
        s->allocator, sizeof(binding) * cap, 8);
    if (!new_buf) return false;
    if (a->bindings) {
        memcpy(new_buf, a->bindings, sizeof(binding) * a->binding_count);
        s->allocator->free(s->allocator, a->bindings);
    }
    a->bindings = new_buf;
    a->binding_capacity = cap;
    return true;
}

static void clear_actions(input_actions_state *s) {
    for (uint32_t i = 0; i < s->action_count; ++i) {
        action *a = &s->actions[i];
        if (a->bindings) {
            s->allocator->free(s->allocator, a->bindings);
            a->bindings = NULL;
        }
        a->binding_count = a->binding_capacity = 0;
    }
    s->action_count = 0;
}

static int32_t find_action_by_name(const input_actions_state *s, const char *name) {
    for (uint32_t i = 0; i < s->action_count; ++i) {
        if (strcmp(s->actions[i].name, name) == 0) return (int32_t)i;
    }
    return -1;
}

static void copy_name(char *dst, const char *src) {
    size_t n = 0;
    while (src[n] && n < KE_ACTION_NAME_MAX - 1) { dst[n] = src[n]; ++n; }
    dst[n] = '\0';
}

// ── Snapshot sampling ───────────────────────────────────────────────────────

static bool is_key_down(const ke_input_snapshot *snap, int key) {
    if (key < 0 || key >= 512) return false;
    return (snap->keys_down[key / 64] >> (key % 64)) & 1ULL;
}

static bool is_mouse_down(const ke_input_snapshot *snap, int button) {
    if (button < 0) return false;
    return (snap->mouse_buttons_down >> button) & 1u;
}

static bool sample_binding(const binding *b, const ke_input_snapshot *snap,
                            float *out_x, float *out_y, float *out_z) {
    *out_x = *out_y = *out_z = 0.0f;
    switch (b->kind) {
    case BK_KEY:
        *out_x = is_key_down(snap, b->k0) ? 1.0f : 0.0f;
        break;
    case BK_MOUSE_BUTTON:
        *out_x = is_mouse_down(snap, b->k0) ? 1.0f : 0.0f;
        break;
    case BK_KEY_PAIR: {
        float pos = is_key_down(snap, b->k1) ? 1.0f : 0.0f;
        float neg = is_key_down(snap, b->k0) ? 1.0f : 0.0f;
        *out_x = pos - neg;
        break;
    }
    case BK_KEY_QUAD: {
        float up    = is_key_down(snap, b->k0) ? 1.0f : 0.0f;
        float down  = is_key_down(snap, b->k1) ? 1.0f : 0.0f;
        float left  = is_key_down(snap, b->k2) ? 1.0f : 0.0f;
        float right = is_key_down(snap, b->k3) ? 1.0f : 0.0f;
        *out_x = right - left;
        *out_y = up - down;
        break;
    }
    }
    return *out_x != 0.0f || *out_y != 0.0f || *out_z != 0.0f;
}

// ── Binding parser (from TOML table) ────────────────────────────────────────

// Free helper for tomlc99 string datums (must `free` the s pointer).
static void free_datum_str(toml_datum_t d) { if (d.ok && d.u.s) free(d.u.s); }

static bool parse_binding_table(toml_table_t *bt, binding *out) {
    toml_datum_t kind = toml_string_in(bt, "kind");
    if (!kind.ok) return false;

    bool ok = false;
    if (strcmp(kind.u.s, "key") == 0) {
        toml_datum_t k = toml_string_in(bt, "key");
        if (k.ok) {
            out->kind = BK_KEY;
            out->k0 = lookup_key(k.u.s);
            ok = true;
            free_datum_str(k);
        }
    } else if (strcmp(kind.u.s, "key_pair") == 0) {
        toml_datum_t n = toml_string_in(bt, "negative");
        toml_datum_t p = toml_string_in(bt, "positive");
        if (n.ok && p.ok) {
            out->kind = BK_KEY_PAIR;
            out->k0 = lookup_key(n.u.s);
            out->k1 = lookup_key(p.u.s);
            ok = true;
        }
        free_datum_str(n); free_datum_str(p);
    } else if (strcmp(kind.u.s, "key_quad") == 0) {
        toml_datum_t up    = toml_string_in(bt, "up");
        toml_datum_t down  = toml_string_in(bt, "down");
        toml_datum_t left  = toml_string_in(bt, "left");
        toml_datum_t right = toml_string_in(bt, "right");
        if (up.ok && down.ok && left.ok && right.ok) {
            out->kind = BK_KEY_QUAD;
            out->k0 = lookup_key(up.u.s);
            out->k1 = lookup_key(down.u.s);
            out->k2 = lookup_key(left.u.s);
            out->k3 = lookup_key(right.u.s);
            ok = true;
        }
        free_datum_str(up); free_datum_str(down);
        free_datum_str(left); free_datum_str(right);
    } else if (strcmp(kind.u.s, "mouse") == 0) {
        toml_datum_t btn = toml_string_in(bt, "button");
        if (btn.ok) {
            out->kind = BK_MOUSE_BUTTON;
            out->k0 = lookup_mouse_button(btn.u.s);
            ok = true;
            free_datum_str(btn);
        }
    }
    free_datum_str(kind);
    return ok;
}

// ── vtable: load ────────────────────────────────────────────────────────────

static ke_result vt_load(ke_input_actions *self, const char *path, ke_error **out_error) {
    if (!self || !self->handle || !path) return KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "invalid argument");
    input_actions_state *s = (input_actions_state *)self->handle;
    clear_actions(s);

    FILE *fp = fopen(path, "rb");
    if (!fp) return KE_ERROR_SET(out_error, &KE_ERROR_NOT_FOUND, "input file not found");

    char errbuf[200];
    toml_table_t *root = toml_parse_file(fp, errbuf, sizeof(errbuf));
    fclose(fp);
    if (!root) return KE_ERROR_SET(out_error, &KE_ERROR_IO, "failed to parse input file");

    toml_table_t *action_section = toml_table_in(root, "action");
    if (!action_section) { toml_free(root); return KE_OK; }

    for (int i = 0; ; ++i) {
        const char *action_name = toml_key_in(action_section, i);
        if (!action_name) break;
        toml_table_t *action_tbl = toml_table_in(action_section, action_name);
        if (!action_tbl) continue;

        if (!ensure_action_capacity(s, s->action_count + 1)) { toml_free(root); return KE_ERROR_SET(out_error, &KE_ERROR_OUT_OF_MEMORY, "action capacity exceeded"); }
        action *act = &s->actions[s->action_count];
        memset(act, 0, sizeof(*act));
        copy_name(act->name, action_name);
        act->type = KE_ACTION_TYPE_BUTTON;

        toml_datum_t type_node = toml_string_in(action_tbl, "type");
        if (type_node.ok) {
            act->type = parse_action_type(type_node.u.s);
            free_datum_str(type_node);
        }

        toml_array_t *bindings_arr = toml_array_in(action_tbl, "bindings");
        if (bindings_arr) {
            int n = toml_array_nelem(bindings_arr);
            for (int j = 0; j < n; ++j) {
                toml_table_t *bt = toml_table_at(bindings_arr, j);
                if (!bt) continue;
                binding b;
                if (!parse_binding_table(bt, &b)) continue;
                if (!ensure_binding_capacity(s, act, act->binding_count + 1)) {
                    toml_free(root); return KE_ERROR_SET(out_error, &KE_ERROR_OUT_OF_MEMORY, "binding capacity exceeded");
                }
                act->bindings[act->binding_count++] = b;
            }
        }

        s->action_count++;
    }

    toml_free(root);
    return KE_OK;
}

// ── vtable: get_action_id ───────────────────────────────────────────────────

static int32_t vt_get_action_id(ke_input_actions *self, const char *name) {
    if (!self || !self->handle || !name) return -1;
    return find_action_by_name((input_actions_state *)self->handle, name);
}

// ── vtable: programmatic registration ───────────────────────────────────────

static int32_t vt_add_action(ke_input_actions *self, const char *name, ke_action_type type) {
    if (!self || !self->handle || !name || !*name) return -1;
    input_actions_state *s = (input_actions_state *)self->handle;
    if (find_action_by_name(s, name) >= 0) return -1;
    if (!ensure_action_capacity(s, s->action_count + 1)) return -1;

    action *act = &s->actions[s->action_count];
    memset(act, 0, sizeof(*act));
    copy_name(act->name, name);
    act->type = type;
    int32_t id = (int32_t)s->action_count;
    s->action_count++;
    return id;
}

static action *get_action_mut(input_actions_state *s, int32_t id) {
    if (id < 0 || (uint32_t)id >= s->action_count) return NULL;
    return &s->actions[id];
}

static ke_result append_binding(input_actions_state *s, int32_t id, binding b, ke_error **out_error) {
    action *a = get_action_mut(s, id);
    if (!a) return KE_ERROR_SET(out_error, &KE_ERROR_NOT_FOUND, "action not found");
    if (!ensure_binding_capacity(s, a, a->binding_count + 1)) return KE_ERROR_SET(out_error, &KE_ERROR_OUT_OF_MEMORY, "binding capacity exceeded");
    a->bindings[a->binding_count++] = b;
    return KE_OK;
}

static ke_result vt_bind_key(ke_input_actions *self, int32_t action_id, ke_key key, ke_error **out_error) {
    if (!self || !self->handle) return KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "invalid argument");
    binding b = { BK_KEY, (int)key, 0, 0, 0 };
    return append_binding((input_actions_state *)self->handle, action_id, b, out_error);
}

static ke_result vt_bind_mouse_button(ke_input_actions *self, int32_t action_id, ke_mouse_button button, ke_error **out_error) {
    if (!self || !self->handle) return KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "invalid argument");
    binding b = { BK_MOUSE_BUTTON, (int)button, 0, 0, 0 };
    return append_binding((input_actions_state *)self->handle, action_id, b, out_error);
}

static ke_result vt_bind_key_pair(ke_input_actions *self, int32_t action_id, ke_key neg, ke_key pos, ke_error **out_error) {
    if (!self || !self->handle) return KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "invalid argument");
    binding b = { BK_KEY_PAIR, (int)neg, (int)pos, 0, 0 };
    return append_binding((input_actions_state *)self->handle, action_id, b, out_error);
}

static ke_result vt_bind_key_quad(ke_input_actions *self, int32_t action_id,
                                   ke_key up, ke_key down, ke_key left, ke_key right, ke_error **out_error) {
    if (!self || !self->handle) return KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "invalid argument");
    binding b = { BK_KEY_QUAD, (int)up, (int)down, (int)left, (int)right };
    return append_binding((input_actions_state *)self->handle, action_id, b, out_error);
}

// ── vtable: evaluate ────────────────────────────────────────────────────────

static ke_result vt_evaluate(ke_input_actions *self, const ke_input_snapshot *snapshot,
                              ke_input_action_event_func on_event, void *event_ctx,
                              ke_error **out_error) {
    if (!self || !self->handle || !snapshot) return KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "invalid argument");
    input_actions_state *s = (input_actions_state *)self->handle;

    for (uint32_t id = 0; id < s->action_count; ++id) {
        action *a = &s->actions[id];
        a->prev_active = a->curr_active;
        a->prev_x = a->curr_x;
        a->prev_y = a->curr_y;
        a->prev_z = a->curr_z;

        float x = 0, y = 0, z = 0;
        bool any_active = false;
        for (uint32_t i = 0; i < a->binding_count; ++i) {
            float bx, by, bz;
            bool active = sample_binding(&a->bindings[i], snapshot, &bx, &by, &bz);
            if (active) {
                any_active = true;
                if (a->type == KE_ACTION_TYPE_BUTTON) {
                    x = 1.0f;
                } else {
                    if (fabsf(bx) > fabsf(x)) x = bx;
                    if (fabsf(by) > fabsf(y)) y = by;
                    if (fabsf(bz) > fabsf(z)) z = bz;
                }
            }
        }
        a->curr_x = x;
        a->curr_y = y;
        a->curr_z = z;
        a->curr_active = any_active;

        if (on_event && a->curr_active != a->prev_active) {
            ke_input_action_event ev = {0};
            ev.action_id = (int32_t)id;
            ev.type      = a->type;
            ev.phase     = a->curr_active ? KE_ACTION_PHASE_STARTED : KE_ACTION_PHASE_CANCELED;
            ev.x = x; ev.y = y; ev.z = z;
            on_event(event_ctx, ev);
        }
        if (on_event && a->curr_active && a->prev_active &&
            a->type != KE_ACTION_TYPE_BUTTON &&
            (a->prev_x != a->curr_x || a->prev_y != a->curr_y || a->prev_z != a->curr_z)) {
            ke_input_action_event ev = {0};
            ev.action_id = (int32_t)id;
            ev.type      = a->type;
            ev.phase     = KE_ACTION_PHASE_PERFORMED;
            ev.x = x; ev.y = y; ev.z = z;
            on_event(event_ctx, ev);
        }
    }
    return KE_OK;
}

// ── vtable: polling ─────────────────────────────────────────────────────────

static const action *get_action(const input_actions_state *s, int32_t id) {
    if (id < 0 || (uint32_t)id >= s->action_count) return NULL;
    return &s->actions[id];
}

static bool vt_is_action_down(ke_input_actions *self, int32_t id) {
    const action *a = get_action((input_actions_state *)self->handle, id);
    return a && a->curr_active;
}

static bool vt_was_action_pressed(ke_input_actions *self, int32_t id) {
    const action *a = get_action((input_actions_state *)self->handle, id);
    return a && a->curr_active && !a->prev_active;
}

static bool vt_was_action_released(ke_input_actions *self, int32_t id) {
    const action *a = get_action((input_actions_state *)self->handle, id);
    return a && !a->curr_active && a->prev_active;
}

static float vt_get_axis1d(ke_input_actions *self, int32_t id) {
    const action *a = get_action((input_actions_state *)self->handle, id);
    return a ? a->curr_x : 0.0f;
}

static void vt_get_axis2d(ke_input_actions *self, int32_t id, float *out_x, float *out_y) {
    const action *a = get_action((input_actions_state *)self->handle, id);
    if (out_x) *out_x = a ? a->curr_x : 0.0f;
    if (out_y) *out_y = a ? a->curr_y : 0.0f;
}

static void vt_get_axis3d(ke_input_actions *self, int32_t id, float *out_x, float *out_y, float *out_z) {
    const action *a = get_action((input_actions_state *)self->handle, id);
    if (out_x) *out_x = a ? a->curr_x : 0.0f;
    if (out_y) *out_y = a ? a->curr_y : 0.0f;
    if (out_z) *out_z = a ? a->curr_z : 0.0f;
}

// ── vtable: teardown ────────────────────────────────────────────────────────

static void vt_destroy(ke_input_actions *self) {
    if (!self || !self->handle) return;
    input_actions_state *s = (input_actions_state *)self->handle;
    clear_actions(s);
    if (s->actions) s->allocator->free(s->allocator, s->actions);
    ke_allocator *a = s->allocator;
    a->free(a, s);
    a->destroy(a);
}

// ── Factory ─────────────────────────────────────────────────────────────────

ke_result ke_input_actions_create(ke_input_actions **out_actions, ke_error **out_error) {
    if (!out_actions) return KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "invalid argument");

    ke_allocator *alloc = ke_allocator_malloc_create();
    if (!alloc) return KE_ERROR_SET(out_error, &KE_ERROR_OUT_OF_MEMORY, "allocator creation failed");

    input_actions_state *s = (input_actions_state *)alloc->alloc(
        alloc, sizeof(input_actions_state), 8);
    if (!s) { alloc->destroy(alloc); return KE_ERROR_SET(out_error, &KE_ERROR_OUT_OF_MEMORY, "state allocation failed"); }
    memset(s, 0, sizeof(*s));
    s->allocator = alloc;

    s->api.handle              = s;
    s->api.load                = vt_load;
    s->api.get_action_id       = vt_get_action_id;
    s->api.add_action          = vt_add_action;
    s->api.bind_key            = vt_bind_key;
    s->api.bind_mouse_button   = vt_bind_mouse_button;
    s->api.bind_key_pair       = vt_bind_key_pair;
    s->api.bind_key_quad       = vt_bind_key_quad;
    s->api.evaluate            = vt_evaluate;
    s->api.is_action_down      = vt_is_action_down;
    s->api.was_action_pressed  = vt_was_action_pressed;
    s->api.was_action_released = vt_was_action_released;
    s->api.get_axis1d          = vt_get_axis1d;
    s->api.get_axis2d          = vt_get_axis2d;
    s->api.get_axis3d          = vt_get_axis3d;
    s->api.destroy             = vt_destroy;

    *out_actions = &s->api;
    return KE_OK;
}
