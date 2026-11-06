using System.Runtime.InteropServices;

namespace KernelEngine.Framework;

/// <summary>
/// Holds the scene requested by <see cref="LoadScene(string)"/> until <c>Flush</c> records its
/// load: the flush destroys every node and records into the system's commands the load of
/// <c>scenes/&lt;name&gt;.scene.toml</c> from the application base directory, then the calls to
/// <c>OnReady</c> on the nodes and the naming of <see cref="CurrentScene"/>. Both run when the
/// commands apply, the load first, so each node is built from its code before its scene section
/// is written over it. Only the latest request before a flush is kept. A failing load fails the
/// application of the commands and leaves <see cref="CurrentScene"/> unchanged.
/// </summary>
internal sealed unsafe class SceneRouter : ISceneRouter, IDisposable
{
    private readonly ScriptHost _scriptHost;
    private readonly SceneLoader _loader;
    private readonly GCHandle _self;

    private string? _pendingLoad;
    private string? _loading;

    public string? CurrentScene { get; private set; }

    public SceneRouter(ScriptHost scriptHost, SceneLoader loader)
    {
        _scriptHost = scriptHost;
        _loader = loader;
        _self = GCHandle.Alloc(this);
    }

    public void LoadScene(string name) => _pendingLoad = name;

    internal void Flush(KernelEngine.Ecs.EcsCommands commands)
    {
        var name = Interlocked.Exchange(ref _pendingLoad, null);
        if (name is null) return;

        _scriptHost.Clear();
        var path = Path.Combine(AppContext.BaseDirectory, "scenes", $"{name}.scene.toml");
        _loader.Instantiate(path, default, commands);
        _loading = name;
        commands.Defer((nint)(delegate* unmanaged[Cdecl]<KernelEngine.Ecs.Native.ke_ecs*, void*, KernelEngine.Result.Native.Result>)&Loaded,
            GCHandle.ToIntPtr(_self));
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static KernelEngine.Result.Native.Result Loaded(KernelEngine.Ecs.Native.ke_ecs* ecs, void* user)
    {
        try
        {
            var router = (SceneRouter)GCHandle.FromIntPtr(*(nint*)user).Target!;
            router._scriptHost.TriggerReady();
            router.CurrentScene = router._loading;
            return KernelEngine.Result.Native.Result.Ok;
        }
        catch (Exception)
        {
            return KernelEngine.Result.Native.Result.General;
        }
    }

    public void Dispose()
    {
        if (_self.IsAllocated) _self.Free();
    }
}
