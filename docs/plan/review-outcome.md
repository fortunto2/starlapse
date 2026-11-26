# Review outcome: name the session that was looked at and not kept

Status: plan, not implemented (2026-11-26). Bet: product-hypotheses#2.

## Why

`capture_finished` (d451a34, live in 1.2.2 build 30 since 24.11) fires once, as a session
**enters** review (`enterReview` → `reportSessionFinished`). Its outcomes say whether there
was anything to review (`result`, `video`, `empty`, `no_video`, `interrupted`), not what
happened next. So the largest unsaved bucket has no name:

1.2.2, 24–26.11: 22 `capture_finished`, 7 `capture_saved`. `still/result` 11, of which 3
saved. ~8 of ~15 unsaved sessions (53%) are "reviewed, not saved", and that number exists
only as `result − saved`. Inside it, indistinguishable:

- tapped Discard (`dismissReview`) — judged the picture bad;
- Photos access refused (`save(image:)` returns early, no event);
- `PhotoLibraryWriter.write` threw (message on screen, no event);
- app killed or backgrounded while reviewing (still mode leaves no scratch file, so no
  `interrupted` either).

The bet asks for one reason over half. With these four folded into one subtraction, a
"held" verdict would name a bucket, not a reason.

## Change (smallest, no seventh event)

Reuse `capture_finished` with two more `outcome` values, sent when review **ends** without
a save. The privacy policy already covers it: "capture finished (with the mode, how it
ended, its length in minutes and the frame count)". No new metric keys.

1. `SessionOutcome` gains `discarded` and `saveFailed = "save_failed"`.
2. `CaptureViewModel` keeps `var reviewSaved = false`, reset in `enterReview`, set to
   `true` after a successful `PhotoLibraryWriter.write` in `save(image:)` / `save(videoAt:)`.
3. `dismissReview()`: if `!reviewSaved`, track `capture_finished` with
   `outcome: discarded`, same props/metrics as `reportSessionFinished` (mode, minutes,
   frames, segments).
4. `save(image:)` / `save(videoAt:)`: on access refused or a thrown write, track
   `capture_finished` with `outcome: save_failed` and prop `why: denied | error`.
   (`why` is a prop value inside "how it ended"; check the policy line still reads true.)
5. Kill during review stays as `result − saved − discarded − save_failed`, now a small
   remainder instead of the whole bucket.

Tests: `Tests/StarlapseTests` has no analytics seam today; add a pure function
`SessionOutcome.afterReview(saved:discarded:)` or skip tests (event wiring, UI flow).
Verify in the Simulator with `UITEST_SKY=1`: still → Discard → one extra row with
`outcome: discarded` in the dev source.

## Reading it

Sessions = `capture_finished` rows with outcome in (result, video, empty, no_video,
interrupted). `discarded` and `save_failed` are second rows of a `result`/`video` session,
never added to the session count. Unsaved split:
`empty + no_video + interrupted + discarded + save_failed + (result + video − saved − discarded − save_failed)`.

## Not doing

- A reason picker on Discard ("too dark / blurry / test"): a prompt at 2am is the wrong
  moment and adds UI; revisit only if `discarded` wins.
- A review-length metric: useful (glance vs deliberate), but a new metric key changes the
  policy text, README and the USAGE COUNTER copy in `ManualControlsView`.
