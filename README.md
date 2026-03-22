# Vox's Water Shader

I am a stupid moron and I like to use Shader Graph like a baby even though I am actually a real programmer…
This nice comment was said by my friend [AlignedCookie88](https://github.com/AlignedCookie88) as I am writing this Markdown in college.

---

## BEFORE WE PROCEED

**THIS SHADER ONLY WORKS ON ORTHOGRAPHIC CAMERA** (unless you use the HLSL version below, which works on both ortho & perspective)

---

## How it works

In an orthographic camera, there is no Z value, so we cannot get depth directly to add the edge foam.
Luckily, the gracious Cyan has a blog teaching how to get depth in an orthographic camera:
[Orthographic Depth - Cyan](https://cyangamedev.wordpress.com/2020/03/05/orthographic-depth/)

**The gist:**

1. Get the raw depth from the Scene Depth node.
2. Use the reversed Z sign if your project uses Unity’s reversed Z.
3. Compare the scene depth with the fragment depth of the water.
4. Run the scene depth through `One Minus` to remap it from 0 → 1.

This gives a usable depth mask even in orthographic mode so you can generate **edge foam** properly.

---

## My HLSL Water Shader

I also made a fully HLSL shader that works on **both orthographic and perspective cameras**, with:

* Stylized water colors (shallow → deep)
* Gerstner waves (A/B/C layers)
* Normal map blending & tiling
* Refraction based on screen depth
* Surface foam & edge foam
* Specular highlights with sun direction
* Correct depth handling for ortho & perspective

> Works in **Unity 6 URP**. Make sure Depth Texture and Opaque Texture are ON in URP Asset.

---

### Quick Depth Breakdown (HLSL version)

```text
sceneDepth  = linear eye depth from scene depth texture
fragDepth   = water pixel depth:
    • Perspective: clip.w
    • Orthographic: remap NDC Z → [near, far]
waterDepth  = saturate((sceneDepth - fragDepth) / maxDist)
```

* Surface foam fades in shallow areas.
* Edge foam appears only at intersections.
* Specular adds realistic glints based on sun.

---

### Shader Highlights

* Procedural foam noise using `ValueNoise`.
* Gerstner waves generate realistic surface displacement.
* Refraction offset from normals for visual bending of objects below water.
* Works with **transparent queue** and **no ZWrite**, fully additive blending.

