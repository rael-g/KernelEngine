namespace KernelEngine.Framework;

internal sealed class SceneRouter : ISceneRouter
{
    private readonly Tree             _tree;
    private readonly SceneLoader      _loader;
    private readonly IServiceProvider _services;

    private string? _pendingLoad;

    public string? CurrentScene { get; private set; }

    public SceneRouter(Tree tree, SceneLoader loader, IServiceProvider services)
    {
        _tree     = tree;
        _loader   = loader;
        _services = services;
    }

    public void LoadScene(string name) => _pendingLoad = name;

    internal void Flush()
    {
        var name = Interlocked.Exchange(ref _pendingLoad, null);
        if (name is null) return;

        _tree.Clear();
        var path = Path.Combine(AppContext.BaseDirectory, "scenes", $"{name}.scene");
        _loader.LoadInto(_tree, _services, path);
        CurrentScene = name;
    }
}
