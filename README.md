# TurboChat

TurboChat is a mountable Rails chat engine for server-rendered applications.

Status: actively maintained.

## What You Get

- Turbo Stream chat UI.
- Role-based permissions.
- Mentions, invitations, moderation, and typing signals.
- A Rails-first path to ship chat quickly.

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

### 2. Resolve the current participant

You can define `current_chat_participant` in your host `ApplicationController`.
If you already expose `current_user` and it returns a model using `acts_as_chat_participant`, TurboChat works without adding this method.

Recommended hook:

```ruby
class ApplicationController < ActionController::Base
  def current_chat_participant
    current_user
  end
end
```

Resolution order:

1. Host `ApplicationController#current_chat_participant` (if defined)
2. `config.current_participant_resolver` (if configured)
3. `current_user` (if available)
4. Raise `NotImplementedError`

Optional resolver for non-`current_user` auth:

```ruby
TurboChat.configure do |config|
  config.current_participant_resolver = ->(controller) { controller.send(:current_member) }
end
```

## First Working Example

Create a chat and add an admin membership:

```ruby
chat = TurboChat::Chat.create!(title: "Support")
TurboChat::ChatMembership.create!(chat: chat, participant: current_user, role: :admin)
```

Link to it:

```erb
<%= link_to "Open chat", turbo_chat.chat_path(chat) %>
```

## Essential Configuration

Start with a minimal initializer and only expand when needed:

```ruby
TurboChat.configure do |config|
  config.permission_adapter = TurboChat::Permission

  config.max_chat_participants = 10
  config.max_message_length = 1000
  config.message_history_limit = 200

  config.enable_mentions = true
  config.enable_emoji_aliases = true

  config.blocked_words = []
  config.blocked_words_action = :reject # or :scramble

  config.render_message_html = false
  config.show_timestamp = true
  config.show_role = false
  config.message_source_labels = TurboChat::Configuration::DEFAULT_MESSAGE_SOURCE_LABELS.dup
  config.signal_text_sheen = true

  config.emit_moderation_events = false
  config.emit_blocked_words_events = false
  config.emit_mention_events = false
end
```

## Message Ingest API

Post messages as a specific participant, including external sources like WhatsApp:

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

`external_id` is required for `ingest_external!` so duplicate webhook deliveries can resolve to the same stored message.

Source labels shown in message badges are configurable:

```ruby
TurboChat.configure do |config|
  config.message_source_labels = {
    "app" => "In App",
    "whatsapp" => "WhatsApp",
    "sms_gateway" => "SMS"
  }
end
```

## Roles

Built-in roles:

- `member`
- `moderator`
- `admin`

Role behavior:

- `member`: can view/post and mention members.
- `moderator`: can invite, mention `@all`/roles, mute/timeout/ban, and delete lower-rank messages.
- `admin`: can do moderator actions plus close/reopen chats.

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

## Moderation API

```ruby
TurboChat::Moderation.mute_member!(actor: moderator, membership: membership)
TurboChat::Moderation.timeout_member!(actor: moderator, membership: membership, until_time: 30.minutes.from_now)
TurboChat::Moderation.ban_member!(actor: moderator, membership: membership)
TurboChat::Moderation.delete_message!(actor: moderator, message: message)
TurboChat::Moderation.close_chat!(actor: admin, chat: chat)
TurboChat::Moderation.reopen_chat!(actor: admin, chat: chat)
```

Raises:

- `TurboChat::Moderation::AuthorizationError`
- `TurboChat::Moderation::InvalidActionError`

## Signals API

```ruby
TurboChat::Signals.start!(chat: chat, participant: current_user, signal_type: :typing)
TurboChat::Signals.start!(chat: chat, participant: current_user, signal_type: :custom, signal_text: "Hello")
TurboChat::Signals.custom!(chat: chat, participant: current_user, signal_text: "Reviewing your request")
TurboChat::Signals.clear!(chat: chat, participant: current_user)
```

## Event Emissions

All event emissions are opt-in.

Enable only what you consume:

```ruby
TurboChat.configure do |config|
  config.emit_typing_events = true
  config.emit_message_events = true
  config.emit_mention_events = true
  config.emit_invitation_events = true
  config.emit_chat_lifecycle_events = true
  config.emit_moderation_events = true
  config.emit_blocked_words_events = true
end
```

Browser events (`CustomEvent`):

- `emit_typing_events`: `turbo-chat:typing-started`, `turbo-chat:typing-ended`
- `emit_message_events`: `turbo-chat:message-sent`
- `emit_mention_events`: `turbo-chat:mention`
- `emit_invitation_events`: `turbo-chat:invitation-accepted`
- `emit_chat_lifecycle_events`: `turbo-chat:chat-invited`, `turbo-chat:chat-joined`, `turbo-chat:chat-declined`, `turbo-chat:chat-left`, `turbo-chat:chat-closed`, `turbo-chat:chat-reopened`

Minimal browser listener:

```js
[
  "turbo-chat:typing-started",
  "turbo-chat:typing-ended",
  "turbo-chat:message-sent",
  "turbo-chat:mention",
  "turbo-chat:invitation-accepted",
  "turbo-chat:chat-invited",
  "turbo-chat:chat-joined",
  "turbo-chat:chat-declined",
  "turbo-chat:chat-left",
  "turbo-chat:chat-closed",
  "turbo-chat:chat-reopened"
].forEach(function (eventName) {
  document.addEventListener(eventName, function (event) {
    console.log(eventName, event.detail);
  });
});
```

Server-side notifications (`ActiveSupport::Notifications`):

- `emit_moderation_events`:
  `turbo_chat.moderation.member_muted`,
  `turbo_chat.moderation.member_unmuted`,
  `turbo_chat.moderation.member_timed_out`,
  `turbo_chat.moderation.member_timeout_cleared`,
  `turbo_chat.moderation.member_banned`,
  `turbo_chat.moderation.message_deleted`,
  `turbo_chat.moderation.chat_closed`,
  `turbo_chat.moderation.chat_reopened`
- `emit_blocked_words_events`:
  `turbo_chat.blocked_words.detected`,
  `turbo_chat.blocked_words.rejected`,
  `turbo_chat.blocked_words.scrambled`

Minimal Rails listener:

```ruby
ActiveSupport::Notifications.subscribe(/turbo_chat\.(moderation|blocked_words)\./) do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  Rails.logger.info("[TurboChat] #{event.name} #{event.payload.inspect}")
end
```

## Upgrade

```bash
bin/rails turbo_chat:install:migrations
bin/rails db:migrate
```

## Dependencies

- Ruby `>= 3.1`
- Rails `>= 7.0`, `< 8.0`
- `turbo-rails` `>= 1.4`, `< 3.0`
