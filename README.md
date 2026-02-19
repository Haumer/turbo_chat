# TurboChat

TurboChat is a mountable Rails chat engine for server-rendered apps.

What you get:
- Turbo Stream chat UI.
- Role-based permissions.
- Mentions, typing signals, invites, moderation.
- Practical customization hooks without rewriting everything.

What this is not:
- A hosted chat service.
- A React-first component library.
- A "just add JS" widget.

## Use This If

Use TurboChat if your app is Rails-first and you want chat now, not after building a custom permission/event/moderation system.

Skip it if you want fully custom frontend architecture from day one.

## Install

```ruby
# Gemfile
gem "turbo_chat"
```

```bash
bundle install
bin/rails generate turbo_chat:install
bin/rails db:migrate
```

Mount with an explicit helper prefix:

```ruby
# config/routes.rb
mount TurboChat::Engine => "/chat", as: "turbo_chat"
```

Opinionated recommendation: mount under `/chat` (or another scoped path), not root.

## Participant Resolution (Most Important Section)

This is where installs usually fail. TurboChat now resolves the current participant in this order:

1. `current_chat_participant` on your host `ApplicationController` (preferred explicit hook).
2. `config.current_participant_resolver` (custom resolver lambda).
3. `current_user` (if your app exposes it).

If none are available, TurboChat raises `NotImplementedError` with guidance.

Return value must be:
- `nil` (unauthenticated), or
- a model that uses `acts_as_chat_participant`.

If you use Devise and your `User` model is a chat participant, this works out of the box.

## Host Contract

### Participant model opt-in

```ruby
class User < ApplicationRecord
  acts_as_chat_participant
end
```

### Optional explicit hook (recommended for clarity)

```ruby
class ApplicationController < ActionController::Base
  def current_chat_participant
    current_user
  end
end
```

### Optional custom resolver (for non-`current_user` auth)

```ruby
TurboChat.configure do |config|
  config.current_participant_resolver = ->(controller) { controller.send(:current_member) }
end
```

## First Working Usage

```ruby
chat = TurboChat::Chat.create!(title: "Support")
TurboChat::ChatMembership.create!(chat: chat, participant: current_user, role: :admin)
```

```erb
<%= link_to "Open chat", turbo_chat.chat_path(chat) %>
```

## Routes You Actually Need

From the mounted engine:
- `GET /chats`
- `GET /chats/:id`
- `POST /chats`
- `PATCH /chats/:id/accept`
- `PATCH /chats/:id/decline`
- `PATCH /chats/:id/leave`
- `PATCH /chats/:id/close`
- `PATCH /chats/:id/reopen`
- `POST /chats/:chat_id/chat_memberships`
- `POST /chats/:chat_id/chat_messages`
- `PATCH /chats/:chat_id/chat_messages/:id`

## Recommended Baseline Config

Keep this simple initially:

```ruby
TurboChat.configure do |config|
  config.permission_adapter = TurboChat::Permission

  config.max_chat_participants = 10
  config.max_message_length = 1000
  config.message_history_limit = 200
  config.active_chat_window = 5.minutes

  config.enable_mentions = true
  config.mention_filter_exclude_self = true
  config.mention_filter_hide_roles = true
  config.enable_emoji_aliases = true

  config.blocked_words = []
  config.blocked_words_action = :reject # or :scramble

  config.render_message_html = false
  config.show_timestamp = true
  config.show_role = false

  config.emit_typing_events = false
  config.emit_message_events = false
  config.emit_mention_events = false
  config.emit_invitation_events = false
  config.emit_chat_lifecycle_events = false
  config.emit_moderation_events = false
  config.emit_blocked_words_events = false
end
```

Opinionated defaults:
- Leave HTML rendering off unless required.
- Leave event emission off unless consumed.
- Keep permissions adapter default until you have a concrete policy gap.

## Roles and Permissions

Built-in roles:
- `member`
- `moderator`
- `admin`

Behavior summary:
- `member`: view/post and member mentions.
- `moderator`: invite, `@all`, role mentions, mute/timeout/ban, delete lower-rank messages.
- `admin`: moderator powers plus close/reopen chat.

Hard rules:
- Moderation is rank-based.
- No self-moderation.
- Closed chat blocks posting.
- Muted/timed-out members cannot post.

Custom role example:

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

## Invitations

- Invite creation: `POST /chats/:chat_id/chat_memberships`
- Accept: `PATCH /chats/:id/accept`
- Decline: `PATCH /chats/:id/decline`

Important constraints:
- Invite type must match inviter participant base class.
- Participant limits apply to active memberships.
- Re-invite reactivates existing memberships.

## Messages, Mentions, Signals

### Messages
- Realtime append/update/remove via Turbo Streams.
- Inline edit for your own messages (permission-gated).
- History capped by `message_history_limit`.

### Mentions
- `@username`, `@all`, `@ROLE`.
- Server-side mention permission validation.
- Autocomplete defaults: excludes self, hides roles.

### Signals
Automatic typing loop is built in.

Manual APIs:

```ruby
TurboChat::Signals.start!(chat: chat, participant: current_user, signal_type: :thinking)
TurboChat::Signals.replace!(chat: chat, participant: current_user, signal_type: :planning)
TurboChat::Signals.clear!(chat: chat, participant: current_user)
```

```ruby
TurboChat::Signals.with(chat: chat, participant: current_user, signal_type: :thinking) do
  # work
end
```

## Moderation API

```ruby
TurboChat::Moderation.mute_member!(actor: moderator, membership: membership)
TurboChat::Moderation.unmute_member!(actor: moderator, membership: membership)
TurboChat::Moderation.timeout_member!(actor: moderator, membership: membership, until_time: 30.minutes.from_now)
TurboChat::Moderation.clear_timeout!(actor: moderator, membership: membership)
TurboChat::Moderation.ban_member!(actor: moderator, membership: membership)
TurboChat::Moderation.delete_message!(actor: moderator, message: message)
TurboChat::Moderation.close_chat!(actor: admin, chat: chat)
TurboChat::Moderation.reopen_chat!(actor: admin, chat: chat)
```

Raises:
- `TurboChat::Moderation::AuthorizationError`
- `TurboChat::Moderation::InvalidActionError`

## Browser Events

Enable with config flags.

Event names:
- `turbo-chat:typing-started`
- `turbo-chat:typing-ended`
- `turbo-chat:message-sent`
- `turbo-chat:mention`
- `turbo-chat:invitation-accepted`
- `turbo-chat:chat-invited`
- `turbo-chat:chat-joined`
- `turbo-chat:chat-declined`
- `turbo-chat:chat-left`
- `turbo-chat:chat-closed`
- `turbo-chat:chat-reopened`

```js
document.addEventListener("turbo-chat:message-sent", function (event) {
  console.log(event.detail.chatId);
});
```

Client namespace: `window.TurboChatUI`

## ActiveSupport::Notifications

Moderation (`emit_moderation_events = true`):
- `turbo_chat.moderation.member_muted`
- `turbo_chat.moderation.member_unmuted`
- `turbo_chat.moderation.member_timed_out`
- `turbo_chat.moderation.member_timeout_cleared`
- `turbo_chat.moderation.member_banned`
- `turbo_chat.moderation.message_deleted`
- `turbo_chat.moderation.chat_closed`
- `turbo_chat.moderation.chat_reopened`

Blocked words (`emit_blocked_words_events = true`):
- `turbo_chat.blocked_words.detected`
- `turbo_chat.blocked_words.rejected`
- `turbo_chat.blocked_words.scrambled`

## UI Customization

Do this in order:
1. Theme with config (`own_message_hex_color`, `role_message_hex_colors`, `mention_mark_hex_color`, formatters).
2. Add class-level customization via `message_css_class_resolver`.
3. Only then override markup partials.

Primary partial override point:
- `app/views/turbo_chat/chat_messages/_message.html.erb`

Keep `id="<%= dom_id(chat_message) %>"` on the message wrapper or Turbo replacements break.

## Internal Names

Use `TurboChat` in app code.

These are implementation identifiers used by the engine:
- Engine namespace in source: `TurboChat`
- Database table prefix: `turbo_chat_`
- Browser event prefix: `turbo-chat:*`
- `ActiveSupport::Notifications` prefix: `turbo_chat.*`

Mount with `as: "turbo_chat"` and use `turbo_chat.*` route helpers.

## Upgrade

```bash
bin/rails turbo_chat:install:migrations
bin/rails db:migrate
```

## Dependencies

- Ruby `>= 3.1`
- Rails `>= 7.0`, `< 8.0`
- `turbo-rails` `>= 1.4`, `< 3.0`
- PostgreSQL or SQLite

## Development

```bash
bundle exec rake test
```
