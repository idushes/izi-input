# AGENTS.md

## Scope

These instructions apply to the entire repository.

## Project Context

Izi Input is a lightweight macOS menu bar app written in Swift. It records audio while the user holds Fn, runs local Whisper transcription/translation through `whisper-cli`, and inserts the selected output language into the active app by setting the clipboard and posting Cmd+V.

Core files:

- `src/AppDelegate.swift`: app lifecycle, status bar menu, Fn listener, recording, Whisper subprocess calls, paste simulation, notifications, and audio playback.
- `src/AudioInputState.swift`: shared observable state for recording, audio readiness, output language, last transcript, and playback.
- `src/OverlayView.swift`: recording overlay window and animated voice indicator.
- `src/SettingsView.swift`: SwiftUI settings UI for models, permissions, output language, and last recording.
- `src/ModelDownloader.swift`: Whisper model selection and downloads from Hugging Face.
- `Info.plist`: macOS bundle metadata and permission descriptions.
- `build.sh`: full local build script for `whisper.cpp`, Swift sources, app bundling, and ad hoc signing.

## Product Boundaries

- Do not make major changes to the product, architecture, API, UX, or business logic without explicit user confirmation.
- Preserve the app's local-first privacy model. Do not add cloud transcription, telemetry, analytics, remote logging, or external service calls without explicit confirmation.
- Treat audio capture, clipboard writes, Accessibility permissions, model download paths, and global key handling as sensitive behavior. Keep changes narrow and easy to review.
- Do not change the main interaction model, default hotkey behavior, output language semantics, or automatic paste behavior unless the user asks for it directly.

## Development Guidelines

- Prefer small, targeted Swift changes that match the existing AppKit/SwiftUI style.
- Keep user-facing strings consistent with the surrounding language in each view.
- Avoid introducing a package manager, new app architecture, or new runtime dependencies unless explicitly approved.
- Keep `whisper-cli` integration compatible with the bundled app resource path and the current local developer fallback.
- Keep build artifacts, downloaded external code, models, temp audio, and logs out of git.

## Build and Verification

- Full app build on Apple Silicon macOS:

```bash
./build.sh
```

- `build.sh` clones `whisper.cpp` if it is missing, compiles it, builds the Swift binary, creates `IziInput.app`, copies `Info.plist`, bundles `whisper-cli`, and ad hoc signs the app.
- For docs-only changes, an app build is not required. Run a lightweight sanity check such as:

```bash
git diff --check
```

- For runtime changes, smoke test the built app with:

```bash
open IziInput.app
```

Then verify the relevant flow manually: model availability, microphone permission, Fn recording, overlay state, Whisper output, selected language, clipboard/paste behavior, and Accessibility permission handling.

## Git Workflow

- Check `git status` before editing and before committing.
- Do not revert or overwrite unrelated user changes.
- Commit and push completed changes unless the user explicitly says not to.
- Do not amend, rebase, force push, reset, or run destructive git commands without explicit user confirmation.
