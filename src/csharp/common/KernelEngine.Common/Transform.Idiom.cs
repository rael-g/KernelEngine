namespace KernelEngine.Common;

/// <summary>
/// The convenience <see cref="Transform"/> affords a managed caller. The fields themselves
/// are generated from <c>ke_transform</c>; this adds only what has no counterpart in C,
/// where the same value is written out as an initialiser at the point of use.
/// </summary>
public partial struct Transform
{
    /// <summary>No translation, no rotation, unit scale.</summary>
    public static readonly Transform Identity = new()
    {
        Position = System.Numerics.Vector3.Zero,
        Rotation = System.Numerics.Quaternion.Identity,
        Scale = System.Numerics.Vector3.One,
    };
}
