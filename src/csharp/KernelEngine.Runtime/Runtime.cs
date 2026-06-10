using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using KernelEngine.Ecs.Flecs;
using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Runtime;

/// <summary>
/// In-house scheduler implementing <see cref="IRuntime"/>. Holds an injected
/// <see cref="FlecsEcs"/> as borrowed storage; never destroys it. Lifetime: construct
/// once at game startup, dispose at shutdown. Holds GC roots for every registered
/// callback so the C side can invoke them across the ABI boundary without the GC
/// reclaiming the delegates.
/// </summary>
public sealed unsafe class Runtime : IRuntime
{
    private ke_runtime* _native;
    private readonly Allocator _allocator;
    private readonly FlecsEcs  _ecs;  // not owned; consumer disposes separately

    private readonly List<GCHandle> _moduleHandles = new();
    private readonly List<GCHandle> _systemHandles = new();

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(CallConvCdecl) })]
    private static ke_result ModuleLoadTrampoline(ke_runtime* rt, void* userData)
    {
        try
        {
            var handle = GCHandle.FromIntPtr((nint)userData);
            var entry = (ModuleEntry)handle.Target!;
            entry.OnLoad(entry.Owner);
            return ke_result.KE_OK;
        }
        catch (Exception ex)
        {
            s_pendingException = ex;
            return ke_result.KE_ERROR;
        }
    }

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(CallConvCdecl) })]
    private static void SystemExecuteTrampoline(ke_runtime* rt, void* userData, float dt)
    {
        try
        {
            var handle = GCHandle.FromIntPtr((nint)userData);
            var entry = (SystemEntry)handle.Target!;
            entry.Execute(entry.Owner, dt);
        }
        catch (Exception ex)
        {
            s_pendingException = ex;
        }
    }

    [ThreadStatic] private static Exception? s_pendingException;

    private sealed class ModuleEntry
    {
        public required Runtime Owner { get; init; }
        public required Action<IRuntime> OnLoad { get; init; }
    }

    private sealed class SystemEntry
    {
        public required Runtime Owner { get; init; }
        public required Action<IRuntime, float> Execute { get; init; }
    }

    public Runtime(Allocator allocator, FlecsEcs ecs)
    {
        ArgumentNullException.ThrowIfNull(allocator);
        ArgumentNullException.ThrowIfNull(ecs);
        _allocator = allocator;
        _ecs = ecs;

        ke_runtime_params @params = default;
        ke_runtime* rt;
        var rc = NativeMethods.runtime_create(allocator.Native, ecs.Native, &@params, &rt);
        if (rc != ke_result.KE_OK)
            throw new InvalidOperationException($"ke_runtime_create failed: {rc}");
        _native = rt;
    }

    public ulong RegisterModule(string name, Action<IRuntime> onLoad)
    {
        ThrowIfDisposed();
        ArgumentException.ThrowIfNullOrEmpty(name);
        ArgumentNullException.ThrowIfNull(onLoad);

        var entry = new ModuleEntry { Owner = this, OnLoad = onLoad };
        var handle = GCHandle.Alloc(entry);
        _moduleHandles.Add(handle);

        var nameBytes = System.Text.Encoding.UTF8.GetBytes(name + "\0");
        ulong id;
        fixed (byte* namePtr = nameBytes)
        {
            ke_runtime_module_params p = default;
            p.name      = (sbyte*)namePtr;
            p.user_data = (void*)GCHandle.ToIntPtr(handle);
            p.on_load   = (delegate* unmanaged[Cdecl]<ke_runtime*, void*, ke_result>)
                          &ModuleLoadTrampoline;

            var rc = _native->register_module(_native, &p, &id);
            CheckResult(rc, nameof(RegisterModule));
        }
        return id;
    }

    public ulong RegisterSystem(string name, RuntimePhase phase, Action<IRuntime, float> execute)
    {
        ThrowIfDisposed();
        ArgumentException.ThrowIfNullOrEmpty(name);
        ArgumentNullException.ThrowIfNull(execute);

        var entry = new SystemEntry { Owner = this, Execute = execute };
        var handle = GCHandle.Alloc(entry);
        _systemHandles.Add(handle);

        var nameBytes = System.Text.Encoding.UTF8.GetBytes(name + "\0");
        ulong id;
        fixed (byte* namePtr = nameBytes)
        {
            ke_runtime_system_params p = default;
            p.name      = (sbyte*)namePtr;
            p.phase     = (ke_phase)phase;
            p.user_data = (void*)GCHandle.ToIntPtr(handle);
            p.execute   = (delegate* unmanaged[Cdecl]<ke_runtime*, void*, float, void>)
                          &SystemExecuteTrampoline;

            var rc = _native->register_system(_native, &p, &id);
            CheckResult(rc, nameof(RegisterSystem));
        }
        return id;
    }

    public void Tick(float dt)
    {
        ThrowIfDisposed();
        s_pendingException = null;
        var rc = _native->tick(_native, dt);
        if (s_pendingException is { } ex)
        {
            s_pendingException = null;
            throw new InvalidOperationException("System execution threw", ex);
        }
        CheckResult(rc, nameof(Tick));
    }

    public void Dispose()
    {
        if (_native == null) return;
        _native->destroy(_native);
        _native = null;

        foreach (var h in _moduleHandles) if (h.IsAllocated) h.Free();
        _moduleHandles.Clear();
        foreach (var h in _systemHandles) if (h.IsAllocated) h.Free();
        _systemHandles.Clear();
    }

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    private void ThrowIfDisposed()
    {
        if (_native == null) throw new ObjectDisposedException(nameof(Runtime));
    }

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    private static void CheckResult(ke_result rc, string op)
    {
        if (rc != ke_result.KE_OK)
            throw new InvalidOperationException($"Runtime.{op} failed: {rc}");
    }
}
