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

    /// <summary>
    /// Records what <paramref name="type"/> declares: <paramref name="reachesOnlyItself"/>, or
    /// null to take its base type's answer, and the components it adds to those of its base types.
    /// </summary>
    public static void Declare(Type type, bool? reachesOnlyItself, NodeComponentUse[] uses) =>
        s_declared[type] = (reachesOnlyItself, uses);

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
