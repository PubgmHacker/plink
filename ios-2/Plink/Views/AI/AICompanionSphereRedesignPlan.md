# Plink AI sphere — redesign plan

Goal: make the AI companion feel premium like Siri / Alice / Yandex Music,
while keeping Plink’s living background identity.

## Keep
- living animated backdrop
- state-driven motion
- color changes by AI state
- overall glass-orb direction

## Change
- increase sphere volume and layering
- strengthen the specular highlight
- add clearer inner core / shell separation
- make listening/speaking feel more energetic
- reduce any toy-like flatness

## Implementation direction
1. Keep the SceneKit sphere, but refine the material stack.
2. Add a slightly more visible inner shell / refraction-like layer.
3. Make the voice-active states breathe more noticeably.
4. Tune light placement so the sphere reads from a distance.
5. Preserve motion reduction behavior and avoid over-animating.

## UX notes
- The orb should be the hero of the AI tab.
- Buttons around it should remain secondary.
- The composition should feel calm, not busy.

## Acceptance criteria
- The orb looks premium on small and large iPhones.
- The orb still works in dark mode.
- The orb still feels alive, not static.
- The orb does not fight the background; it sits in front of it.
