using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using KernelEngine.Kernel.Native;
using NLua;

namespace LuaSpike;

/// <summary>
/// Wires a Lua script file to a <c>ke_script_component</c> on a given entity.
/// Each entity gets its own <see cref="Lua"/> state so scripts are isolated.
/// The trampolines are static (required by [UnmanagedCallersOnly]) and dispatch
/// to the correct Lua state via a static registry keyed by entity ID.
/// </summary>
internal static unsafe class LuaScriptBridge
{
    private record struct LuaCallbacks(Lua State, LuaFunction? OnAwake, LuaFunction? OnStart,
        LuaFunction? OnUpdate, LuaFunction? OnLateUpdate, LuaFunction? OnDestroy);

    private static readonly Dictionary<ulong, LuaCallbacks> s_states = [];

    /// <summary>
    /// Loads <paramref name="scriptPath"/>, extracts the lifecycle functions, adds a
    /// <c>ke_script_component</c> to the entity, and wires the trampolines.
    /// </summary>
    public static void Register(EcsRegistry registry, uint scriptComponentId, ulong entity, string scriptPath)
    {
        var lua = new Lua();
        lua.LoadCLRPackage();
        lua.DoFile(scriptPath);

        var callbacks = new LuaCallbacks(
            State:        lua,
            OnAwake:      lua["on_awake"]      as LuaFunction,
            OnStart:      lua["on_start"]      as LuaFunction,
            OnUpdate:     lua["on_update"]     as LuaFunction,
            OnLateUpdate: lua["on_late_update"] as LuaFunction,
            OnDestroy:    lua["on_destroy"]    as LuaFunction);

        s_states[entity] = callbacks;

        var slot = registry.AddComponent<ke_script_component>(entity, scriptComponentId);
        slot[0] = new ke_script_component
        {
            state          = 0,
            on_awake       = callbacks.OnAwake      != null ? &NativeOnAwake      : null,
            on_start       = callbacks.OnStart      != null ? &NativeOnStart      : null,
            on_update      = callbacks.OnUpdate     != null ? &NativeOnUpdate     : null,
            on_late_update = callbacks.OnLateUpdate != null ? &NativeOnLateUpdate : null,
            on_destroy     = callbacks.OnDestroy    != null ? &NativeOnDestroy    : null,
            on_input       = null,
        };
    }

    /// <summary>Disposes the Lua state and removes the script component.</summary>
    public static void Unregister(ulong entity)
    {
        if (s_states.Remove(entity, out var cb))
            cb.State.Dispose();
    }

    // ── Trampolines ───────────────────────────────────────────────────────────

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static ke_result NativeOnAwake(ulong entity)
    {
        if (s_states.TryGetValue(entity, out var cb))
            cb.OnAwake?.Call(entity);
        return ke_result.KE_OK;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static ke_result NativeOnStart(ulong entity)
    {
        if (s_states.TryGetValue(entity, out var cb))
            cb.OnStart?.Call(entity);
        return ke_result.KE_OK;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static ke_result NativeOnUpdate(ulong entity, float dt)
    {
        if (s_states.TryGetValue(entity, out var cb))
            cb.OnUpdate?.Call(entity, dt);
        return ke_result.KE_OK;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static ke_result NativeOnLateUpdate(ulong entity, float dt)
    {
        if (s_states.TryGetValue(entity, out var cb))
            cb.OnLateUpdate?.Call(entity, dt);
        return ke_result.KE_OK;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static ke_result NativeOnDestroy(ulong entity)
    {
        if (s_states.TryGetValue(entity, out var cb))
            cb.OnDestroy?.Call(entity);
        return ke_result.KE_OK;
    }
}
