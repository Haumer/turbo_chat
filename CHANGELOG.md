# Changelog

All notable changes to `turbo_chat` will be documented in this file.

## [0.1.12] - 2026-02-26

### Added
- Configurable signal lifetime via `config.signal_ttl_seconds` (default `60`) so applications can keep typing/status indicators active longer.

### Changed
- Signal visibility/pruning now use the configured signal TTL consistently on both server-rendered active signals and client-side signal cleanup.
- Chat show renders signal TTL metadata for frontend pruning coordination.

## [0.1.11] - 2026-02-26

### Changed
- Smoothed signal-state transitions (for example: thinking to planning to typing) to reduce flicker during rapid updates.
- Updated signal Turbo Stream updates to use morphing so signal entries transition in place more smoothly.

## [0.1.10] - 2026-02-26

### Added
- Unbounded chat now supports a viewport-edge scrollbar proxy on the far right side of the screen while preserving inner chat layout.

### Changed
- Improved unbounded chat scrolling smoothness for wheel input and maintained synchronization between the edge scrollbar and message list position.
- Hardened page scroll locking for unbounded chat so the document does not scroll while chat remains scrollable.

## [0.1.9] - 2026-02-25

### Added
- Support improved mobile chat behavior to keep the composer pinned and visible on iOS-class viewports, with safer full-screen height handling.

### Changed
- Updated RubyGems metadata links to the `main` branch.

## [0.1.8] - 2026-02-23

### Added
- `TurboChat::Messages.send_message_as` and `TurboChat::Messages.ingest_external!` for permission-aware message ingest as a participant.
- Message source persistence (`source`, `external_id`, `sent_at`) with idempotency support for external providers.
- Configurable source label badges in chat UI via `config.message_source_labels`.
- Shared `TurboChat::ParticipantIdentity` utility for participant display and mention identity resolution.

### Changed
- Refactored member entries rendering to reuse helper-driven mention token generation and participant labeling.
- Internal participant naming/identifier logic now uses a centralized identity module across helpers and models.

## [0.1.7] - 2026-02-23

### Added
- Configurable custom signal-text sheen rendering via `config.signal_text_sheen` (default `true`).

### Changed
- Custom signal text now renders with bracketed sheen styling by default.

## [0.1.6] - 2026-02-22

### Fixed
- System invite browser-event tests now open the members panel before interacting with invite search inputs.
- Test event configuration reset now restores `show_members` to avoid cross-test config leakage.

## [0.1.5] - 2026-02-22

### Added
- Custom signal text support via `signal_type: :custom` and `signal_text`.
- `TurboChat::Signals.custom!` helper for explicit custom status updates.

### Changed
- Signal rendering now shows custom signal text in the live signals rail.

## [0.1.4] - 2026-02-22

### Added
- Searchable invite picker for chat invitations.
- Collapsible members panel with fixed-height member list shell.
- Role management and Turbo member list synchronization in chat UI.
- Lifecycle system messages for join/leave/moderation events.
- Config toggles for chat member visibility and composer controls.

### Changed
- Expanded initializer template guidance and README setup/docs.
- Refactored core chat modules for simpler internal structure.
- Improved invite row UX and chat composer behavior.

### Fixed
- Turbo Stream helper errors in member entry rendering.
- CI setup to prepare the test database before running `test:all`.

## [0.1.3] - 2026-02-19
- Initial RubyGems release.
