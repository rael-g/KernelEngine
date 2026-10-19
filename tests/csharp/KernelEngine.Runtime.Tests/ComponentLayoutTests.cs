using System.Numerics;

using KernelEngine.Ecs;
using KernelEngine.Ecs.Flecs;

using Xunit;

namespace KernelEngine.Runtime.Tests;

public unsafe class ComponentLayoutTests : IDisposable
{
    private readonly FlecsEcs _ecs = new();
    private readonly EcsRegistry _registry;

    public ComponentLayoutTests() => _registry = EcsRegistry.Borrow(((INativeEcs)_ecs).Native);

    public void Dispose() => _ecs.Dispose();

    private struct Pose : IComponentLayout
    {
        public Vector2 Position;
        public float Angle;

        public static ReadOnlySpan<ComponentField> Fields => s_fields;

        private static readonly ComponentField[] s_fields = Describe();

        private static ComponentField[] Describe()
        {
            var v = default(Pose);
            return
            [
                ComponentFields.Row(ref v, ref v.Position, "position", ComponentFieldKind.Vec2, ComponentFieldValue.None),
                ComponentFields.Row(ref v, ref v.Angle, "angle", ComponentFieldKind.Float, ComponentFieldValue.Of(1.5)),
            ];
        }
    }

    private struct SwappedPose : IComponentLayout
    {
        public float Angle;
        public Vector2 Position;

        public static ReadOnlySpan<ComponentField> Fields => s_fields;

        private static readonly ComponentField[] s_fields = Describe();

        private static ComponentField[] Describe()
        {
            var v = default(SwappedPose);
            return
            [
                ComponentFields.Row(ref v, ref v.Position, "position", ComponentFieldKind.Vec2, ComponentFieldValue.None),
                ComponentFields.Row(ref v, ref v.Angle, "angle", ComponentFieldKind.Float, ComponentFieldValue.None),
            ];
        }
    }

    [Fact]
    public void A_struct_registered_twice_with_the_same_table_gets_the_same_id()
    {
        var first = _registry.RegisterComponent<Pose>("pose");
        Assert.NotEqual(0u, first);
        Assert.Equal(first, _registry.RegisterComponent<Pose>("pose"));
    }

    [Fact]
    public void A_struct_whose_fields_sit_elsewhere_is_refused_under_a_name_already_registered()
    {
        _registry.RegisterComponent<Pose>("pose");
        Assert.ThrowsAny<Exception>(() => _registry.RegisterComponent<SwappedPose>("pose"));
    }

    [Fact]
    public void Adding_a_component_seeds_the_defaults_its_table_declares()
    {
        var cid = _registry.RegisterComponent<Pose>("pose");
        var entity = _registry.CreateEntity();
        var pose = _registry.AddComponent<Pose>(entity, cid);
        Assert.Equal(1.5f, pose[0].Angle);
    }
}
