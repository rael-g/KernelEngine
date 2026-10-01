using KernelEngine.Framework;

namespace NodeStress;

/// <summary>
/// The same arithmetic <see cref="Mover"/> does, on a node that borrows another one.
/// The borrow is what makes the difference measurable: a type whose signature reaches
/// beyond its own entity cannot be run as concurrent slices, so timing the two side by
/// side prices the promise rather than asserting it.
/// </summary>
public sealed partial class Anchored : Node
{
    /// <summary>Position along the one axis this node moves on.</summary>
    public partial float Value { get; set; }

    /// <summary>How fast it moves, authored per instance so the instances differ.</summary>
    public partial float Rate { get; set; }

    void Update(in View view, Descendant<Mover> unused)
    {
        var v = Value;
        var step = Rate * view.DeltaTime;
        for (int i = 0; i < Workload.StepsPerTick; i++)
            v = v * 0.9999f + step;
        Value = v;
    }
}
