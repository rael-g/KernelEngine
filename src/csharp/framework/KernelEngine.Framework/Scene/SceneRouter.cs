namespace KernelEngine.Framework;

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
