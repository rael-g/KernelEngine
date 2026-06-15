namespace KernelEngine.Framework;

/// <summary>
/// Scene node that drives the per-frame view/projection. The first entity with a
/// <see cref="CameraComponent"/> in the ECS becomes the active camera.
/// </summary>
public class Camera : Node
{
    public float Fov              { get; set; } = 60f;
    public float Near             { get; set; } = 0.1f;
    public float Far              { get; set; } = 1000f;
    public bool  Orthographic     { get; set; }
    public float OrthographicSize { get; set; } = 5f;

    protected internal override void OnBind(NodeWorld nodeWorld)
        => nodeWorld.Set(Entity, new CameraComponent
        {
            Fov              = Fov,
            NearPlane        = Near,
            FarPlane         = Far,
            Orthographic     = (byte)(Orthographic ? 1 : 0),
            OrthographicSize = OrthographicSize,
        });
}
