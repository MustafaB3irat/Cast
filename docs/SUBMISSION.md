# Hackathon submission — Cast

**Event:** DevDay Exchange Community Hackathon, London, 1 November 2026
**Repository:** https://github.com/MustafaB3irat/Cast
**Demo video:** pending final export from the separate video workflow; must be public and ≤90 seconds.

## Short pitch

Cast puts little characters into your world. Tap a real surface, pick a furry avatar, give it a name, then direct it by voice. OpenAI Realtime translates spoken requests into validated character actions, while the Decisions API chooses playful reactions from options grounded in the scanned scene. Native SwiftUI, ARKit and RealityKit bring the cast to life, with expressive skeletal gestures and locally synthesized cartoon chirps.

## Why it is fun

A phone camera becomes a tiny stage. Naming, positioning and directing characters makes the experience personal; nonverbal voices keep it playful without turning every interaction into a chatbot conversation.

## What was built

A native iPhone prototype with five authored avatars, tap placement, a visual carousel, gesture editing, a cast gallery, offline actions, named voice commands and autonomous fixed-choice decisions. The app began as a pivot from an AR memory app called Pinmoir. Assets were supplied by their creator; provenance and existing-material credits are in CREDITS.md.

## Codex example

Codex diagnosed an immediate Go live crash using the physical iPhone's crash report, found a duplicate dictionary key in the scene snapshot, fixed it and added a populated-scene regression test. It also helped implement the API/action boundary, skeletal animation and iterative native UX. Details: CODEX_NOTES.md.

## 75-second working-demo outline

- 0–8 s: “Cast: little characters, your world.” Show the real iPhone AR camera and a clear, non-identifying surface.
- 8–25 s: Tap, swipe through avatars, add Felipe; demonstrate resizing/rotation and Ready.
- 25–40 s: Add Alfred. Show one verified offline gesture, such as Wave or Dance.
- 40–58 s: Go live and issue a named command. Include the actual response; do not replace latency or failures with fabricated footage.
- 58–68 s: If verified, show a spontaneous Decisions choice. Otherwise describe it as implemented and show its real status.
- 68–75 s: Repo URL, stack and one concrete Codex contribution.

Do not showcase walking as fixed until build 23 passes on the physical device. No saved-placement, people-avoidance or general visual-understanding claims. Avoid personal faces, notifications, keys and identifiable room/location information. Credit any licensed music in the final video.

## Final handoff

- [ ] Verify the final video is ≤90 seconds and plays without sign-in or permission requests.
- [ ] Add its public link to README.md and this file.
- [ ] Submit the repository and video through the organisers' submission channel before 17:00 London time.
- [ ] Confirm the actual receipt; publishing GitHub is not itself submitting the entry.
