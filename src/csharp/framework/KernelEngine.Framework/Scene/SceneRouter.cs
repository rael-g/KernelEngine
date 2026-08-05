namespace KernelEngine.Framework;

internal sealed class SceneRouter : ISceneRouter
{
    private readonly NodeWorld          _nodeWorld;
    private readonly SceneLoader  _loader;

    private string? _pendingLoad;

    public string? CurrentScene { get; private set; }

    public SceneRouter(NodeWorld nodeWorld, SceneLoader loader)
    {
        _nodeWorld = nodeWorld;
        _loader    = loader;
    }

    public void LoadScene(string name) => _pendingLoad = name;

    internal void Flush()
    {
        var name = Interlocked.Exchange(ref _pendingLoad, null);
        if (name is null) return;

        _nodeWorld.Clear();
        var path = Path.Combine(AppContext.BaseDirectory, "scenes", $"{name}.scene");
        _loader.Load(path);
        _nodeWorld.TriggerReady();
        CurrentScene = name;
    }
}
