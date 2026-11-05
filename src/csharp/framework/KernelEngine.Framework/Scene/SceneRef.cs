namespace KernelEngine.Framework;

/// <summary>
/// A scene file a node names in one of its fields, the way a scene writes it
/// (<c>hit_sound = "res://scenes/HitSound.scene.toml"</c>), held by the node it belongs to.
/// </summary>
/// <param name="Owner">The node whose field holds the reference; what <see cref="Spawn"/> creates goes under it.</param>
/// <param name="Path">The path the scene wrote; empty when the field was not written.</param>
public readonly record struct SceneRef(Node? Owner, string Path)
{
    /// <summary>A reference to <paramref name="path"/> owned by no node, for assigning to a field.</summary>
    public static implicit operator SceneRef(string path) => new(null, path);

    /// <summary>
    /// Creates the nodes the scene file describes under <see cref="Owner"/>, when the system this
    /// runs in reaches its barrier.
    /// </summary>
    /// <exception cref="InvalidOperationException">The reference names no scene, belongs to no
    /// bound node, or this runs outside a system.</exception>
    public void Spawn()
    {
        if (string.IsNullOrEmpty(Path)) throw new InvalidOperationException("the scene reference names no scene");
        if (Owner is not { Host: { } host } owner)
            throw new InvalidOperationException($"the scene reference '{Path}' belongs to no bound node");
        host.Instantiate(Path, owner);
    }
}
