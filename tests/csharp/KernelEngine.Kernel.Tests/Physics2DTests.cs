using System.Numerics;
using System.Runtime.InteropServices;
using Xunit;

namespace KernelEngine.Kernel.Tests;

public class Physics2DTests
{
    private static Vector2 LastGravity = Vector2.Zero;
    private static float LastDeltaTime = 0;
    private static uint LastBodyId = 0;
    private static bool DestroyCalled = false;
    private static ke_body_type_2d LastBodyType = ke_body_type_2d.KE_BODY_TYPE_STATIC;
    private static Vector2 LastPosition = Vector2.Zero;
    private static float LastAngle = 0;
    private static Vector2 LastVelocity = Vector2.Zero;
    private static Vector2 LastImpulse = Vector2.Zero;
    private static ke_result LastResult = ke_result.KE_OK;

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
    private static unsafe ke_result MockCreateBody(ke_physics_2d* self, ke_body_type_2d type, float x, float y, uint* outId, ke_error** out_error)
    {
        LastBodyType = type;
        LastPosition = new Vector2(x, y);
        *outId = 42;
        return LastResult;
    }

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
    private static unsafe void MockDestroyBody(ke_physics_2d* self, uint id)
    {
        LastBodyId = id;
    }

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
    private static unsafe ke_result MockAddBoxFixture(ke_physics_2d* self, uint id, float hx, float hy, float d, float f, float r, ke_error** out_error)
    {
        LastBodyId = id;
        return ke_result.KE_OK;
    }

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
    private static unsafe ke_result MockAddCircleFixture(ke_physics_2d* self, uint id, float rad, float d, float f, float r, ke_error** out_error)
    {
        LastBodyId = id;
        return ke_result.KE_OK;
    }

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
    private static unsafe void MockGetBodyState(ke_physics_2d* self, uint id, ke_body_state_2d* state)
    {
        LastBodyId = id;
        state->x = 10;
        state->y = 20;
        state->angle = 0.5f;
        state->velocity_x = 1;
        state->velocity_y = 2;
        state->angular_velocity = 0.1f;
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
        var physics = new Physics2D(h);
        physics.SetGravity(new Vector2(0, -10));
        Assert.Equal(0, LastGravity.X);
        Assert.Equal(-10, LastGravity.Y);
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public unsafe void Step_CallsNative()
    {
        var h = CreateMockHandle();
        var physics = new Physics2D(h);
        physics.Step(0.016f);
        Assert.Equal(0.016f, LastDeltaTime);
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public unsafe void CreateBody_MarshalsTypeCorrectly()
    {
        var h = CreateMockHandle();
        var physics = new Physics2D(h);
        physics.CreateBody(BodyType2D.Dynamic, Vector2.Zero);
        Assert.Equal(ke_body_type_2d.KE_BODY_TYPE_DYNAMIC, LastBodyType);
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public unsafe void CreateBody_MarshalsPositionXCorrectly()
    {
        var h = CreateMockHandle();
        var physics = new Physics2D(h);
        physics.CreateBody(BodyType2D.Static, new Vector2(1, 0));
        Assert.Equal(1, LastPosition.X);
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public unsafe void CreateBody_MarshalsPositionYCorrectly()
    {
        var h = CreateMockHandle();
        var physics = new Physics2D(h);
        physics.CreateBody(BodyType2D.Static, new Vector2(0, 2));
        Assert.Equal(2, LastPosition.Y);
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public unsafe void CreateBody_ReturnsHandleFromNative()
    {
        var h = CreateMockHandle();
        var physics = new Physics2D(h);
        var handle = physics.CreateBody(BodyType2D.Static, Vector2.Zero);
        Assert.Equal(42u, handle.Value);
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public unsafe void CreateBody_ReturnsNone_WhenNativeFails()
    {
        var h = CreateMockHandle();
        var physics = new Physics2D(h);
        LastResult = ke_result.KE_ERROR;
        var handle = physics.CreateBody(BodyType2D.Dynamic, new Vector2(1, 2));
        Assert.Equal(BodyHandle2D.None, handle);
        LastResult = ke_result.KE_OK;
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public unsafe void DestroyBody_CallsNative()
    {
        var h = CreateMockHandle();
        var physics = new Physics2D(h);
        physics.DestroyBody(new BodyHandle2D(123));
        Assert.Equal(123u, LastBodyId);
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public unsafe void AddBoxFixture_CallsNative()
    {
        var h = CreateMockHandle();
        var physics = new Physics2D(h);
        physics.AddBoxFixture(new BodyHandle2D(123), new Vector2(1, 1));
        Assert.Equal(123u, LastBodyId);
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public unsafe void AddCircleFixture_CallsNative()
    {
        var h = CreateMockHandle();
        var physics = new Physics2D(h);
        physics.AddCircleFixture(new BodyHandle2D(123), 1.0f);
        Assert.Equal(123u, LastBodyId);
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public unsafe void GetBodyState_CallsNativeWithCorrectId()
    {
        var h = CreateMockHandle();
        var physics = new Physics2D(h);
        physics.GetBodyState(new BodyHandle2D(123));
        Assert.Equal(123u, LastBodyId);
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public unsafe void GetBodyState_ReturnsCorrectPositionX()
    {
        var h = CreateMockHandle();
        var physics = new Physics2D(h);
        var state = physics.GetBodyState(new BodyHandle2D(1));
        Assert.Equal(10, state.Position.X);
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public unsafe void GetBodyState_ReturnsCorrectPositionY()
    {
        var h = CreateMockHandle();
        var physics = new Physics2D(h);
        var state = physics.GetBodyState(new BodyHandle2D(1));
        Assert.Equal(20, state.Position.Y);
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public unsafe void GetBodyState_ReturnsCorrectAngle()
    {
        var h = CreateMockHandle();
        var physics = new Physics2D(h);
        var state = physics.GetBodyState(new BodyHandle2D(1));
        Assert.Equal(0.5f, state.Angle);
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public unsafe void SetBodyPosition_CallsNativeWithCorrectId()
    {
        var h = CreateMockHandle();
        var physics = new Physics2D(h);
        physics.SetBodyPosition(new BodyHandle2D(123), Vector2.Zero, 0);
        Assert.Equal(123u, LastBodyId);
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public unsafe void SetBodyPosition_MarshalsPositionCorrectly()
    {
        var h = CreateMockHandle();
        var physics = new Physics2D(h);
        physics.SetBodyPosition(new BodyHandle2D(1), new Vector2(1, 2), 0);
        Assert.Equal(1, LastPosition.X);
        Assert.Equal(2, LastPosition.Y);
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public unsafe void SetBodyPosition_MarshalsAngleCorrectly()
    {
        var h = CreateMockHandle();
        var physics = new Physics2D(h);
        physics.SetBodyPosition(new BodyHandle2D(1), Vector2.Zero, 0.5f);
        Assert.Equal(0.5f, LastAngle);
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public unsafe void SetBodyVelocity_CallsNativeWithCorrectId()
    {
        var h = CreateMockHandle();
        var physics = new Physics2D(h);
        physics.SetBodyVelocity(new BodyHandle2D(123), Vector2.Zero);
        Assert.Equal(123u, LastBodyId);
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public unsafe void SetBodyVelocity_MarshalsVelocityCorrectly()
    {
        var h = CreateMockHandle();
        var physics = new Physics2D(h);
        physics.SetBodyVelocity(new BodyHandle2D(1), new Vector2(1, 2));
        Assert.Equal(1, LastVelocity.X);
        Assert.Equal(2, LastVelocity.Y);
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public unsafe void ApplyImpulse_CallsNativeWithCorrectId()
    {
        var h = CreateMockHandle();
        var physics = new Physics2D(h);
        physics.ApplyImpulse(new BodyHandle2D(123), Vector2.Zero);
        Assert.Equal(123u, LastBodyId);
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public unsafe void ApplyImpulse_MarshalsImpulseCorrectly()
    {
        var h = CreateMockHandle();
        var physics = new Physics2D(h);
        physics.ApplyImpulse(new BodyHandle2D(1), new Vector2(1, 2));
        Assert.Equal(1, LastImpulse.X);
        Assert.Equal(2, LastImpulse.Y);
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public unsafe void Dispose_CallsDestroy()
    {
        var h = CreateMockHandle();
        var physics = new Physics2D(h);
        DestroyCalled = false;
        physics.Dispose();
        Assert.True(DestroyCalled);
        NativeMemory.Free(h.@ref);
    }
}
