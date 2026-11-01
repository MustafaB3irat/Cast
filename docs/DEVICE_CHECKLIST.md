# Physical-device checks — build 23

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

**Known outstanding:** previous dynamic walking stalled on-device despite a passing simple physics experiment. Build 23 replaces that walking path; the final device retest remains pending. Do not mark it passed from unit tests alone.
