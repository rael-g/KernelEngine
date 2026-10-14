namespace KernelEngine.Common;

/// <summary>
/// The managed convenience members of <see cref="Transform"/>; its fields are generated from
/// <c>ke_transform</c>.
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
