namespace KernelEngine.Framework;

/// <summary>
/// Camera node. Init properties set perspective parameters; the world position
/// is read from <see cref="Node.LocalTransform"/> (so the camera moves by
/// updating its transform like any other node).
/// </summary>
public class Camera : Node
{
    public float Fov              { get; set; } = 60f;
    public float Near             { get; set; } = 0.1f;
    public float Far              { get; set; } = 1000f;
    public bool  Orthographic     { get; set; } = false;
    public float OrthographicSize { get; set; } = 5f;

    protected internal override void OnBind(Tree tree)
    {
        tree.Set(Entity, new CameraComponent
        {
            FovDeg           = Fov,
            Near             = Near,
            Far              = Far,
            Orthographic     = Orthographic,
            OrthographicSize = OrthographicSize,
        });
    }
}
