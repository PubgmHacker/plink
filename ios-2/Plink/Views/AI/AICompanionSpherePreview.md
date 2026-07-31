# Plink AI sphere — preview concept

Concept direction: keep the living background, but make the AI orb feel more like a premium voice assistant.

## What changes
- Replace the current slightly flat orb with a **proper layered glass sphere**.
- Preserve the **living, animated backdrop** behind it.
- Make the sphere read as:
  - glossy
  - volumetric
  - centered
  - responsive to state
  - premium, not toy-like

## Visual target
Think:
- Siri / Alice / Yandex Music assistant sphere
- soft core glow
- translucent outer shell
- subtle particle motion
- state-driven color shifts
- realistic specular highlight
- gentle breathing animation

## Current code direction
The existing `AI3DCompanionSphere` already gives us a strong base:
- SceneKit sphere
- state-based palette
- glow
- particles
- glass highlight
- accessibility-safe motion reduction

## What still should be improved next
1. Make the sphere slightly more **heroic** on the AI tab.
2. Increase the sense of **depth** with layered shells and refraction-like lighting.
3. Add a more distinct **voice-active pulse** for listening/speaking.
4. Reduce any “flat icon” feeling by tuning light contrast and highlight placement.
5. Keep the background alive, but ensure the sphere remains the visual anchor.

## Non-goals
- Do not turn it into a dead static illustration.
- Do not remove the living background concept.
- Do not replace it with a simple 2D blob.
