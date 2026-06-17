namespace KernelEngine.Cli;

/// <summary>
/// DAG sort for module ordering. Output preserves declaration order among independent modules
/// (Kahn's algorithm) — so a user adding A then B (with A and B not depending on each other)
/// sees them appear in the generated Program.cs in the order they added them.
/// </summary>
internal static class TopologicalSort
{
    public static List<ModuleSpec> Sort(IEnumerable<ModuleSpec> modules, ModuleCatalog catalog)
    {
        var input = modules.ToList();
        var remaining = input.Select(m => m.Id).ToHashSet(StringComparer.Ordinal);

        // Build edges: edge from dep → m means dep must come first.
        var inDegree = input.ToDictionary(m => m.Id, _ => 0, StringComparer.Ordinal);
        var dependents = new Dictionary<string, List<string>>(StringComparer.Ordinal);

        foreach (var m in input)
        {
            foreach (var dep in m.DependsOn)
            {
                if (!remaining.Contains(dep)) continue; // dep not in manifest — treated as satisfied
                if (!dependents.TryGetValue(dep, out var list))
                    dependents[dep] = list = new List<string>();
                list.Add(m.Id);
                inDegree[m.Id]++;
            }
        }

        // Walk input in original order; pick the first one with zero in-degree, emit it, repeat.
        var ordered = new List<ModuleSpec>(input.Count);
        var remainingList = new List<ModuleSpec>(input);

        while (remainingList.Count > 0)
        {
            var pickIndex = remainingList.FindIndex(m => inDegree[m.Id] == 0);
            if (pickIndex < 0)
            {
                var cycle = string.Join(", ", remainingList.Select(m => m.Id));
                throw new InvalidOperationException($"Dependency cycle among modules: {cycle}.");
            }
            var picked = remainingList[pickIndex];
            remainingList.RemoveAt(pickIndex);
            ordered.Add(picked);
            if (dependents.TryGetValue(picked.Id, out var ds))
                foreach (var d in ds) inDegree[d]--;
        }

        return ordered;
    }
}
