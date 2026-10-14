namespace KernelEngine.Framework;

/// <summary>
/// Holds the scene requested by <see cref="LoadScene(string)"/> until <c>Flush</c> loads it: the
/// flush destroys every node, loads <c>scenes/&lt;name&gt;.scene.toml</c> from the application
/// base directory with the <see cref="SceneLoader"/>, calls <c>OnReady</c> on the nodes and
/// records the name as <see cref="CurrentScene"/>. Only the latest request before a flush is
/// kept. A failing load propagates its exception from <c>Flush</c> and leaves
/// <see cref="CurrentScene"/> unchanged.
/// </summary>
internal sealed class SceneRouter : ISceneRouter
{
    private readonly ScriptHost          _scriptHost;
    private readonly SceneLoader  _loader;

    private string? _pendingLoad;

    public string? CurrentScene { get; private set; }

    public SceneRouter(ScriptHost scriptHost, SceneLoader loader)
    {
        _scriptHost = scriptHost;
        _loader    = loader;
    }

    public void LoadScene(string name) => _pendingLoad = name;

    internal void Flush()
    {
        var name = Interlocked.Exchange(ref _pendingLoad, null);
        if (name is null) return;

        _scriptHost.Clear();
        var path = Path.Combine(AppContext.BaseDirectory, "scenes", $"{name}.scene.toml");
        _loader.Load(path);
        _scriptHost.TriggerReady();
        CurrentScene = name;
    }
}
