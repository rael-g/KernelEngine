using KernelEngine.Framework.Nodes;

namespace NodeStress;

/// <summary>The work each node does per tick, so a tick costs more than the dispatch around it.</summary>
static class Workload
{
    /// <summary>Iterations of the update's arithmetic per node per tick.</summary>
    public const int StepsPerTick = 256;
}

/// <summary>A value raised past a node's threshold.</summary>
struct Crossed
{
    public float Value;
}

/// <summary>A node that only works on its own fields.</summary>
[NodeType("stress.mover")]
partial class Mover : Node
{
    /// <summary>The value the update advances.</summary>
    public partial float Value { get; set; }

    /// <summary>How fast the value advances.</summary>
    [Export] public partial float Rate { get; set; }

    void Born() => Rate = 1.0f;

    void Update()
    {
        var v = Value;
        var step = Rate * Dt;
        for (var i = 0; i < Workload.StepsPerTick; i++) v = v * 0.9999f + step;
        Value = v;
    }
}

/// <summary>A node that raises an event each time its value passes its threshold.</summary>
[NodeType("stress.raiser")]
partial class Raiser : Node
{
    /// <summary>The value the update advances.</summary>
    public partial float Value { get; set; }

    void Born() => Value = 0.0f;

    void Update()
    {
        Value += Dt;
        if (Value < 1.0f / 30.0f) return;
        Raise(new Crossed { Value = Value });
        Value = 0.0f;
    }
}

/// <summary>A node that counts the events every raiser raises.</summary>
[NodeType("stress.listener")]
partial class Listener : Node
{
    /// <summary>Events every listener received, across nodes.</summary>
    public static long Heard;

    [On<Crossed>]
    void OnCrossed(Crossed crossed) => Interlocked.Increment(ref Heard);
}
