using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using KernelEngine.Ecs.Flecs;
using KernelEngine.Common.Native;
using KernelEngine.Ecs;
using KernelEngine.Ecs.Native;
using KernelEngine.Scheduler;
using KernelEngine.Scheduler.Native;

namespace KernelEngine.Runtime;

/// <summary>
/// The parts of <see cref="Runtime"/> that are not a direct image of the C ABI:
/// registration takes managed delegates, which have no ABI shape, so each one is
/// held by a GC root and reached through a static trampoline; and an exception
/// thrown inside a system body cannot cross the C boundary, so it is queued on the
/// runtime that owns the system and rethrown by the next <see cref="Tick"/> or
/// <see cref="Flush"/>. Everything mirroring the vtable 1:1 is generated in
/// <c>Generated/Runtime.g.cs</c>.
/// </summary>
public sealed unsafe partial class Runtime : IRuntime
{
    private readonly List<GCHandle> _moduleHandles = [];
    private readonly List<GCHandle> _systemHandles = [];

    /// <summary>
    /// What system bodies belonging to this runtime have thrown and not yet been told
    /// about. The render phase is dispatched asynchronously and outlives the
    /// <see cref="Tick"/> that started it, so a failure can arrive on a worker thread at
    /// any moment — including between one tick reading this and the next one starting.
    /// Nothing here is ever discarded unread: it is drained, never cleared.
    /// </summary>
    private readonly System.Collections.Concurrent.ConcurrentQueue<Exception> _systemFailures = new();

    private sealed class ModuleEntry
    {
        public required Runtime Owner { get; init; }
        public required Action<IRuntime> OnLoad { get; init; }

        /// <summary>
        /// What <see cref="OnLoad"/> threw. Held on the entry rather than on the runtime
        /// because the load runs inside the registering call, and a system failing
        /// concurrently on a worker would otherwise be reported as this module's.
        /// </summary>
        public Exception? Failure;
    }

    private sealed class SystemEntry
    {
        public required Runtime Owner { get; init; }
        public Action<IRuntime, float>? Execute { get; init; }
        public Action<IRuntime, nint, float>? ExecuteCtx { get; init; }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static bool ModuleLoadTrampoline(ke_runtime* rt, void* userData, ke_error** out_error)
    {
        var entry = (ModuleEntry)GCHandle.FromIntPtr((nint)userData).Target!;
        try
        {
            entry.OnLoad(entry.Owner);
            return true;
        }
        catch (Exception ex)
        {
            entry.Failure = ex;
            return false;
        }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static void SystemExecuteTrampoline(ke_system_ctx* ctx, void* userData, float dt)
    {
        var entry = (SystemEntry)GCHandle.FromIntPtr((nint)userData).Target!;
        try
        {
            if (entry.ExecuteCtx is not null)
                entry.ExecuteCtx(entry.Owner, (nint)ctx, dt);
            else
                entry.Execute!(entry.Owner, dt);
        }
        catch (Exception ex)
        {
            entry.Owner._systemFailures.Enqueue(ex);
        }
    }

    /// <summary>
    /// Throws whatever system bodies have reported since the last drain, or returns if
    /// none have. A failure raised by the render phase is reported by the call that
    /// observes it rather than by the tick that dispatched the phase, because that tick
    /// had already returned before the body ran.
    /// </summary>
    private void DrainSystemFailures()
    {
        if (_systemFailures.IsEmpty) return;

        var collected = new List<Exception>();
        while (_systemFailures.TryDequeue(out var failure)) collected.Add(failure);
        if (collected.Count == 0) return;

        throw new InvalidOperationException("System execution threw",
            collected.Count == 1 ? collected[0] : new AggregateException(collected));
    }

    /// <summary>
    /// Builds a runtime over borrowed ECS storage and a borrowed task scheduler.
    /// Only the pointers are taken: keeping the managed wrappers reachable is the
    /// caller's business, exactly as it is for whoever else borrows them.
    /// </summary>
    public Runtime(INativeEcs ecs, IScheduler taskScheduler)
        : this(NativeEcsOf(ecs), NativeSchedulerOf(taskScheduler), null)
    {
    }

    private static ke_ecs* NativeEcsOf(INativeEcs ecs)
    {
        ArgumentNullException.ThrowIfNull(ecs);
        return ecs.Native;
    }

    private static ke_scheduler* NativeSchedulerOf(IScheduler taskScheduler)
    {
        ArgumentNullException.ThrowIfNull(taskScheduler);
        if (taskScheduler is not KernelEngine.Scheduler.Scheduler concrete)
            throw new ArgumentException(
                $"Runtime currently requires {nameof(KernelEngine.Scheduler.Scheduler)} (or a subclass) as the "
                + $"{nameof(IScheduler)} impl; got {taskScheduler.GetType().Name}.",
                nameof(taskScheduler));
        return ((INativeScheduler)concrete).Native;
    }

    /// <inheritdoc />
    public ulong RegisterModule(string name, Action<IRuntime> onLoad)
    {
        ArgumentException.ThrowIfNullOrEmpty(name);
        ArgumentNullException.ThrowIfNull(onLoad);

        var entry = new ModuleEntry { Owner = this, OnLoad = onLoad };
        var handle = GCHandle.Alloc(entry);
        _moduleHandles.Add(handle);

        var nameBytes = System.Text.Encoding.UTF8.GetBytes(name + "\0");
        fixed (byte* namePtr = nameBytes)
        {
            ke_runtime_module_params p = default;
            p.name      = (sbyte*)namePtr;
            p.user_data = (void*)GCHandle.ToIntPtr(handle);
            p.on_load   = &ModuleLoadTrampoline;

            var id = RegisterModule(&p);
            if (entry.Failure is { } trampolineEx)
                throw new InvalidOperationException($"Module '{name}' OnLoad threw", trampolineEx);
            return id;
        }
    }

    /// <inheritdoc />
    public ulong RegisterSystem(string name, RuntimePhase phase, Action<IRuntime, float> execute,
                                 IReadOnlyList<QueryDecl>? queries = null,
                                 IReadOnlyList<ComponentAccess>? accessList = null,
                                 uint pinnedThread = 0,
                                 bool perEntity = false)
    {
        ArgumentNullException.ThrowIfNull(execute);
        return RegisterSystemEntry(name, phase, new SystemEntry { Owner = this, Execute = execute },
                                    queries, accessList, pinnedThread, perEntity);
    }

    /// <inheritdoc />
    public ulong RegisterSystem(string name, RuntimePhase phase, Action<IRuntime, nint, float> execute,
                                 IReadOnlyList<QueryDecl>? queries = null,
                                 IReadOnlyList<ComponentAccess>? accessList = null,
                                 uint pinnedThread = 0,
                                 bool perEntity = false)
    {
        ArgumentNullException.ThrowIfNull(execute);
        return RegisterSystemEntry(name, phase, new SystemEntry { Owner = this, ExecuteCtx = execute },
                                    queries, accessList, pinnedThread, perEntity);
    }

    private ulong RegisterSystemEntry(string name, RuntimePhase phase, SystemEntry entry,
                                       IReadOnlyList<QueryDecl>? queries,
                                       IReadOnlyList<ComponentAccess>? accessList,
                                       uint pinnedThread,
                                       bool perEntity)
    {
        ArgumentException.ThrowIfNullOrEmpty(name);

        var handle = GCHandle.Alloc(entry);
        _systemHandles.Add(handle);

        var queryCount = queries?.Count ?? 0;
        var accessCount = accessList?.Count ?? 0;

        var nativeQueries = new ke_query_decl[Math.Max(queryCount, 1)];
        for (var q = 0; q < queryCount; q++)
        {
            var terms = queries![q].Terms ?? [];
            if (terms.Length > QueryDecl.MaxTerms)
                throw new ArgumentException(
                    $"Query {q} of system '{name}' declares {terms.Length} terms; the ABI allows {QueryDecl.MaxTerms}.",
                    nameof(queries));
            for (var t = 0; t < terms.Length; t++)
            {
                nativeQueries[q].terms[t].cid = terms[t].Cid;
                nativeQueries[q].terms[t].access = (ke_access)terms[t].Access;
            }
            nativeQueries[q].term_count = (uint)terms.Length;
        }

        var nativeAccess = new ke_component_access[Math.Max(accessCount, 1)];
        for (var a = 0; a < accessCount; a++)
        {
            nativeAccess[a].cid = accessList![a].Cid;
            nativeAccess[a].access = (ke_access)accessList[a].Access;
        }

        var nameBytes = System.Text.Encoding.UTF8.GetBytes(name + "\0");
        fixed (byte* namePtr = nameBytes)
        fixed (ke_query_decl* queryPtr = nativeQueries)
        fixed (ke_component_access* accessPtr = nativeAccess)
        {
            ke_runtime_system_params p = default;
            p.name           = (sbyte*)namePtr;
            p.phase          = (ke_phase)phase;
            p.pinned_thread  = pinnedThread;
            p.per_entity     = perEntity;
            p.user_data      = (void*)GCHandle.ToIntPtr(handle);
            p.execute        = &SystemExecuteTrampoline;
            p.queries        = queryCount > 0 ? queryPtr : null;
            p.query_count    = (uint)queryCount;
            p.access_list    = accessCount > 0 ? accessPtr : null;
            p.access_count   = (uint)accessCount;

            return RegisterSystem(&p);
        }
    }

    /// <inheritdoc />
    public void Tick(float dt)
    {
        TickNative(dt);
        DrainSystemFailures();
    }

    /// <inheritdoc />
    public void Flush()
    {
        FlushRender();
        DrainSystemFailures();
    }

    partial void OnDispose()
    {
        foreach (var h in _moduleHandles) if (h.IsAllocated) h.Free();
        _moduleHandles.Clear();
        foreach (var h in _systemHandles) if (h.IsAllocated) h.Free();
        _systemHandles.Clear();
    }
}
