
using NSubstitute;
using Xunit;
using System.Text;

namespace KernelEngine.Framework.Legacy.Tests;

[Collection("KernelRegistry")]
public class SceneLoaderFrameworkTests
{
    private class FakeRegistry : IEcsRegistry
    {
        public ulong CreateEntity() => 0;
        public void DestroyEntity(ulong entity) { }
        public uint RegisterComponent<T>(string name) where T : unmanaged => 1u;
        public bool TryLookupComponent(string name, out uint componentId) { componentId = 0; return false; }
        public Span<T> AddComponent<T>(ulong entity, uint componentId) where T : unmanaged => new T[1];
        public Span<T> GetComponent<T>(ulong entity, uint componentId) where T : unmanaged => Span<T>.Empty;
        public void RemoveComponent(ulong entity, uint componentId) { }
        public bool HasComponent(ulong entity, uint componentId) => false;
        public EcsQuery<T> Query<T>(uint componentId) where T : unmanaged => default;
    }

    [Fact]
    public void Load_TriggersBackend()
    {
        var world = Substitute.For<IWorld>();
        world.Registry.Returns(new FakeRegistry());
        world.TransformComponentId.Returns(1u);

        var treeBackend = Substitute.For<ISceneTreeBackend>();
        treeBackend.Root.Returns(1UL);
        var tree = new Tree(world, treeBackend, null!);
        
        var backend = Substitute.For<ISceneLoaderBackend>();
        var factory = Substitute.For<IFrameworkBackendFactory>();
        factory.CreateSceneLoader(world, Arg.Any<ISceneTreeBackend>(), Arg.Any<string>())
            .Returns(backend);
        
        var old = FrameworkBackends.Default;
        FrameworkBackends.Default = factory;
        try {
            SceneLoader.Load(tree, "test.scene");
            backend.Received(1).Load("test.scene");
        } finally {
            FrameworkBackends.Default = old;
        }
    }
}
