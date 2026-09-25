using KernelEngine.Ecs;
using KernelEngine.Ecs.Native;
using KernelEngine.Scheduler;
using KernelEngine.Scheduler.Native;

namespace KernelEngine.Runtime;

/// <summary>
/// The parts of <see cref="Runtime"/> that are not a direct image of the C ABI: a
/// system is registered against queries described by managed records, which have to be
/// laid out as the ABI's own structs before the call can take them, and a body written
/// against the managed surface is handed the runtime rather than the raw context
/// pointer. Everything mirroring the vtable 1:1 is generated in
/// <c>Generated/Runtime.g.cs</c>.
/// </summary>
public sealed unsafe partial class Runtime : IRuntime
{
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
        return taskScheduler.Native;
    }

    /// <inheritdoc />
    ulong IRuntime.RegisterModule(string name, Action<IRuntime> onLoad, Action<IRuntime>? onUnload = null)
    {
        ArgumentException.ThrowIfNullOrEmpty(name);
        ArgumentNullException.ThrowIfNull(onLoad);

        return RegisterModule(name, rt => onLoad(rt),
            onUnload is null ? null : rt => onUnload(rt));
    }

    /// <inheritdoc />
    ulong IRuntime.RegisterSystem(string name, RuntimePhase phase, Action<IRuntime, float> execute,
                                 IReadOnlyList<QueryDecl>? queries = null,
                                 IReadOnlyList<ComponentAccess>? accessList = null,
                                 uint pinnedThread = 0,
                                 bool perEntity = false)
    {
        ArgumentNullException.ThrowIfNull(execute);
        return RegisterSystemDeclared(name, phase, (_, dt) => execute(this, dt),
                               queries, accessList, pinnedThread, perEntity);
    }

    /// <inheritdoc />
    ulong IRuntime.RegisterSystem(string name, RuntimePhase phase, Action<IRuntime, nint, float> execute,
                                 IReadOnlyList<QueryDecl>? queries = null,
                                 IReadOnlyList<ComponentAccess>? accessList = null,
                                 uint pinnedThread = 0,
                                 bool perEntity = false)
    {
        ArgumentNullException.ThrowIfNull(execute);
        return RegisterSystemDeclared(name, phase, (ctx, dt) => execute(this, ctx, dt),
                               queries, accessList, pinnedThread, perEntity);
    }

    private ulong RegisterSystemDeclared(string name, RuntimePhase phase, SystemExecute execute,
                                  IReadOnlyList<QueryDecl>? queries,
                                  IReadOnlyList<ComponentAccess>? accessList,
                                  uint pinnedThread,
                                  bool perEntity)
    {
        ArgumentException.ThrowIfNullOrEmpty(name);

        var nativeQueries = new ke_query_decl[queries?.Count ?? 0];
        for (var q = 0; q < nativeQueries.Length; q++)
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

        var nativeAccess = new ke_component_access[accessList?.Count ?? 0];
        for (var a = 0; a < nativeAccess.Length; a++)
        {
            nativeAccess[a].cid = accessList![a].Cid;
            nativeAccess[a].access = (ke_access)accessList[a].Access;
        }

        return RegisterSystemRaw(name, phase, nativeQueries, nativeAccess, pinnedThread, perEntity, execute);
    }
}
