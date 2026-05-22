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
    // Entity → managed callbacks. Mirrors the lifetime of the entity's ke_script_component.
    private static readonly Dictionary<ulong, (Action start, Action<float> update)> s_callbacks = [];

    /// <summary>
    /// Adds a <c>ke_script_component</c> to the entity wired to the static trampolines and records
    /// the managed callbacks the trampolines will dispatch to.
    /// </summary>
    public static void Register(EcsRegistry registry, uint scriptComponentId, ulong entity, Action onStart, Action<float> onUpdate)
    {
        s_callbacks[entity] = (onStart, onUpdate);
        var slot = registry.AddComponent<ke_script_component>(entity, scriptComponentId);
        slot[0] = new ke_script_component
        {
            started = false,
            on_start = &NativeOnStart,
            on_update = &NativeOnUpdate,
        };
    }

    /// <summary>Forgets an entity's callbacks (call when the entity/node is destroyed).</summary>
    public static void Unregister(ulong entity) => s_callbacks.Remove(entity);

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static ke_result NativeOnStart(ulong entity)
    {
        if (s_callbacks.TryGetValue(entity, out var cb))
            cb.start();
        return ke_result.KE_OK;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static ke_result NativeOnUpdate(ulong entity, float dt)
    {
        if (s_callbacks.TryGetValue(entity, out var cb))
            cb.update(dt);
        return ke_result.KE_OK;
    }
}
