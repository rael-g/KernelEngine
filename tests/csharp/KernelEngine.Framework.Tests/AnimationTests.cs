using KernelEngine.Framework.Animation;
using Xunit;

namespace KernelEngine.Framework.Tests;

public class AnimationTests
{
    [Fact]
    public void Tween_UpdatesValueOverTime()
    {
        var tween = new Tween(0f, 100f, 1000, Easing.Linear);
        
        tween.Update(0.5f); // 500ms
        Assert.Equal(50, tween.Current, 1);
        Assert.False(tween.IsCompleted);

        tween.Update(0.5f); // +500ms = 1000ms
        Assert.Equal(100, tween.Current, 1);
        Assert.True(tween.IsCompleted);
    }

    [Fact]
    public void Tween_Easing_EaseIn()
    {
        var tween = new Tween(0f, 100f, 1000, Easing.EaseIn);
        
        tween.Update(0.5f); // 500ms -> t=0.5 -> t*t = 0.25
        Assert.Equal(25, tween.Current, 1);
    }

    [Fact]
    public void Tween_Reset_Works()
    {
        var tween = new Tween(0f, 100f, 1000);
        tween.Update(1.0f);
        Assert.True(tween.IsCompleted);

        tween.Reset();
        Assert.Equal(0, tween.Current);
        Assert.False(tween.IsCompleted);
    }

    [Fact]
    public void Easing_Linear_ReturnsT()
    {
        Assert.Equal(0.5f, Easing.Linear(0.5f));
    }

    [Fact]
    public void Easing_EaseIn_ReturnsTSquared()
    {
        Assert.Equal(0.25f, Easing.EaseIn(0.5f));
    }

    [Fact]
    public void Easing_EaseOut_ReturnsParabola()
    {
        Assert.Equal(0.75f, Easing.EaseOut(0.5f));
    }

    [Fact]
    public void Easing_EaseInOut_ReturnsS_Curve()
    {
        Assert.Equal(0.5f, Easing.EaseInOut(0.5f));
        Assert.Equal(0.08f, Easing.EaseInOut(0.2f), 2);
        Assert.Equal(0.92f, Easing.EaseInOut(0.8f), 2);
    }

    [Fact]
    public void AnimationCurve_EvaluatesKeys()
    {
        var points = new List<(float Time, float Value)>
        {
            (0f, 0f),
            (1000f, 100f)
        };
        var curve = new AnimationCurve(points);

        Assert.Equal(50, curve.Evaluate(500), 1);
    }

    [Fact]
    public void KeyframeAnimation_SequencesAnimations()
    {
        var keyframes = new List<(float Time, float Value, EasingFunction? EasingFunction)>
        {
            (0, 0f, Easing.Linear),
            (500, 50f, Easing.Linear),
            (1000, 100f, Easing.Linear)
        };
        var animation = new KeyframeAnimation(keyframes);

        animation.Update(250f); // 250ms
        Assert.Equal(25, animation.Current, 1);

        animation.Update(500f); // 250 + 500 = 750ms
        Assert.Equal(75, animation.Current, 1);
    }
}
