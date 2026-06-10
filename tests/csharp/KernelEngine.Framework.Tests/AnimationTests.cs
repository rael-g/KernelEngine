using KernelEngine.Framework.Animation;
using Xunit;
using System.Collections.Generic;

namespace KernelEngine.Framework.Tests;

public class AnimationTests
{
    [Fact]
    public void KeyframeAnimation_EvaluatesCorrectly()
    {
        var keyframes = new List<(float Time, float Value, EasingFunction? EasingFunction)>
        {
            (0f, 0f, Easing.Linear),
            (1f, 10f, Easing.Linear)
        };
        var anim = new KeyframeAnimation(keyframes);
        
        anim.Update(0f);
        Assert.Equal(0f, anim.Current);
        
        anim.Update(0.5f);
        Assert.Equal(5f, anim.Current);
        
        anim.Update(0.6f); // Total 1.1s
        Assert.True(anim.IsCompleted);
        Assert.Equal(10f, anim.Current);
    }

    [Fact]
    public void Tween_UpdatesValueOverTime()
    {
        var tween = new Tween(0f, 100f, 1000, Easing.Linear);
        
        tween.Update(0.5f); // 500ms
        Assert.Equal(50, tween.Current, 1);
        Assert.False(tween.IsCompleted);

        tween.Update(0.6f); // +600ms = 1100ms
        Assert.Equal(100, tween.Current, 1);
        Assert.True(tween.IsCompleted);
    }

    [Fact]
    public void Tween_Easing_EaseIn()
    {
        var tween = new Tween(0f, 100f, 1000, Easing.EaseIn);
        
        tween.Update(0.5f); // t=0.5 -> t*t = 0.25
        Assert.Equal(25, tween.Current, 1);
    }

    [Fact]
    public void Tween_Reset_Works()
    {
        var tween = new Tween(0f, 100f, 1000);
        tween.Update(1.1f);
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
    public void Easing_EaseOut_ReturnsInverseSquared()
    {
        Assert.Equal(0.75f, Easing.EaseOut(0.5f));
    }

    [Fact]
    public void AnimationCurve_EvaluatesKeys()
    {
        var points = new List<(float Time, float Value)>
        {
            (0f, 0f),
            (1f, 100f)
        };
        var curve = new AnimationCurve(points);

        Assert.Equal(50, curve.Evaluate(0.5f), 1);
    }
}
