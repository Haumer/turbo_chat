# TurboChat

TurboChat is a mountable Rails chat engine for server-rendered applications.

Status: actively maintained.

## What You Get

- Turbo Stream chat UI with two layout styles (bounded card or full-viewport).
- Role-based permissions with a swappable adapter.
- Mentions, invitations, inline message editing, and typing signals.
- Moderation: mute, timeout, ban, and message deletion.
- System messages for membership lifecycle events.
- Browser and server-side event hooks.

## Basic Setup

Add the gem:

```ruby
# Gemfile
gem "turbo_chat"
```

Install and migrate:

```bash
bundle install
bin/rails generate turbo_chat:install
bin/rails db:migrate
```

Mount the engine:

```ruby
# config/routes.rb
mount TurboChat::Engine => "/", as: "turbo_chat"
```

This mounts TurboChat at your app root.

Because the engine defines `root` as `chats#index`, both of these resolve to chat index:

- `/`
- `/chats`

Route helpers:

- `turbo_chat.root_path` -> `/`
- `turbo_chat.chats_path` -> `/chats`
- `turbo_chat.chat_path(chat)` -> `/chats/:id`
- `turbo_chat_path` -> the mount point (`/`)

## Host App Requirements

### 1. Mark your participant model

```ruby
class User < ApplicationRecord
  acts_as_chat_participant
end
```

This adds `has_many :chat_memberships` and the associations TurboChat needs to resolve participants in chats.

### 2. Resolve the current participant

If your app exposes `current_user` and it returns a model using `acts_as_chat_participant`, TurboChat works out of the box.

Resolution order:

1. Host `ApplicationController#current_chat_participant` (if defined)
2. `config.chat.current_participant_resolver` (if configured)
3. `current_user` (if available)
4. Raise `NotImplementedError`

For non-`current_user` auth:

```ruby
TurboChat.configure do |config|
  config.chat.current_participant_resolver = ->(controller) { controller.send(:current_member) }
end
```

## First Working Example

```ruby
chat = TurboChat::Chat.create!(title: "Support")
TurboChat::ChatMembership.create!(chat: chat, participant: current_user, role: :admin)
```

```erb
<%= link_to "Open chat", turbo_chat.chat_path(chat) %>
```

## Configuration

The installer generates a full initializer at `config/initializers/turbo_chat.rb` with every option documented. Start with the defaults and change only what you need.

Config is organized into scoped namespaces:

```ruby
TurboChat.configure do |config|
  # Limits
  config.chat.max_chat_participants = 10
  config.chat_message.max_message_length = 1000

  # Features
  config.chat_message.enable_mentions = true
  config.chat_message.blocked_words = []
  config.chat_message.blocked_words_action = :reject  # or :scramble

  # Layout
  config.style.chat_style = "chat_style_bounded"       # or "chat_style_unbounded"
  config.chat_message.message_insert_position = "append_end" # or "append_start"

  # Events (all opt-in, all false by default)
  config.events.emit_typing_events = true
  config.events.emit_message_events = true
end
```

Available scopes: `config.chat`, `config.chat_message`, `config.style`, `config.events`, `config.moderation`, `config.signals`. Flat aliases (e.g. `config.max_message_length`) still work for backward compatibility.

### Rate Limiting

TurboChat does not include built-in rate limiting. For production, add request throttling using middleware such as [rack-attack](https://github.com/rack/rack-attack).

## Roles and Permissions

### Built-in roles

| Role | Rank | Key capabilities |
|------|------|-----------------|
| `member` | 0 | View, post, mention members, edit own messages |
| `moderator` | 1 | + invite, `@all`/`@ROLE` mentions, mute/timeout/ban, delete messages |
| `admin` | 2 | + close/reopen chats, change member roles |

Higher-rank roles can act on lower-rank members but not on peers or above.

### Custom roles

```ruby
TurboChat.configure do |config|
  config.add_role(
    :support_agent,
    name: "Support Agent",
    rank: 1,
    permissions: %i[view_chat post_message delete_message]
  )
end
```

### Permission adapter

All access checks go through `config.chat.permission_adapter` (default: `TurboChat::Permission`). To customize, create a class that implements the same public interface:

```ruby
class CustomPermission < TurboChat::Permission
  def can_post_message?
    super && !participant.suspended?
  end
end

TurboChat.configure do |config|
  config.chat.permission_adapter = CustomPermission
end
```

The adapter must respond to: `can_view_chat?`, `can_create_chat?`, `can_post_message?`, `can_invite_member?`, `can_grant_member_permissions?`, `can_mute_member?`, `can_timeout_member?`, `can_ban_member?`, `can_delete_message?`, `can_edit_message?`, `can_close_chat?`, `can_reopen_chat?`.

## Invitations

Admins and moderators can invite participants through the members panel. The invited participant sees pending invitations on the chat index with Accept/Decline buttons.

Programmatic invitation:

```ruby
TurboChat::ChatMembership.create!(
  chat: chat,
  participant: invitee,
  role: :member,
  invitation_accepted: false
)
```

Accept/decline routes are built in: `PATCH /chats/:id/accept` and `PATCH /chats/:id/decline`.

## Message Ingest API

Post messages as a specific participant:

```ruby
TurboChat::Messages.send_message_as(
  current_user,
  chat,
  body: "Internal note",
  source: :app
)
```

External ingest with idempotency (`chat_id + source + external_id`):

```ruby
TurboChat::Messages.ingest_external!(
  chat: chat,
  participant: current_user,
  body: "Hello from WhatsApp",
  source: :whatsapp,
  external_id: webhook_payload.fetch("message_id"),
  sent_at: webhook_payload["sent_at"]
)
```

Duplicate webhook deliveries with the same `external_id` resolve to the existing message.

Source labels shown in message badges are configurable:

```ruby
config.chat_message.message_source_labels = {
  "app" => "In App",
  "whatsapp" => "WhatsApp",
  "sms_gateway" => "SMS"
}
```

## Moderation API

```ruby
TurboChat::Moderation.mute_member!(actor: moderator, membership: membership)
TurboChat::Moderation.unmute_member!(actor: moderator, membership: membership)
TurboChat::Moderation.timeout_member!(actor: moderator, membership: membership, until_time: 30.minutes.from_now)
TurboChat::Moderation.ban_member!(actor: moderator, membership: membership)
TurboChat::Moderation.delete_message!(actor: moderator, message: message)
TurboChat::Moderation.close_chat!(actor: admin, chat: chat)
TurboChat::Moderation.reopen_chat!(actor: admin, chat: chat)
```

All actions are permission-checked and generate system messages in the chat timeline. Mute, timeout, ban, and role changes are visible to all participants as system messages (disable with `config.chat.system_messages = false`).

Raises `TurboChat::Moderation::AuthorizationError` or `TurboChat::Moderation::InvalidActionError`.

## Signals API

```ruby
TurboChat::Signals.start!(chat: chat, participant: user, signal_type: :typing)
TurboChat::Signals.start!(chat: chat, participant: user, signal_type: :thinking)
TurboChat::Signals.start!(chat: chat, participant: user, signal_type: :planning)
TurboChat::Signals.custom!(chat: chat, participant: user, signal_text: "Reviewing your request")
TurboChat::Signals.clear!(chat: chat, participant: user)
```

Block form that auto-clears when the work finishes:

```ruby
TurboChat::Signals.with(chat: chat, participant: user, signal_type: :thinking) do
  # long-running operation
end
```

Signal lifetime is configurable via `config.signals.signal_ttl_seconds` (default: 60).

## Events

All event emissions are opt-in.

### Browser events (`CustomEvent` on `document`)

```ruby
config.events.emit_typing_events = true         # turbo-chat:typing-started, turbo-chat:typing-ended
config.events.emit_message_events = true         # turbo-chat:message-sent
config.events.emit_mention_events = true         # turbo-chat:mention
config.events.emit_invitation_events = true      # turbo-chat:invitation-accepted
config.events.emit_chat_lifecycle_events = true  # turbo-chat:chat-invited, chat-joined, chat-declined,
                                                 #   chat-left, chat-closed, chat-reopened
```

```js
document.addEventListener("turbo-chat:message-sent", function (event) {
  console.log(event.detail); // { chatId: "123" }
});
```

### Server-side events (`ActiveSupport::Notifications`)

```ruby
config.moderation.emit_moderation_events = true    # turbo_chat.moderation.member_muted, member_banned, ...
config.moderation.emit_blocked_words_events = true  # turbo_chat.blocked_words.detected, rejected, scrambled
```

```ruby
ActiveSupport::Notifications.subscribe(/turbo_chat\.moderation\./) do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  Rails.logger.info("[TurboChat] #{event.name} #{event.payload.inspect}")
end
```

## Theming

TurboChat ships a default theme built on CSS custom properties. Override them in your app stylesheet:

```css
:root {
  --chat-text: #12263f;
  --chat-muted: #5f738a;
  --chat-border: #c9d5e3;
  --chat-surface: #ffffff;
  --chat-surface-soft: #f6f9fd;
  --chat-primary: #1f6edc;
  --chat-primary-dark: #1452ac;
  --chat-primary-soft: #e7f1ff;
  --chat-danger: #b42318;
  --chat-danger-soft: #fff1f3;
  --chat-success: #1f7a40;
  --chat-success-soft: #ecfdf3;
  --chat-mention-highlight-color: #b42318;
  --chat-shadow: 0 20px 48px rgba(16, 36, 58, 0.12);
}
```

Additional style config:

```ruby
config.style.own_message_hex_color = "#e7f1ff"
config.style.other_message_hex_color = "#ffffff"
config.style.mention_mark_hex_color = "#b42318"
config.style.composer_placeholder_text = "Type a message..."
```

## Upgrade

```bash
bin/rails turbo_chat:install:migrations
bin/rails db:migrate
```

## Known Limitations

- **Stream subscriptions after member removal.** Turbo Stream subscriptions persist until page reload. A removed member may see new messages until they navigate away. Stream names are cryptographically signed so this is not a security issue.
- **Blocked word filtering.** Word-boundary matching can be bypassed with Unicode homoglyphs, zero-width characters, or leetspeak. Treat it as a first line of defense.
- **Invitable participants cap.** The invite picker returns at most 100 non-member participants. Larger user bases should provide a custom search endpoint.

## Dependencies

- Ruby `>= 3.1`
- Rails `>= 7.0`, `< 8.0`
- `turbo-rails` `>= 1.4`, `< 3.0`
