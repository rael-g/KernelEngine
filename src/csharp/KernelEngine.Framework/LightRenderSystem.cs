using System.Numerics;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Pure-managed render system that reads directional/point/spot light components from the ECS
/// and publishes them into the frame packet via the safe <see cref="IFramePacket"/> API.
/// </summary>
public sealed class LightRenderSystem : ISystem
{
    private readonly uint _lightCid;
    private readonly uint _pointCid;
    private readonly uint _spotCid;
    private readonly uint _transformCid;

    public LightRenderSystem(uint lightCid, uint pointCid, uint spotCid, uint transformCid)
    {
        _lightCid = lightCid;
        _pointCid = pointCid;
        _spotCid = spotCid;
        _transformCid = transformCid;
    }

    public void Update(IWorld world, float dt, IFramePacket? packet = null, IInputReader? input = null)
    {
        if (packet == null) return;
        var registry = world.Registry;

        // ── Directional ────────────────────────────────────────────────────────
        var dirLights = registry.Query<LightComponent>(_lightCid);
        if (dirLights.Length > 0)
        {
            var l = dirLights.Data[0];
            packet.SetDirectionalLight(new DirectionalLight
            {
                Direction = new Vector3(l.DirX, l.DirY, l.DirZ),
                Color = new Vector3(l.R, l.G, l.B),
                Intensity = l.Intensity,
            });
        }

        // ── Point ──────────────────────────────────────────────────────────────
        var pointLights = registry.Query<PointLightComponent>(_pointCid);
        for (int i = 0; i < pointLights.Length; i++)
        {
            var c = pointLights.Data[i];
            var pos = ReadPosition(registry, pointLights.Entities[i]);
            packet.AddPointLight(new PointLight
            {
                Position = pos,
                Radius = c.Radius,
                Color = new Vector3(c.R, c.G, c.B),
                Intensity = c.Intensity,
            });
        }

        // ── Spot ───────────────────────────────────────────────────────────────
        var spotLights = registry.Query<SpotLightComponent>(_spotCid);
        for (int i = 0; i < spotLights.Length; i++)
        {
            var c = spotLights.Data[i];
            var pos = ReadPosition(registry, spotLights.Entities[i]);
            packet.AddSpotLight(new SpotLight
            {
                Position = pos,
                Range = c.Range,
                Direction = new Vector3(c.DirX, c.DirY, c.DirZ),
                InnerAngle = c.InnerAngle,
                OuterAngle = c.OuterAngle,
                Color = new Vector3(c.R, c.G, c.B),
                Intensity = c.Intensity,
            });
        }
    }

    private Vector3 ReadPosition(IEcsRegistry registry, ulong entity)
    {
        var slot = registry.GetComponent<TransformComponent>(entity, _transformCid);
        return slot.IsEmpty ? Vector3.Zero : slot[0].Position;
    }

    public ComponentAccess GetAccess() => new()
    {
        Reads = [_lightCid, _pointCid, _spotCid, _transformCid],
        Writes = []
    };
}
