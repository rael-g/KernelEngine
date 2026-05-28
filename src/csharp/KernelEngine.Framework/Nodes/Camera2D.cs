namespace KernelEngine.Framework;

/// <summary>
/// A <see cref="Camera"/> preset for 2D scenes: orthographic projection, near/far chosen for
/// a thin Z slice around the XY plane. <see cref="Camera.OrthographicSize"/> is the half-height
/// of the viewport in world units (default <c>5</c> → 10-unit tall viewport).
///
/// <para>
/// The render is still 3D-PBR under the hood; the camera just stays parallel to XY. Place
/// physics-driven 2D nodes at Z=0; light them with a <see cref="DirectionalLight"/> pointing
/// roughly toward the camera, or crank <c>tree.SetAmbientLight</c> for a flat look.
/// </para>
/// </summary>
public class Camera2D : Camera
{
    public Camera2D()
    {
        // Defaults tuned for a 2D side-view: orthographic, ten-unit-tall viewport.
        // Near pulled away from 0 so 2D content sitting at Z=0 is in front of the camera
        // (which sits at Z = +10 by default); Far comfortably past it.
        Orthographic     = true;
        Near             = 0.1f;
        Far              = 100f;
        OrthographicSize = 5f;
    }

    protected override void Start()
    {
        // Pull the camera back along +Z by default so a 2D scene placed on the XY plane (Z=0)
        // is visible without the game having to set Position. Quads' +Z normals then face the
        // camera — backface culling stops eating them. Game code can override LocalTransform
        // before Start (init) to relocate.
        if (LocalTransform.Position == System.Numerics.Vector3.Zero)
        {
            LocalTransform = LocalTransform with { Position = new System.Numerics.Vector3(0, 0, 10) };
        }
        base.Start();
    }
}
