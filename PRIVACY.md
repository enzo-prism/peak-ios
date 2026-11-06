# Peak Privacy Policy

Peak is private by default. Your surf sessions live on your device. Peak requires no account and includes no analytics or tracking SDK.

## On-device data

Peak stores saved sessions, spots, gear, buddies, attached photos and videos, settings, a saved surf plan, and an unfinished new-session draft locally using SwiftData and app file storage. Draft recovery files remain until you save or discard the draft. A backup includes saved sessions and their media; save an unfinished draft before backing up.

Your logbook stays on your device unless you export it, share a session, or explicitly use the optional services below. Peak has no server for your logbook.

## Optional services and system features

### Conditions and surf plans

Auto-fill Conditions sends the session time window and the surf break's pinned coordinates to Open-Meteo's marine and weather APIs over HTTPS. Check conditions on the Best Window card requests a forecast for the selected pinned break. Automatic forecast refresh is off by default and runs only if you enable it in Settings.

These requests do not send notes, gear, buddies, photos or Health data. A saved plan is a cached forecast and setup, not a logged surf or continuous monitoring service.

The optional Station Tide Predictions action downloads NOAA CO-OPS station information and requests predictions using the confirmed station ID and date range. NOAA station predictions use MLLW; Peak keeps them separate from model sea level referenced to MSL.

### Location

Use My Location and map pins are optional. Peak uses them to place a surf break pin and enable conditions requests for that pin. A spot can have a name with no location. Your phone's location is not needed to log a surf.

### Apple Health

If you enable Apple Health, Peak can save logged surfs as workouts and read surfing workouts, heart rate, active calories and workout routes. Peak uses routes in memory for spot suggestions, wave estimates and replay, and stores the workout UUID rather than route coordinates in its logbook or backups.

Peak can observe new surfing workouts in the background to offer an unlogged surf. A separate notification toggle, off by default, enables local reminders. Peak has no push notification server. You can revoke Health permission in iOS Settings. Turning off Peak's Health integration stops its optional Health reads and observation.

### Voice logging

Speak your surf is optional. Microphone access is requested only after you choose Record Session. Supported speech transcription runs on the device. First use may download Apple's speech assets after your recording action; Peak does not send your audio to a transcription server or use a server fallback.

Recordings are limited to two minutes. Recording ends when Peak leaves the foreground. Temporary audio is removed after transcription or closing the review; audio left by a force quit is removed at the next app launch. You review the transcript and recognized fields before adding them to the draft. The transcript becomes a saved note only when you save the session.

### Search and Apple Intelligence

On iOS 18 and later, Peak donates saved session names, dates, ratings, durations and notes, plus spot and gear names, to its private on-device Spotlight index. Edits and deletions refresh that index.

Ask Peak computes counts and board usage directly from saved records. On eligible iOS 27 devices, optional related-memory search uses Apple's on-device model and the local index. Peak displays matching live source sessions rather than generated factual answers. It does not use cloud model providers or send your journal to an AI server.

### Photos, videos and chosen memories

The system Photos picker shares the photos and videos you select. Where available, Choose a Surf Memory uses Apple's Journaling Suggestions picker and imports only photos from the suggestion you choose, for review in the session draft. Peak does not scan your photo library or automatically create sessions from suggestions.

Media remains local unless you export a backup or share it yourself.

### Backups and sharing

JSON and CSV exports contain logbook records without attached media. Full `.peakbackup` files also contain saved photos and videos. Peak verifies new full backups and offers a Files destination that you choose. A cloud file provider may upload a file according to your chosen provider's settings; Peak does not start background cloud sync.

Peak does not encrypt exported files itself. Keep them in a location you trust and retain a copy outside the device to protect against losing it. Reset All Data clears Peak's local library, recovery draft, plan and timer; copies you previously exported remain wherever you saved them.

## Support

If you choose to email support, you decide which device details, screenshots or records to include. They are used to respond to your request.

Last updated: 2026-11-06
