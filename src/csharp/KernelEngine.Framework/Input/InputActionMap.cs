using KernelEngine.Kernel;
using Tomlyn;
using Tomlyn.Model;

namespace KernelEngine.Framework;

/// <summary>
/// Reflection-built <see cref="IInputActionMap{TEnum}"/> backed by a TOML
/// document. Loaded once at startup; immutable afterward.
/// </summary>
/// <remarks>
/// TOML schema (subset of the legacy framework's format):
/// <code>
/// [action.PaddleLeftMove]
/// type = "Axis1D"             # optional, informational only
/// bindings = [
///     { kind = "key_pair", negative = "S", positive = "W" },
/// ]
///
/// [action.Launch]
/// type = "Button"
/// bindings = [
///     { kind = "key", key = "Space" },
/// ]
/// </code>
/// Unknown action names (no matching enum member) are ignored — forward-
/// compat for files that target a newer enum.
/// </remarks>
public sealed class InputActionMap<TEnum> : IInputActionMap<TEnum> where TEnum : struct, Enum
{
    private enum BindingKind { Key, KeyPair }

    private readonly struct Binding
    {
        public readonly BindingKind Kind;
        public readonly int         KeyPositive;
        public readonly int         KeyNegative;

        public Binding(BindingKind kind, int pos, int neg)
        {
            Kind        = kind;
            KeyPositive = pos;
            KeyNegative = neg;
        }
    }

    private readonly Dictionary<TEnum, List<Binding>> _bindings = new();

    public static InputActionMap<TEnum> LoadFromFile(string path)
    {
        if (!File.Exists(path))
            throw new FileNotFoundException(
                $"Input actions file not found: {path}", path);
        var text = File.ReadAllText(path);
        return LoadFromText(text);
    }

    public static InputActionMap<TEnum> LoadFromText(string toml)
    {
        var map = new InputActionMap<TEnum>();
        var doc = Toml.ToModel(toml);

        if (!doc.TryGetValue("action", out var actionSectionRaw) || actionSectionRaw is not TomlTable actions)
            return map;

        foreach (var (actionName, actionEntry) in actions)
        {
            if (!Enum.TryParse<TEnum>(actionName, ignoreCase: true, out var enumValue))
                continue;
            if (actionEntry is not TomlTable actionTable) continue;
            if (!actionTable.TryGetValue("bindings", out var bindingsRaw)) continue;
            if (bindingsRaw is not TomlArray bindings) continue;

            var list = new List<Binding>(bindings.Count);
            foreach (var bindingObj in bindings)
            {
                if (bindingObj is not TomlTable binding) continue;
                var kind = binding.TryGetValue("kind", out var k) ? k as string : null;
                switch (kind)
                {
                    case "key":
                        if (binding.TryGetValue("key", out var keyObj) && keyObj is string keyName
                            && Enum.TryParse<Key>(keyName, ignoreCase: true, out var key))
                        {
                            list.Add(new Binding(BindingKind.Key, (int)key, 0));
                        }
                        break;
                    case "key_pair":
                        var pos = binding.TryGetValue("positive", out var p) ? p as string : null;
                        var neg = binding.TryGetValue("negative", out var n) ? n as string : null;
                        if (pos is not null && neg is not null
                            && Enum.TryParse<Key>(pos, ignoreCase: true, out var posKey)
                            && Enum.TryParse<Key>(neg, ignoreCase: true, out var negKey))
                        {
                            list.Add(new Binding(BindingKind.KeyPair, (int)posKey, (int)negKey));
                        }
                        break;
                }
            }
            map._bindings[enumValue] = list;
        }

        return map;
    }

    public float GetAxis1D(TEnum action, in View view)
    {
        if (!_bindings.TryGetValue(action, out var list)) return 0f;
        float total = 0f;
        for (int i = 0; i < list.Count; i++)
        {
            var b = list[i];
            if (b.Kind != BindingKind.KeyPair) continue;
            if (view.IsKeyDown(b.KeyPositive)) total += 1f;
            if (view.IsKeyDown(b.KeyNegative)) total -= 1f;
        }
        return Math.Clamp(total, -1f, 1f);
    }

    public bool IsPressed(TEnum action, in View view)
    {
        if (!_bindings.TryGetValue(action, out var list)) return false;
        for (int i = 0; i < list.Count; i++)
        {
            var b = list[i];
            if (view.IsKeyDown(b.KeyPositive)) return true;
        }
        return false;
    }
}
