using System.Collections.Concurrent;
using System.Text;

namespace KernelEngine.Framework;

/// <summary>
/// What each node type declares about itself, filled by the generated code of the type before
/// any instance exists: whether its behavior reaches only its own entity, and the components it
/// reaches. A type that declares nothing takes what its nearest declaring base type declares.
/// </summary>
public static class NodeTypes
{
    private static readonly ConcurrentDictionary<Type, (bool? ReachesOnlyItself, NodeComponentUse[] Uses)> s_declared = new();
    private static readonly ConcurrentDictionary<Type, Action<ComponentRegistry, KernelEngine.Ecs.INativeEcs>> s_registrations = new();

    /// <summary>
    /// Records what <paramref name="type"/> declares: <paramref name="reachesOnlyItself"/>, or
    /// null to take its base type's answer, and the components it adds to those of its base types.
    /// </summary>
    /// <param name="type">The node type.</param>
    /// <param name="reachesOnlyItself">Whether its behavior touches only its own entity, or null for its base type's answer.</param>
    /// <param name="uses">The components it adds to those of its base types.</param>
    /// <param name="registerComponent">Registers the component the type itself declares and the scene apply of it, or null when it declares none.</param>
    public static void Declare(Type type, bool? reachesOnlyItself, NodeComponentUse[] uses,
        Action<ComponentRegistry, KernelEngine.Ecs.INativeEcs>? registerComponent = null)
    {
        s_declared[type] = (reachesOnlyItself, uses);
        if (registerComponent is not null) s_registrations[type] = registerComponent;
    }

    /// <summary>
    /// Registers with <paramref name="registry"/> and <paramref name="ecs"/> the component each type
    /// of the chain of <paramref name="type"/> declares, its base types' first, skipping a type
    /// already in <paramref name="registered"/> and adding each one it registers.
    /// </summary>
    public static void RegisterComponents(Type type, ComponentRegistry registry, KernelEngine.Ecs.INativeEcs ecs, ISet<Type> registered)
    {
        var chain = new Stack<Type>();
        for (var t = type; t is not null; t = t.BaseType) chain.Push(t);
        foreach (var t in chain)
            if (s_registrations.TryGetValue(t, out var register) && registered.Add(t)) register(registry, ecs);
    }

    /// <summary>Whether the behavior of <paramref name="type"/> touches nothing beyond its own entity; false when no type of its chain says.</summary>
    public static bool ReachesOnlyItself(Type type)
    {
        for (var t = type; t is not null; t = t.BaseType)
            if (s_declared.TryGetValue(t, out var d) && d.ReachesOnlyItself is { } reaches) return reaches;
        return false;
    }

    /// <summary>Appends the components <paramref name="type"/> reaches, its base types' first.</summary>
    public static void CollectComponents(Type type, List<NodeComponentUse> into)
    {
        var chain = new Stack<Type>();
        for (var t = type; t is not null; t = t.BaseType) chain.Push(t);
        foreach (var t in chain)
            if (s_declared.TryGetValue(t, out var d)) into.AddRange(d.Uses);
    }

    /// <summary>
    /// The spelling of a CLR type name in a scene file: snake case, with a dot for each nesting.
    /// The native scene loader applies the same rule to the type name it hands to the script
    /// factory. Only ASCII letters change case; any other character is kept as written.
    /// </summary>
    public static string NameOf(string clrName)
    {
        var sb = new StringBuilder(clrName.Length + 4);
        for (var i = 0; i < clrName.Length; i++)
        {
            var ch = clrName[i];
            if (ch == '+') { sb.Append('.'); continue; }
            if (char.IsAsciiLetterUpper(ch))
            {
                var rawPrev = i > 0 ? clrName[i - 1] : '.';
                var prev = rawPrev == '+' ? '.' : rawPrev;
                var startsWord = prev != '.' && prev != '_' && !char.IsAsciiDigit(prev)
                    && (!char.IsAsciiLetterUpper(prev) || (i + 1 < clrName.Length && char.IsAsciiLetterLower(clrName[i + 1])));
                if (startsWord) sb.Append('_');
                sb.Append(char.ToLowerInvariant(ch));
            }
            else sb.Append(ch);
        }
        return sb.ToString();
    }
}
