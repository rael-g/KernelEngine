using KernelEngine.Framework;

namespace NodeStress;

/// <summary>Raised by <see cref="Coupled"/> once its value crosses the threshold.</summary>
public struct Crossed
{
    /// <summary>The value at the moment of the crossing.</summary>
    public float Value;
}

/// <summary>
/// A node whose borrow actually resolves, and which emits a signal its child handles.
/// Exists so the paths a windowed game exercises — a named borrow that finds its node,
/// a signal that reaches a handler — are reachable from a headless run, where they can
/// be asserted instead of watched.
/// </summary>
public sealed partial class Coupled : Node
{
    /// <summary>Position along the one axis this node moves on.</summary>
    public partial float Value { get; set; }

    /// <summary>How fast it moves, authored per instance so the instances differ.</summary>
    public partial float Rate { get; set; }

    /// <summary>Value the node emits <see cref="Crossed"/> at.</summary>
    public partial float Threshold { get; set; }

    void Update(in View view, [NodeName("Echo")] Descendant<Echo> echo, Emit<Crossed> crossed)
    {
        var v = Value;
        var step = Rate * view.DeltaTime;
        for (int i = 0; i < Workload.StepsPerTick; i++)
            v = v * 0.9999f + step;
        Value = v;

        echo.Node?.Note(v);
        if (v >= Threshold) crossed.Send(new Crossed { Value = v });
    }
}

/// <summary>
/// The child <see cref="Coupled"/> borrows and signals. Counts what reaches it, so a
/// borrow that silently stops resolving shows up as a count of zero rather than as
/// nothing at all.
/// </summary>
public sealed partial class Echo : Node
{
    /// <summary>Last value handed over by the parent's borrow.</summary>
    public partial float Last { get; set; }

    /// <summary>How many times the borrow reached this node.</summary>
    public partial int Notes { get; set; }

    /// <summary>How many times the parent's signal was delivered here.</summary>
    public partial int Signals { get; set; }

    internal void Note(float value)
    {
        Last = value;
        Notes++;
    }

    void On(in Crossed crossed) => Signals++;
}
