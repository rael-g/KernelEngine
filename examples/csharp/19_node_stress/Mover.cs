using KernelEngine.Framework;

namespace NodeStress;

/// <summary>
/// How much arithmetic one instance does per tick. High enough that the measurement
/// is about the work rather than about the loop around it — a body that did nothing
/// would time the dispatch and call it the workload.
/// </summary>
public static class Workload
{
    /// <summary>Iterations one instance runs per tick.</summary>
    public const int StepsPerTick = 256;
}

/// <summary>
/// A node whose behaviour touches nothing but its own two values, which is what lets
/// the runtime run its instances as concurrent slices. Its counterpart
/// <see cref="Anchored"/> does the same arithmetic while declaring a borrow, so the
/// two differ in what they promise and in nothing else.
/// </summary>
public sealed partial class Mover : Node
{
    /// <summary>Position along the one axis this node moves on.</summary>
    public partial float Value { get; set; }

    /// <summary>How fast it moves, authored per instance so the instances differ.</summary>
    public partial float Rate { get; set; }

    void Update(in View view)
    {
        var v = Value;
        var step = Rate * view.DeltaTime;
        for (int i = 0; i < Workload.StepsPerTick; i++)
            v = v * 0.9999f + step;
        Value = v;
    }
}
