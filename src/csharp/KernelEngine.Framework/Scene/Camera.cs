namespace KernelEngine.Framework;

/// <summary>
/// Camera node. Init properties set perspective parameters; the world position
/// is read from <see cref="Node.LocalTransform"/> (so the camera moves by
/// updating its transform like any other node).
/// </summary>
public sealed class Camera : Node
{
    public float Fov  { get; set; } = 60f;
    public float Near { get; set; } = 0.1f;
    public float Far  { get; set; } = 1000f;

    protected internal override void OnBind(Tree tree)
    {
        tree.SetCamera(Entity, new CameraComponent
        {
            FovDeg = Fov,
            Near   = Near,
            Far    = Far,
        });
    }
}
