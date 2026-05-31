using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Kernel;

/// <summary>
/// Bridges managed per-entity script callbacks to the C <c>ScriptSystem</c>.
/// <para>
/// The C system calls function pointers stored in <c>ke_script_component</c>. This type owns the
/// only <see cref="UnmanagedCallersOnlyAttribute"/> trampolines in the managed stack: they look up
/// the entity's managed callbacks and invoke them. Keeping all function-pointer machinery here lets
/// the Framework (and game code) stay free of <c>unsafe</c> — callers register plain delegates.
/// </para>
/// </summary>
internal static unsafe class ScriptBridge
{
    private record struct Callbacks(
        Action? Awake,
        Action? Start,
        Action<float>? Update,
        Action<float>? LateUpdate,
        Action? Destroy,
        Action<ke_input_snapshot>? Input);

    // Entity → managed callbacks. Mirrors the lifetime of the entity's ke_script_component.
    private static readonly Dictionary<ulong, Callbacks> s_callbacks = [];

    /// <summary>
    /// Adds a <c>ke_script_component</c> to the entity wired to the static trampolines and records
    /// the managed callbacks the trampolines will dispatch to. All parameters are optional.
    /// </summary>
    public static void Register(
        EcsRegistry registry,
        uint scriptComponentId,
        ulong entity,
        Action? onAwake      = null,
        Action? onStart      = null,
        Action<float>? onUpdate     = null,
        Action<float>? onLateUpdate = null,
        Action? onDestroy    = null,
        Action<ke_input_snapshot>? onInput = null)
    {
        s_callbacks[entity] = new Callbacks(onAwake, onStart, onUpdate, onLateUpdate, onDestroy, onInput);
        var slot = registry.AddComponent<ke_script_component>(entity, scriptComponentId);
        slot[0] = new ke_script_component
        {
            state          = 0,
            on_awake       = onAwake      != null ? &NativeOnAwake      : null,
            on_start       = onStart      != null ? &NativeOnStart      : null,
            on_update      = onUpdate     != null ? &NativeOnUpdate     : null,
            on_late_update = onLateUpdate != null ? &NativeOnLateUpdate : null,
            on_destroy     = onDestroy    != null ? &NativeOnDestroy    : null,
            on_input       = onInput      != null ? &NativeOnInput      : null,
        };
    }

    /// <summary>Forgets an entity's callbacks (call when the entity/node is destroyed).</summary>
    public static void Unregister(ulong entity) => s_callbacks.Remove(entity);

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static ke_result NativeOnAwake(ulong entity)
    {
        if (s_callbacks.TryGetValue(entity, out var cb))
            cb.Awake?.Invoke();
        return ke_result.KE_OK;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static ke_result NativeOnStart(ulong entity)
    {
        if (s_callbacks.TryGetValue(entity, out var cb))
            cb.Start?.Invoke();
        return ke_result.KE_OK;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static ke_result NativeOnUpdate(ulong entity, float dt)
    {
        if (s_callbacks.TryGetValue(entity, out var cb))
            cb.Update?.Invoke(dt);
        return ke_result.KE_OK;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static ke_result NativeOnLateUpdate(ulong entity, float dt)
    {
        if (s_callbacks.TryGetValue(entity, out var cb))
            cb.LateUpdate?.Invoke(dt);
        return ke_result.KE_OK;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static ke_result NativeOnDestroy(ulong entity)
    {
        if (s_callbacks.TryGetValue(entity, out var cb))
            cb.Destroy?.Invoke();
        return ke_result.KE_OK;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static ke_result NativeOnInput(ulong entity, ke_input_snapshot* input)
    {
        if (input != null && s_callbacks.TryGetValue(entity, out var cb))
            cb.Input?.Invoke(*input);
        return ke_result.KE_OK;
    }
}
