using System.Numerics;
using System.Runtime.InteropServices;

using KernelEngine.Result.Native;

using Xunit;

namespace EngineTests;

public class Physics2DTests
{
    private static Vector2 LastGravity = Vector2.Zero;
    private static float LastDeltaTime = 0;
    private static uint LastBodyId = 0;
    private static bool DestroyCalled = false;
    private static BodyType2D LastBodyType = BodyType2D.Static;
    private static Vector2 LastPosition = Vector2.Zero;
    private static float LastAngle = 0;
    private static Vector2 LastVelocity = Vector2.Zero;
    private static Vector2 LastImpulse = Vector2.Zero;
    private static bool LastResult = true;

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
    private static unsafe void MockSetGravity(ke_physics_2d* self, float x, float y)
    {
        LastGravity = new Vector2(x, y);
    }

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
    private static unsafe void MockStep(ke_physics_2d* self, float dt)
    {
        LastDeltaTime = dt;
    }

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
    private static unsafe global::KernelEngine.Result.Native.Result MockCreateBody(ke_physics_2d* self, BodyType2D type, float x, float y, uint* outBody)
    {
        LastBodyType = type;
        LastPosition = new Vector2(x, y);
        *outBody = LastResult ? 42u : 0u;
        return LastResult ? global::KernelEngine.Result.Native.Result.Ok : global::KernelEngine.Result.Native.Result.OutOfMemory;
    }

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
    private static unsafe void MockDestroyBody(ke_physics_2d* self, uint id)
    {
        LastBodyId = id;
    }

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
    private static unsafe global::KernelEngine.Result.Native.Result MockAddBoxFixture(ke_physics_2d* self, uint id, float hx, float hy, float ox, float oy, float oa, float d, float f, float r, CollisionFilter2d* filter)
    {
        LastBodyId = id;
        return global::KernelEngine.Result.Native.Result.Ok;
    }

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
    private static unsafe global::KernelEngine.Result.Native.Result MockAddCircleFixture(ke_physics_2d* self, uint id, float rad, float ox, float oy, float d, float f, float r, CollisionFilter2d* filter)
    {
        LastBodyId = id;
        return global::KernelEngine.Result.Native.Result.Ok;
    }

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
    private static unsafe void MockGetBodyState(ke_physics_2d* self, uint id, BodyState2d* state)
    {
        LastBodyId = id;
        state->X = 10;
        state->Y = 20;
        state->Angle = 0.5f;
        state->VelocityX = 1;
        state->VelocityY = 2;
        state->AngularVelocity = 0.1f;
    }

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
    private static unsafe void MockSetBodyPosition(ke_physics_2d* self, uint id, float x, float y, float a)
    {
        LastBodyId = id;
        LastPosition = new Vector2(x, y);
        LastAngle = a;
    }

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
    private static unsafe void MockSetBodyVelocity(ke_physics_2d* self, uint id, float vx, float vy)
    {
        LastBodyId = id;
        LastVelocity = new Vector2(vx, vy);
    }

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
    private static unsafe void MockApplyImpulse(ke_physics_2d* self, uint id, float ix, float iy)
    {
        LastBodyId = id;
        LastImpulse = new Vector2(ix, iy);
    }

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
    private static unsafe void MockDestroy(ke_physics_2d* self)
    {
        DestroyCalled = true;
    }

    private unsafe ke_physics_2d_handle CreateMockHandle()
    {
        var ptr = (ke_physics_2d*)NativeMemory.Alloc((nuint)sizeof(ke_physics_2d));
        ptr->set_gravity = &MockSetGravity;
        ptr->step = &MockStep;
        ptr->create_body = &MockCreateBody;
        ptr->destroy_body = &MockDestroyBody;
        ptr->add_box_fixture = &MockAddBoxFixture;
        ptr->add_circle_fixture = &MockAddCircleFixture;
        ptr->get_body_state = &MockGetBodyState;
        ptr->set_body_position = &MockSetBodyPosition;
        ptr->set_body_velocity = &MockSetBodyVelocity;
        ptr->apply_impulse = &MockApplyImpulse;
        return new ke_physics_2d_handle { @ref = ptr, destroy = &MockDestroy };
    }

    [Fact]
    public unsafe void Constructor_Throws_WhenNativeIsNull()
    {
        Assert.Throws<ArgumentNullException>(() => new Physics2D(new ke_physics_2d_handle()));
    }

    [Fact]
    public unsafe void SetGravity_CallsNative()
    {
        var h = CreateMockHandle();
        IPhysics2D physics = new Physics2D(h);
        physics.SetGravity(0, -10);
        Assert.Equal(0, LastGravity.X);
        Assert.Equal(-10, LastGravity.Y);
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public unsafe void Step_CallsNative()
    {
        var h = CreateMockHandle();
        IPhysics2D physics = new Physics2D(h);
        physics.Step(0.016f);
        Assert.Equal(0.016f, LastDeltaTime);
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public unsafe void CreateBody_MarshalsTypeCorrectly()
    {
        var h = CreateMockHandle();
        IPhysics2D physics = new Physics2D(h);
        physics.CreateBody(BodyType2D.Dynamic, 0, 0);
        Assert.Equal(BodyType2D.Dynamic, LastBodyType);
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public unsafe void CreateBody_MarshalsPositionXCorrectly()
    {
        var h = CreateMockHandle();
        IPhysics2D physics = new Physics2D(h);
        physics.CreateBody(BodyType2D.Static, 1, 0);
        Assert.Equal(1, LastPosition.X);
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public unsafe void CreateBody_MarshalsPositionYCorrectly()
    {
        var h = CreateMockHandle();
        IPhysics2D physics = new Physics2D(h);
        physics.CreateBody(BodyType2D.Static, 0, 2);
        Assert.Equal(2, LastPosition.Y);
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public unsafe void CreateBody_ReturnsHandleFromNative()
    {
        var h = CreateMockHandle();
        IPhysics2D physics = new Physics2D(h);
        var handle = physics.CreateBody(BodyType2D.Static, 0, 0);
        Assert.Equal(42u, handle);
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public unsafe void CreateBody_Throws_WhenNativeFails()
    {
        var h = CreateMockHandle();
        IPhysics2D physics = new Physics2D(h);
        LastResult = false;
        Assert.Throws<OutOfMemoryException>(() => physics.CreateBody(BodyType2D.Dynamic, 1, 2));
        LastResult = true;
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public unsafe void DestroyBody_CallsNative()
    {
        var h = CreateMockHandle();
        IPhysics2D physics = new Physics2D(h);
        physics.DestroyBody(123);
        Assert.Equal(123u, LastBodyId);
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public unsafe void AddBoxFixture_CallsNative()
    {
        var h = CreateMockHandle();
        IPhysics2D physics = new Physics2D(h);
        physics.AddBoxFixture(123, 1, 1, 0, 0, 0, 1f, 0.3f, 0f, default);
        Assert.Equal(123u, LastBodyId);
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public unsafe void AddCircleFixture_CallsNative()
    {
        var h = CreateMockHandle();
        IPhysics2D physics = new Physics2D(h);
        physics.AddCircleFixture(123, 1f, 0, 0, 1f, 0.3f, 0f, default);
        Assert.Equal(123u, LastBodyId);
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public unsafe void GetBodyState_CallsNativeWithCorrectId()
    {
        var h = CreateMockHandle();
        IPhysics2D physics = new Physics2D(h);
        physics.GetBodyState(123);
        Assert.Equal(123u, LastBodyId);
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public unsafe void GetBodyState_ReturnsCorrectPositionX()
    {
        var h = CreateMockHandle();
        IPhysics2D physics = new Physics2D(h);
        var state = physics.GetBodyState(1);
        Assert.Equal(10, state.X);
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public unsafe void GetBodyState_ReturnsCorrectPositionY()
    {
        var h = CreateMockHandle();
        IPhysics2D physics = new Physics2D(h);
        var state = physics.GetBodyState(1);
        Assert.Equal(20, state.Y);
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public unsafe void GetBodyState_ReturnsCorrectAngle()
    {
        var h = CreateMockHandle();
        IPhysics2D physics = new Physics2D(h);
        var state = physics.GetBodyState(1);
        Assert.Equal(0.5f, state.Angle);
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public unsafe void SetBodyPosition_CallsNativeWithCorrectId()
    {
        var h = CreateMockHandle();
        IPhysics2D physics = new Physics2D(h);
        physics.SetBodyPosition(123, 0, 0, 0);
        Assert.Equal(123u, LastBodyId);
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public unsafe void SetBodyPosition_MarshalsPositionCorrectly()
    {
        var h = CreateMockHandle();
        IPhysics2D physics = new Physics2D(h);
        physics.SetBodyPosition(1, 1, 2, 0);
        Assert.Equal(1, LastPosition.X);
        Assert.Equal(2, LastPosition.Y);
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public unsafe void SetBodyPosition_MarshalsAngleCorrectly()
    {
        var h = CreateMockHandle();
        IPhysics2D physics = new Physics2D(h);
        physics.SetBodyPosition(1, 0, 0, 0.5f);
        Assert.Equal(0.5f, LastAngle);
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public unsafe void SetBodyVelocity_CallsNativeWithCorrectId()
    {
        var h = CreateMockHandle();
        IPhysics2D physics = new Physics2D(h);
        physics.SetBodyVelocity(123, 0, 0);
        Assert.Equal(123u, LastBodyId);
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public unsafe void SetBodyVelocity_MarshalsVelocityCorrectly()
    {
        var h = CreateMockHandle();
        IPhysics2D physics = new Physics2D(h);
        physics.SetBodyVelocity(1, 1, 2);
        Assert.Equal(1, LastVelocity.X);
        Assert.Equal(2, LastVelocity.Y);
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public unsafe void ApplyImpulse_CallsNativeWithCorrectId()
    {
        var h = CreateMockHandle();
        IPhysics2D physics = new Physics2D(h);
        physics.ApplyImpulse(123, 0, 0);
        Assert.Equal(123u, LastBodyId);
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public unsafe void ApplyImpulse_MarshalsImpulseCorrectly()
    {
        var h = CreateMockHandle();
        IPhysics2D physics = new Physics2D(h);
        physics.ApplyImpulse(1, 1, 2);
        Assert.Equal(1, LastImpulse.X);
        Assert.Equal(2, LastImpulse.Y);
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public unsafe void Dispose_CallsDestroy()
    {
        var h = CreateMockHandle();
        IPhysics2D physics = new Physics2D(h);
        DestroyCalled = false;
        physics.Dispose();
        Assert.True(DestroyCalled);
        NativeMemory.Free(h.@ref);
    }
}
