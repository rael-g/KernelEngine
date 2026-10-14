namespace KernelEngine.Framework;

/// <summary>
/// Reports the current scene and requests a change to another one.
/// </summary>
public interface ISceneRouter
{
    /// <summary>
    /// The scene currently loaded, or <see langword="null"/> before the first load.
    /// </summary>
    string? CurrentScene { get; }

    /// <summary>
    /// Requests a transition to the scene named <paramref name="name"/>. The transition happens
    /// at the next pre-update flush, not during this call.
    /// </summary>
    void LoadScene(string name);

    /// <summary>
    /// Requests a transition to the scene <typeparamref name="TScene"/> names, as
    /// <see cref="LoadScene(string)"/> does.
    /// </summary>
    void LoadScene<TScene>() where TScene : IScene => LoadScene(TScene.SceneName);
}

/// <summary>
/// Implemented by the type generated for each <c>.scene.toml</c> file in a project.
/// </summary>
public interface IScene
{
    /// <summary>The scene's file name without its <c>.scene.toml</c> extension.</summary>
    static abstract string SceneName { get; }
}
