using System.Numerics;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// A 2D-friendly <see cref="MeshRenderer"/>. Adds two live-sync properties that fold into
/// <see cref="Node.LocalTransform"/>:
/// <list type="bullet">
///   <item><see cref="Size"/> — world-unit dimensions (XY). Sets <c>LocalTransform.Scale = (Size.X, Size.Y, 1)</c>.</item>
///   <item><see cref="Position2D"/> — XY in world units. Keeps <c>LocalTransform.Position.Z</c> intact.</item>
/// </list>
///
/// <para>
/// MVP scope (slice B1): expects a unit-quad <see cref="MeshRenderer.Mesh"/> and a colored
/// <see cref="MeshRenderer.Material"/> supplied by the caller (typical: <c>MeshShape.Quad()</c>
/// pre-created in <c>OnReady</c>; one material per distinct color). Textured sprites + flip + atlas
/// sub-rects + nine-slice are explicit non-goals here; they ship in a follow-up slice.
/// </para>
///
/// <para>
/// Lighting: the render is still PBR. A solid-color sprite reads dim without a light. Either
/// crank ambient (<c>tree.SetAmbientLight(1, 1, 1)</c>) for a flat 2D look, or place a
/// <see cref="DirectionalLight"/> pointed toward the camera.
/// </para>
/// </summary>
public class Sprite2D : MeshRenderer
{
    private Vector2 _size = Vector2.One;

    /// <summary>World-unit dimensions of the quad. Default <c>(1, 1)</c>.</summary>
    public Vector2 Size
    {
        get
        {
            var t = LocalTransform;
            return new Vector2(t.Scale.X, t.Scale.Y);
        }
        set
        {
            _size = value;
            LocalTransform = LocalTransform with { Scale = new Vector3(value.X, value.Y, 1f) };
        }
    }

    /// <summary>XY position shorthand. Z stays at whatever <see cref="LocalTransform"/> already has.</summary>
    public Vector2 Position2D
    {
        get
        {
            var p = LocalTransform.Position;
            return new Vector2(p.X, p.Y);
        }
        set
        {
            LocalTransform = LocalTransform with {
                Position = new Vector3(value.X, value.Y, LocalTransform.Position.Z),
            };
        }
    }

    protected override void Start()
    {
        // Apply Size at Start in case it was set on a not-yet-bound node (LocalTransform setter
        // is no-op until the node has a world; back-fill here once World is bound).
        LocalTransform = LocalTransform with { Scale = new Vector3(_size.X, _size.Y, 1f) };
        base.Start();
    }
}
