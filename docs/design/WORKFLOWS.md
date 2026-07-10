# Design Workflow Templates

Workflow templates define complete states, not just components.

## First Run And Permissions

States:

- Ready with no permissions requested.
- Microphone permission request.
- Accessibility permission request for dictation paste.
- Optional calendar permission.
- Permission denied with recovery action.

Rules:

- Ask for one permission at a time.
- Use local-processing copy.
- Never imply automatic recording.

## Idle Record Or Import

Primary jobs:

- Record meeting.
- Drop or choose supported audio/video file.
- Optional calendar context.

Rules:

- The first screen is the product, not onboarding.
- Keep file extensions visible as compact chips.
- Keep speaker engine settings out of the main path.

## Meeting Detection Prompt

States:

- Hidden.
- Browser microphone active.
- Call app active.
- Multiple apps active.
- Dismissed until clear.

Rules:

- Browser copy says microphone active, not meeting detected.
- The prompt never starts recording automatically.

## Recording

States:

- Starting.
- Recording.
- Paused.
- Stopping.
- Failed with recovery.

Rules:

- Recording state wins menu bar icon priority.
- Stop should clearly imply processing will begin.

## Model Setup

States:

- Missing models.
- Downloading.
- Download failed.
- Downloaded and ready to continue.

Rules:

- Show approximate size and FluidAudio/Hugging Face source before download.
- Keep uploads/no-upload copy visible.

## Processing

Stages:

- Preparing.
- Transcribing.
- Finding speakers.

Rules:

- Respect Reduce Motion.
- Skeleton geometry should match review geometry.
- Cancellation is not a failure state.

## Review And Export

Primary jobs:

- Rename speakers.
- Merge speakers.
- Filter preview.
- Copy Markdown.
- Save Markdown.

Rules:

- Copy and save are the final actions.
- New File is a utility action and requires confirmation when destructive.
- Calendar details are included only when enabled.

## Dictation

States:

- Ready.
- Missing model.
- Listening.
- Processing.
- Inserted.
- Failed.

Rules:

- Dictation settings use native controls.
- Dictation HUD stays compact.
- No dictation history is shown or implied.
