#ifndef KERNEL_ENGINE_CONFIGURATION_CONFIGURATION_H_
#define KERNEL_ENGINE_CONFIGURATION_CONFIGURATION_H_

// ke_configuration — a format-agnostic, typed section/key settings store with a
// change subscription (the native equivalent of a reactive settings monitor).
//
// This is a kernel primitive: it knows nothing about TOML, JSON, or any file
// format. A loader (e.g. the framework reading Project.toml via tomlc99)
// populates the store through the set_* slots; consumers read through the typed
// get_* slots with a fallback.
//
// Multi-language rationale: settings are a universal engine capability, far too
// important to live only in the C# composition layer. The store is a C-ABI
// contract so every host (C#, Lua, Rust, future backends) shares one mechanism;
// the C# side is a thin wrapper over this vtable. The implementation is Zig
// (src/zig/configuration/); this header is the contract both the impl and the
// bindings read.
//
// Doctrine (see docs/RenderArchitectureV2.md §9.9):
//   - A value is addressed by (section, key), both strings. "shadow"/"resolution"
//     maps to what a TOML loader flattens from `[shadow] resolution = 2048`.
//   - get_* returns the provided fallback when the key is missing OR stored with
//     a different type. Missing is never an error — defaults live on the caller.
//   - A subscription fires when any key in its section is written after the
//     subscriber attached. The callback runs synchronously on the writing thread
//     and MUST only latch a pending change; the owning system applies it at its
//     own next execution point (never touch GPU/threaded state here, and never
//     reintroduce pinning to do so).
//   - Cross-thread access is the caller's responsibility; the store is
//     single-threaded inside.

#include <kernel_engine/common/error.h>
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    typedef uint32_t ke_configuration_subscription;

#define KE_CONFIGURATION_SUBSCRIPTION_NONE UINT32_MAX

    /// Change callback: invoked with the section whose value(s) changed, plus the
    /// unchanged ctx supplied at subscribe time. Latch-only — see doctrine above.
    typedef void (*ke_configuration_change_func)(const char *section, void *ctx);

    typedef struct ke_configuration
    {
        void *handle; // opaque; owned by the implementation

        // ── Typed reads (return fallback when absent or type-mismatched) ──────

        int64_t (*get_int)(struct ke_configuration *self, const char *section, const char *key, int64_t fallback);
        double (*get_double)(struct ke_configuration *self, const char *section, const char *key, double fallback);
        bool (*get_bool)(struct ke_configuration *self, const char *section, const char *key, bool fallback);
        /// Returned pointer is owned by the store and valid until the same key is
        /// overwritten or the store is destroyed. Copy it if you need to retain.
        const char *(*get_string)(struct ke_configuration *self, const char *section, const char *key, const char *fallback);

        // ── Typed writes (loader at boot; settings API at runtime → notify) ───

        bool (*set_int)(struct ke_configuration *self, const char *section, const char *key, int64_t value, ke_error **out_error);
        bool (*set_double)(struct ke_configuration *self, const char *section, const char *key, double value, ke_error **out_error);
        bool (*set_bool)(struct ke_configuration *self, const char *section, const char *key, bool value, ke_error **out_error);
        bool (*set_string)(struct ke_configuration *self, const char *section, const char *key, const char *value, ke_error **out_error);

        // ── Change subscription (native OnChange) ─────────────────────────────

        /// Subscribes to writes on `section`. Returns a subscription id, or
        /// KE_CONFIGURATION_SUBSCRIPTION_NONE on failure.
        ke_configuration_subscription (*subscribe)(struct ke_configuration *self,
                                                   const char                  *section,
                                                   ke_configuration_change_func cb,
                                                   void                        *ctx);

        /// Removes a subscription. Safe to call with KE_CONFIGURATION_SUBSCRIPTION_NONE.
        void (*unsubscribe)(struct ke_configuration *self, ke_configuration_subscription sub);

    } ke_configuration;

    typedef struct ke_configuration_handle
    {
        ke_configuration *ref;
        void (*destroy)(ke_configuration *self);
    } ke_configuration_handle;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_CONFIGURATION_CONFIGURATION_H_
