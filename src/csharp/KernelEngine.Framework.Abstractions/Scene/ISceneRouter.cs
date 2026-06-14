namespace KernelEngine.Framework;

/// <summary>
/// Allows game code to query and navigate between named scenes without depending
/// on the concrete <c>SceneRouter</c> or Toolkit types.
/// </summary>
public interface ISceneRouter
{
    /// <summary>The scene currently loaded, or <see langword="null"/> before the first load.</summary>
    string? CurrentScene { get; }

    /// <summary>
    /// Schedules a transition to the scene registered as <paramref name="name"/>.
    /// The transition is deferred to the next frame boundary to avoid mutating
    /// the scene graph while it is being iterated.
    /// </summary>
    void LoadScene(string name);
}
