# How Codex helped build Cast

Built during the DevDay Exchange Community Hackathon in London, 1 November 2026. This is an account of work visible in the development conversation, not a claim that every feature has passed a physical-device test.

## Scope and pivot

The initial brief was Pinmoir: persistent AR memories. The author later chose a separate app for named, voice-directed AR characters. Cast carries forward native SwiftUI and ARKit/RealityKit work, but does not include Pinmoir's saved ARWorldMap journey. The author supplied the character assets and directed the product and visual iteration.

## Meaningful contributions

1. **Native experience:** implemented the visual character carousel, default names, gallery, gesture editing, contextual Live controls and focused placement panel. Removed redundant instructional copy following device feedback.
2. **Asset correctness:** kept Entity.load hierarchies, authored metres and alpha-cutout fur materials; removed obsolete size/orientation corrections; rendered front-facing previews with RealityKit. Added checks for all five assets and their skeletons.
3. **Model-to-world boundary:** implemented Realtime named-character tool calls and Decisions fixed-choice requests. Generated options from measured scene state and revalidated decisions against scene revision and current options. Added cancellation and mocked failure/refusal/stale-response tests.
4. **Nonverbal personality:** implemented locally synthesized hums/chirps and bounded expression parameters. Names can change without changing a character's voice identity.
5. **Physical-device crash diagnosis:** an immediate Go live crash was traced through the actual iPhone crash report to Dictionary.init(dictionaryLiteral:) in CastScene.snapshot(). A duplicate name key caused a runtime trap. Codex removed it and added a populated-scene serialization regression test. Build numbers were also corrected in the generated Info.plist.
6. **Animation debugging:** replaced nearly invisible whole-body cues with skeletal gestures. Local joint-transform changes alone did not produce the intended rendered result, so sampled RealityKit animations were used. Rendered poses and tests verified the imported skeletons moved without replacing materials.
7. **Walking feedback loop:** the author reported walking in place. An impulse controller passed a simple floor/wall physics experiment, but the physical device still reported Path blocked. That status came from a stall timer, not obstacle detection. Build 23 uses small kinematic steps gated by scanned support and clearance, removes the silent Explore-to-inspect fallback, and includes a test moving an actual imported character hierarchy. Final on-device validation remains pending.
8. **Release preparation:** wrote setup instructions, credits, privacy notes, honest limitations and the hackathon submission copy; checked publication candidates for credentials and excluded device/build artifacts.

## Evidence and limits

- 25 unit tests passed for build 23; the added imported-character translation test also passed, for 26 passing tests across those runs.
- Simulator UI tests cover picking, editing gestures, gallery/settings and contextual controls. They cannot prove LiDAR navigation.
- Build 23 compiled for iPhone and was installed/launched on the connected physical device.
- Decisions tests mock HTTP transport. They do not prove live account access, response latency or autonomous behaviour in an arbitrary room.
- The author confirmed Pinmoir's memory restoration earlier in the day. That is evidence for the earlier app, not Cast persistence.
- No claim of complete environment understanding, person avoidance, reliable arbitrary-room navigation or zero drift is made.

## Post-submission development: build 24

The author confirmed build 23's walking travelled on the physical surface. The next increment adds local, confidence-filtered LiDAR obstacle-approach detection, conservative escape-route checks, a flinch fallback, cancellation of stale AI actions and gait synchronization. Six synthetic-depth/reflex tests cover projection, padded pixel-buffer rows, confidence, sustained approach, cooldown, stationary/retreating observations and swept route checks. This is not proof of real-world person tracking; physical validation remains pending. The initial hackathon commit remains available in Git history.

Build 25 investigates a report of a character disappearing when someone entered the scene. Added finite horizontal-plane support on LiDAR devices, updated the walking recovery checkpoint as the actor moves, and reduced the fall threshold from one metre to eight centimetres. Recovery clears animation/targets and holds the character near the supported checkpoint. Normal people occlusion still hides virtual content behind visible people; the precise reported cause requires device confirmation.

Build 28 adds a bounded two-leg detour when an active walk becomes blocked; both legs require scanned support, clearance samples and fresh depth checks when available. A waypoint preserves the requested destination and each subsequent motion step remains gated. Temporary support recovery now requires a continuous second of evidence and allows at most two automatic releases before manual repositioning. Placement panels expose rejection status. Added regression tests for blocked return legs, invalid routes, intermittent support and retry limits; real-room behavior still needs device validation.

Build 32 voice debugging: code inspection found microphone chunks were dropped during local chirps and immediate batch execution could overwrite a character's prior action. Realtime now waits for completed responses (arguments.done also occurs on cancellation), deduplicates responses, queues overlapping participants, cancels queued work on new speech/Stop, and uses a tool-disabled text follow-up. Continuous voice-processed input allows interruption; hardware echo behavior still requires testing. Activity exposes approximate input transcription and actual local command results. Seven protocol/queue regression tests passed with the final full 44-test suite. No live API/microphone success is claimed from these tests. Official references: https://developers.openai.com/api/reference/resources/realtime/server-events and https://developers.openai.com/api/docs/guides/realtime-conversations .
