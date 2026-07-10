# Antrum Privacy Policy

## Local processing

- Meeting audio, transcript text, speaker labels, and Markdown are processed on your Mac.
- Antrum does not upload meeting audio or transcript text.
- Antrum has no account system, advertising identifiers, analytics SDKs, or cross-app tracking.

## Permissions

- Microphone permission records your voice as a separate local track.
- System audio capture records remote speakers locally on macOS 14.2 or later.
- Meeting detection checks local macOS microphone-use state for supported apps and only offers a recording prompt. It does not inspect browser tabs, join calls, or record automatically.
- Dictation records temporary microphone audio, transcribes it on-device, inserts text with Accessibility permission, then deletes temporary audio.
- Calendar access is optional. When enabled, Antrum reads only an event overlapping a recording and can add its title, schedule, calendar, and location to that meeting's Markdown. It does not include notes, URLs, attendees, or unrelated events.

You are responsible for obtaining consent from all meeting participants before recording.

## Storage and network access

- App data and temporary recording tracks live in `~/Library/Application Support/Antrum`.
- Local models live in `~/Library/Application Support/Antrum/Models`.
- Markdown is written only to a location you choose.
- Dictation does not keep history.
- Model downloads occur only after you choose Download. They use FluidAudio/Hugging Face; audio, transcripts, speaker labels, and calendar details are not sent.

Deleting `~/Library/Application Support/Antrum` removes local recordings, temporary artifacts, and downloaded models.
