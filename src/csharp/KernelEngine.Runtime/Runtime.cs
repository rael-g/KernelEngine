using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using KernelEngine.Ecs.Flecs;
using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;
using KernelEngine.Runtime.Native;

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
    private readonly Allocator                          _allocator;
    private readonly IEcs                               _ecs;            // not owned; consumer disposes separately
    private readonly KernelEngine.Kernel.TaskScheduler  _taskScheduler;  // not owned

    private readonly List<GCHandle> _moduleHandles = new();
    private readonly List<GCHandle> _systemHandles = new();

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(CallConvCdecl) })]
    private static int ModuleLoadTrampoline(ke_runtime* rt, void* userData)
    {
        try
        {
            var handle = GCHandle.FromIntPtr((nint)userData);
            var entry = (ModuleEntry)handle.Target!;
            entry.OnLoad(entry.Owner);
            return 0;
        }
        catch (Exception ex)
        {
            lock (s_excLock) s_pendingException = ex;
            return (int)ke_result.KE_ERROR;
        }
    }

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(CallConvCdecl) })]
    private static void SystemExecuteTrampoline(ke_system_ctx* ctx, void* userData, float dt)
    {
        try
        {
            var handle = GCHandle.FromIntPtr((nint)userData);
            var entry = (SystemEntry)handle.Target!;
            entry.Execute(entry.Owner, dt);
        }
        catch (Exception ex)
        {
            lock (s_excLock) s_pendingException = ex;
        }
    }

    // Exception propagation across the C ABI boundary. enki may dispatch the
    // execute callback onto a worker thread, so we can't use [ThreadStatic] —
    // Tick reads on the calling thread but the trampoline writes on a worker.
    // Single static + lock is safe for the prototype; if multiple systems in
    // the same wave throw, the last one wins (acceptable for now).
    private static readonly object s_excLock = new();
    private static Exception? s_pendingException;

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

    /// <summary>Borrowed pointer to the native ke_runtime vtable. Valid until Dispose.</summary>
    public ke_runtime* Native => _native;

    public Runtime(Allocator allocator, IEcs ecs, ITaskScheduler taskScheduler)
    {
        ArgumentNullException.ThrowIfNull(allocator);
        ArgumentNullException.ThrowIfNull(ecs);
        ArgumentNullException.ThrowIfNull(taskScheduler);

        // The runtime needs raw C ABI handles, not interfaces. For now we
        // recognize the concrete wrappers shipped by the engine; future impls
        // would either add their own native-handle protocol or wire through
        // an internal contract. The cast is contained — it lives only here.
        if (ecs is not FlecsEcs flecsEcs)
            throw new ArgumentException(
                $"Runtime currently requires {nameof(FlecsEcs)} as the {nameof(IEcs)} impl; got {ecs.GetType().Name}.",
                nameof(ecs));
        if (taskScheduler is not KernelEngine.Kernel.TaskScheduler tsConcrete)
            throw new ArgumentException(
                $"Runtime currently requires {nameof(KernelEngine.Kernel.TaskScheduler)} (or a subclass) as the {nameof(ITaskScheduler)} impl; got {taskScheduler.GetType().Name}.",
                nameof(taskScheduler));

        _allocator     = allocator;
        _ecs           = ecs;
        _taskScheduler = tsConcrete;

        ke_runtime_params @params = default;
        ke_runtime* rt;
        var rc = KernelEngine.Runtime.Native.NativeMethods.runtime_create(
            flecsEcs.Native, tsConcrete.Native, &@params, &rt);
        if (rc != (int)ke_result.KE_OK)
            throw new InvalidOperationException($"ke_runtime_create failed: {(ke_result)rc}");
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
            p.on_load   = &ModuleLoadTrampoline;

            var rc = _native->register_module(_native, &p, &id);
            // Surface any exception captured by the trampoline so the caller
            // gets the real stack trace, not just KE_ERROR.
            Exception? trampolineEx;
            lock (s_excLock) { trampolineEx = s_pendingException; s_pendingException = null; }
            if (trampolineEx != null)
                throw new InvalidOperationException(
                    $"Module '{name}' OnLoad threw", trampolineEx);
            CheckResult(rc, nameof(RegisterModule));
        }
        return id;
    }

    public ulong RegisterSystem(string name, RuntimePhase phase, Action<IRuntime, float> execute,
                                 uint pinnedThread = 0)
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
            p.name           = (sbyte*)namePtr;
            p.phase          = (ke_phase)phase;
            p.pinned_thread  = pinnedThread;
            p.user_data      = (void*)GCHandle.ToIntPtr(handle);
            p.execute        = (delegate* unmanaged[Cdecl]<ke_system_ctx*, void*, float, void>)
                                &SystemExecuteTrampoline;

            var rc = _native->register_system(_native, &p, &id);
            CheckResult(rc, nameof(RegisterSystem));
        }
        return id;
    }

    public void Tick(float dt)
    {
        ThrowIfDisposed();
        lock (s_excLock) s_pendingException = null;
        var rc = _native->tick(_native, dt);
        Exception? ex;
        lock (s_excLock) { ex = s_pendingException; s_pendingException = null; }
        if (ex != null)
            throw new InvalidOperationException("System execution threw", ex);
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
    private static void CheckResult(int rc, string op)
    {
        if (rc != (int)ke_result.KE_OK)
            throw new InvalidOperationException($"Runtime.{op} failed: {(ke_result)rc}");
    }
}
