# Physical-device checks — build 24

Use a textured horizontal surface, good lighting and a LiDAR iPhone where possible. Unit/simulator tests cannot certify these steps.

- [ ] Camera permission, scan, tap, select an avatar, default/custom name, Ready.
- [ ] Select, drag, pinch, rotate, Adjust, Ready; other characters remain unchanged.
- [ ] Wave and Dance visibly animate limbs; Jump either jumps/lands or reports missing support/clearance.
- [ ] Step right travels approximately 15 cm; Explore chooses a supported route of up to 30 cm. Verify the walk cycle stops when travel stops.
- [ ] Walking respects another character, table edge and nearby wall; no overlap or traversal into unscanned space.
- [ ] Stop/selection/tracking loss interrupts movement. Ready restores appropriate physics.
- [ ] Empty scene shows add-character guidance; Live appears only with placed characters.
- [ ] Key saved in Settings; Go live connects without crashing. Named commands affect the intended character.
- [ ] Decisions chooses a currently valid action without speech; cancellation/editing/speech prevents stale actions.
- [ ] End live, backgrounding and interruption stop the microphone. HTTP errors remain visible.
- [ ] Relaunch preserves character identities; placement is intentionally recreated.

**Confirmed by author:** build 23 Step right travels across the physical surface.

## Experimental depth reflexes

- [ ] Place a character on a broad clear surface, Ready, then Play. Confirm “Depth sensing active”.
- [ ] Move a hand or object slowly toward its side within the camera view. It should step away when there is clear scanned space, or flinch if boxed in.
- [ ] A stationary nearby mug should not repeatedly startle it. Moving the phone around a static scene should not create repeated avoidance.
- [ ] Stop, pause or select a character: no autonomous avoidance starts. Resume Play to re-enable.
- [ ] Repeat at a table edge and near another character; escape must remain on scanned support and respect occupied space.
- [ ] A person passing in front should occlude the character on supported hardware. This does not verify foot identification.
- [ ] Cover the depth view or lose tracking: status/reactions should degrade without inventing observations.
- [ ] Confirm walking limbs keep pace with actual travel and turns are smooth.

Do not claim reliable person avoidance from synthetic depth tests. Walking is confirmed; depth reflexes still require this hardware checklist.

## Build 25: a person covers a character

- [ ] With a floor/table scanned, let someone pass in front of or over the character in the camera view. Temporary hiding behind the person is expected; it must become visible again when the person leaves.
- [ ] Confirm the character does not fall through a temporary mesh gap. Horizontal detected-plane colliders now remain as finite support alongside LiDAR mesh collisions.
- [ ] If recovery is triggered, the character should be held near its latest supported spot (8 cm fall threshold), with an explicit status. Select/reposition and Ready to release it.
- [ ] Check jump/landing and walking near table edges with the additional support colliders.

This change addresses a plausible loss-of-support failure path. The reported disappearance has not yet been conclusively distinguished from normal people occlusion.

## Build 26 — reuse your cast
- Open Your cast: Place on an unplaced character closes the sheet; tap a detected surface to place the same saved identity. Cancel leaves the roster unchanged.
- Select on a placed character exposes its gesture/adjustment controls. New spot lets you relocate it even if it is offscreen.
- Verify failed placement allows another tap, with no duplicate roster entries. Edit and Delete remain separate.

## Build 28 — navigation and recovery
- While a character is travelling, block its route: it can take one short detour if both legs have scanned support and clearance. Otherwise it stops; no bypass of collision checks.
- Repeat the person-crossing test. A held character resumes physics after one continuous second of support/clearance. After two failed releases it stays held until New spot, preventing endless falling/resetting.
- Try Place / New spot on an unscanned or crowded area: the panel displays the reason and permits another tap.
- Check Pause interrupts a detour immediately, and arrival at a detour waypoint continues toward the original destination.
- Physical validation pending; tests cover candidate route validation and recovery evidence/retry bounds, not real-room perception accuracy.

## Build 30 — larger characters
- Pinch or Adjust size from 0.25× through 10× (bundled avatars roughly 3 cm–1.2 m tall).
- Verify enlargement is refused near another character or scanned obstacle and the reason appears in placement/Adjust controls; shrinking remains possible.
- Verify movement, support and collision at larger scales on a clear scanned floor. Mass calculations now use the same scale range as gestures and slider.

## Build 31 — animated character previews
- The selected carousel character and visible Your cast cards wave, wiggle and hop in non-AR RealityKit previews. Imported models retain their hierarchy and materials.
- Verify swiping still selects cards, Select/Place/Edit/Delete still work, and scrolling offscreen/dismissing stops previews. Reduce Motion should show still portraits.
- Simulator frame comparisons confirmed changing character poses with stable card layout. Preview performer is retained for the subscription lifetime; weak Entity wrappers froze the first iteration.
- Check smoothness with the live camera behind the sheet on the physical phone; device performance remains to be confirmed.

## Build 32 — voice command debugging
- Place a character, Ready, Go live; pause Play to isolate direct commands. Say the exact displayed name followed by wave, then try jump and step right separately.
- In Activity → Voice command, inspect Heard and the local result. Transcript is approximate; rejection reasons distinguish missing support/space from recognition problems.
- Say “wave then jump”: actions should occur sequentially. Pause/Stop or new speech should cancel remaining queued work.
- Speak during a character chirp; input should not be muted. Check for false self-triggering at the phone's usual speaker volume (voice processing enabled).
- Protocol/queue tests use synthetic server events and a mock executor; on-device microphone, model interpretation, and AR execution still need this end-to-end check.

## Build 33 — explicit walking request
User subsequently reported walking works on build 32. Build 33 adds an explicit walk tool action: without direction it resolves to exploration; with direction it resolves to a bounded move (15 cm default). Existing motion/support checks remain in place, with more specific failure messages. Verify “walk” and “walk right” after Ready, using the displayed character name.
