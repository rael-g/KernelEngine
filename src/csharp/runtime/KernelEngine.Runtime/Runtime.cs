using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using KernelEngine.Ecs.Flecs;
using KernelEngine.Common.Native;
using KernelEngine.Ecs;
using KernelEngine.Scheduler;

namespace KernelEngine.Runtime;

/// <summary>
/// In-house scheduler implementing <see cref="IRuntime"/>. Holds an injected
/// <see cref="FlecsEcs"/> as borrowed storage; never destroys it. Lifetime: construct
/// once at game startup, dispose at shutdown. Holds GC roots for every registered
/// callback so the C side can invoke them across the ABI boundary without the GC
/// reclaiming the delegates.
/// </summary>
public sealed unsafe class Runtime : IRuntime, INativeRuntime
{
    private ke_runtime* _native;
    private readonly delegate* unmanaged[Cdecl]<ke_runtime*, void> _destroy;
    private readonly IEcs                               _ecs;            // not owned; consumer disposes separately
    private readonly KernelEngine.Scheduler.Scheduler  _taskScheduler;  // not owned

    private readonly List<GCHandle> _moduleHandles = new();
    private readonly List<GCHandle> _systemHandles = new();

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(CallConvCdecl) })]
    private static bool ModuleLoadTrampoline(ke_runtime* rt, void* userData, ke_error** out_error)
    {
        try
        {
            var handle = GCHandle.FromIntPtr((nint)userData);
            var entry = (ModuleEntry)handle.Target!;
            entry.OnLoad(entry.Owner);
            return true;
        }
        catch (Exception ex)
        {
            lock (s_excLock) s_pendingException = ex;
            return false;
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

    ke_runtime* INativeRuntime.Native => _native;

    public Runtime(IEcs ecs, IScheduler taskScheduler)
    {
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
        if (taskScheduler is not KernelEngine.Scheduler.Scheduler tsConcrete)
            throw new ArgumentException(
                $"Runtime currently requires {nameof(KernelEngine.Scheduler.Scheduler)} (or a subclass) as the {nameof(IScheduler)} impl; got {taskScheduler.GetType().Name}.",
                nameof(taskScheduler));

        _ecs           = ecs;
        _taskScheduler = tsConcrete;

        ke_runtime_params @params = default;
        var handle = KernelEngine.Runtime.Native.NativeMethods.runtime_create(
            ((INativeEcs)flecsEcs).Native, ((INativeScheduler)tsConcrete).Native, &@params, null);
        if (handle.@ref == null)
            throw new InvalidOperationException("ke_runtime_create failed");
        _native = handle.@ref;
        _destroy = handle.destroy;
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

            id = _native->register_module(_native, &p, null);
            // Surface any exception captured by the trampoline so the caller
            // gets the real stack trace, not just a generic error.
            Exception? trampolineEx;
            lock (s_excLock) { trampolineEx = s_pendingException; s_pendingException = null; }
            if (trampolineEx != null)
                throw new InvalidOperationException(
                    $"Module '{name}' OnLoad threw", trampolineEx);
            if (id == 0) throw new InvalidOperationException($"Runtime.{nameof(RegisterModule)} failed");
        }
        return id;
    }

    public ulong RegisterSystem(string name, RuntimePhase phase, Action<IRuntime, float> execute,
                                 uint pinnedThread = 0, bool exclusive = false)
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
            p.exclusive      = exclusive;
            p.user_data      = (void*)GCHandle.ToIntPtr(handle);
            p.execute        = (delegate* unmanaged[Cdecl]<ke_system_ctx*, void*, float, void>)
                                &SystemExecuteTrampoline;

            id = _native->register_system(_native, &p, null);
            if (id == 0) throw new InvalidOperationException($"Runtime.{nameof(RegisterSystem)} failed");
        }
        return id;
    }

    public void Tick(float dt)
    {
        ThrowIfDisposed();
        lock (s_excLock) s_pendingException = null;
        bool ok = _native->tick(_native, dt, null);
        Exception? ex;
        lock (s_excLock) { ex = s_pendingException; s_pendingException = null; }
        if (ex != null)
            throw new InvalidOperationException("System execution threw", ex);
        if (!ok) throw new InvalidOperationException($"Runtime.{nameof(Tick)} failed");
    }

    public void Dispose()
    {
        if (_native == null) return;
        if (_destroy != null) _destroy(_native);
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

}
