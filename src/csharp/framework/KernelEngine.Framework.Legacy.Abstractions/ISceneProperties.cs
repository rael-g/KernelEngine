using System.Numerics;

namespace KernelEngine.Framework.Legacy;

/// <summary>
/// Read-only view over an entity's <c>scene_properties</c> bag — the generic key/value map the
/// SceneLoader writes from <c>[entity.properties]</c> blocks (option C of the ECS-pure-nodes
/// refactor, plan §5b). Node subclasses pull their scene-authored values via
/// <see cref="GetString"/> / <see cref="GetFloat"/> / etc. inside <see cref="Node.Start"/>.
/// </summary>
/// <remarks>
/// The default implementation lives in <c>KernelEngine.Framework.Legacy.Native</c> and decodes the
/// native <c>ke_scene_properties</c> component on demand. Game code never touches the variant
/// pointers directly — only this interface.
/// </remarks>
public interface ISceneProperties
{
    /// <summary>True when this entity has no <c>scene_properties</c> bag attached.</summary>
    bool IsEmpty { get; }

    bool    TryGetString (string key, out string value);
    bool    TryGetFloat  (string key, out float  value);
    bool    TryGetInt    (string key, out long   value);
    bool    TryGetBool   (string key, out bool   value);
    bool    TryGetVector2(string key, out Vector2 value);
    bool    TryGetVector3(string key, out Vector3 value);
    bool    TryGetVector4(string key, out Vector4 value);

    string  GetString (string key, string  fallback = "");
    float   GetFloat  (string key, float   fallback = 0f);
    long    GetInt    (string key, long    fallback = 0);
    bool    GetBool   (string key, bool    fallback = false);
    Vector2 GetVector2(string key, Vector2 fallback = default);
    Vector3 GetVector3(string key, Vector3 fallback = default);
    Vector4 GetVector4(string key, Vector4 fallback = default);
}

/// <summary>Empty-bag singleton used when an entity has no <c>scene_properties</c> attached.</summary>
public sealed class EmptySceneProperties : ISceneProperties
{
    public static readonly EmptySceneProperties Instance = new();
    private EmptySceneProperties() { }

    public bool IsEmpty => true;

    public bool TryGetString (string key, out string  value) { value = ""; return false; }
    public bool TryGetFloat  (string key, out float   value) { value = 0; return false; }
    public bool TryGetInt    (string key, out long    value) { value = 0; return false; }
    public bool TryGetBool   (string key, out bool    value) { value = false; return false; }
    public bool TryGetVector2(string key, out Vector2 value) { value = default; return false; }
    public bool TryGetVector3(string key, out Vector3 value) { value = default; return false; }
    public bool TryGetVector4(string key, out Vector4 value) { value = default; return false; }

    public string  GetString (string key, string  fallback = "")      => fallback;
    public float   GetFloat  (string key, float   fallback = 0f)      => fallback;
    public long    GetInt    (string key, long    fallback = 0)       => fallback;
    public bool    GetBool   (string key, bool    fallback = false)   => fallback;
    public Vector2 GetVector2(string key, Vector2 fallback = default) => fallback;
    public Vector3 GetVector3(string key, Vector3 fallback = default) => fallback;
    public Vector4 GetVector4(string key, Vector4 fallback = default) => fallback;
}
