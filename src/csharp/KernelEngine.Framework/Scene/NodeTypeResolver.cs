namespace KernelEngine.Framework;

/// <summary>
/// Resolves a C# <see cref="Node"/> subclass by name. The script factory in
/// <see cref="SceneLoader"/> calls this for every <c>[entity.script] type = "..."</c>
/// block. Three-step lookup: short name prefixed with <c>KernelEngine.Framework</c>,
/// direct fully-qualified <see cref="System.Type.GetType(string)"/>, then a scan of
/// every loaded assembly. Returns <c>null</c> if no matching <see cref="Node"/>
/// subclass is found — the loader treats that as a quiet skip.
/// </summary>
public static class NodeTypeResolver
{
    public static System.Type? Resolve(string typeName)
    {
        if (string.IsNullOrEmpty(typeName)) return null;

        if (!typeName.Contains('.'))
        {
            var t = System.Type.GetType($"KernelEngine.Framework.{typeName}, KernelEngine.Framework");
            if (t != null && typeof(Node).IsAssignableFrom(t)) return t;
        }

        var direct = System.Type.GetType(typeName);
        if (direct != null && typeof(Node).IsAssignableFrom(direct)) return direct;

        foreach (var asm in System.AppDomain.CurrentDomain.GetAssemblies())
        {
            var t = asm.GetType(typeName);
            if (t != null && typeof(Node).IsAssignableFrom(t)) return t;
        }
        return null;
    }
}
