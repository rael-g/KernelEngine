using System.Text;

namespace KernelEngine.Framework;

/// <summary>
/// Maps the names a <c>.scene.toml</c> file uses to the managed <see cref="Type"/>s
/// <see cref="SceneLoader"/> instantiates. Built at startup via
/// <c>services.AddNodeType&lt;T&gt;()</c>.
/// </summary>
public sealed class NodeTypeRegistry
{
    private readonly Dictionary<string, Type> _qualified = new(StringComparer.Ordinal);
    private readonly Dictionary<string, List<Type>> _short = new(StringComparer.Ordinal);

    /// <summary>
    /// Registers <typeparamref name="T"/> under <paramref name="name"/>, or under the
    /// normalized form of its full name when none is given.
    /// </summary>
    /// <exception cref="InvalidOperationException">
    /// Another type already claims the same qualified name.
    /// </exception>
    public NodeTypeRegistry Register<T>(string? name = null) where T : Node
    {
        var qualified = name is null ? Normalize(typeof(T).FullName!) : Normalize(name);
        if (_qualified.TryGetValue(qualified, out var taken) && taken != typeof(T))
            throw new InvalidOperationException(
                $"Node type '{qualified}' is claimed by both {taken.FullName} and {typeof(T).FullName}. " +
                "A qualified name identifies one type; rename one of them.");
        _qualified[qualified] = typeof(T);

        var shortName = Normalize(typeof(T).Name);
        if (!_short.TryGetValue(shortName, out var candidates))
            _short[shortName] = candidates = [];
        if (!candidates.Contains(typeof(T))) candidates.Add(typeof(T));
        return this;
    }

    /// <summary>Resolves a name a scene file wrote to the type it names.</summary>
    /// <exception cref="InvalidOperationException">
    /// The name is unknown, or it is a short name more than one registered type answers to.
    /// </exception>
    public Type Resolve(string name)
    {
        var key = Normalize(name);
        if (_qualified.TryGetValue(key, out var exact)) return exact;

        if (_short.TryGetValue(key, out var candidates))
        {
            if (candidates.Count == 1) return candidates[0];
            throw new InvalidOperationException(
                $"Scene references node type '{name}', which is ambiguous between " +
                string.Join(" and ", candidates.Select(t => Normalize(t.FullName!))) +
                ". Write the qualified name.");
        }

        throw new InvalidOperationException(
            $"Scene references node type '{name}' but it is not registered. " +
            $"Call services.AddNodeType<{name}>() during startup.");
    }

    /// <summary>
    /// The one spelling of a node type name: snake_case, dots between namespace parts.
    /// </summary>
    public static string Normalize(string name)
    {
        var sb = new StringBuilder(name.Length + 4);
        for (var i = 0; i < name.Length; i++)
        {
            var ch = name[i];
            if (ch == '+') { sb.Append('.'); continue; }
            if (char.IsUpper(ch))
            {
                var prev = i > 0 ? name[i - 1] : '.';
                var startsWord = prev != '.' && prev != '_' && !char.IsDigit(prev)
                    && (!char.IsUpper(prev) || (i + 1 < name.Length && char.IsLower(name[i + 1])));
                if (startsWord) sb.Append('_');
                sb.Append(char.ToLowerInvariant(ch));
            }
            else sb.Append(ch);
        }
        return sb.ToString();
    }
}
