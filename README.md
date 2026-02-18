# ChatGem

Mountable Rails engine gem for lightweight, realtime chats using Turbo Streams.

## Sections

- [Quick Start](#quick-start-)
- [Host App Contract](#host-app-contract)
- [Feature Overview](#feature-overview-)
- [Configuration](#configuration)
- [Chat Lifecycle](#chat-lifecycle)
- [Mentions and Emoji](#mentions-and-emoji)
- [Styling and Custom Markup](#styling-and-custom-markup-)
- [Rich HTML Message Rendering](#rich-html-message-rendering)
- [Browser Events](#browser-events)
- [Participants, Roles, and Moderation](#participants-roles-and-moderation)
- [Programmatic Signals](#programmatic-signals)

## Quick Start 🚀

1. Add the gem to your host app:

```ruby
# Gemfile
gem "chat_gem"
```

2. Install and copy setup files:

```bash
bundle install
bin/rails generate chat_gem:install
bin/rails db:migrate
```

3. Mount the engine:

```ruby
# config/routes.rb
mount ChatGem::Engine => "/chat"
```

## Host App Contract

### Participant models

Any model that should join chats must call `acts_as_chat_participant`:

```ruby
class User < ApplicationRecord
  acts_as_chat_participant
end
```

### Current participant

Expose the current participant from your host `ApplicationController`:

```ruby
class ApplicationController < ActionController::Base
  helper_method :chat_current_participant

  def chat_current_participant
    Current.user
  end
end
```

`chat_current_participant` must return a model using `acts_as_chat_participant`, or `nil` for unauthenticated sessions.

## Feature Overview ✨

- Mountable chat UI with Turbo Stream updates.
- Message rows + signal rows (`typing`, `thinking`, `planning`).
- Role-aware permissions, mentions, moderation, and chat close/reopen.
- Configurable styling and optional sanitized HTML rendering.
- Optional browser events for typing and message submit lifecycle.
- Programmatic signal helpers for API/AI workflows.

## Configuration

### Key options by concern

#### Access and limits

- `config.permission_adapter` (`ChatGem::Permission` by default).
- `config.max_chat_participants` (`10` by default).
- `config.max_message_length` (`1000` by default).
- `config.message_history_limit` (`200` by default; set `nil` or `0` to disable).

#### Behavior and lifecycle

- `config.active_chat_window` (`5.minutes` by default).
- `config.show_self_signals` (`false` by default).
- `config.replace_signals_on_message_submit` (`false` by default).

#### Mentions and emoji

- `config.enable_mentions` (`true` by default).
- `config.enable_emoji_aliases` (`true` by default).
- `config.emoji_aliases` (`ChatGem::Configuration::DEFAULT_EMOJI_ALIASES.dup` by default).

#### Rendering and styling

- `config.show_timestamp` (`true` by default).
- `config.show_role` (`false` by default).
- `config.own_message_hex_color`, `config.other_message_hex_color` (`nil` by default).
- `config.role_message_hex_colors` (`{}` by default).
- `config.message_css_class_resolver` (`nil` by default).
- `config.render_message_html` (`false` by default).
- `config.message_html_tags` (`%w[a b br code em i li ol p pre strong ul]` by default).
- `config.message_html_attributes` (`%w[href target rel class]` by default).
- `config.timestamp_formatter` (`->(timestamp, _chat_message) { I18n.l(timestamp.in_time_zone, format: :long) }` by default).
- `config.role_formatter` (`->(role, _chat_message) { role.to_s.humanize }` by default).

#### Browser events

- `config.emit_typing_events` (`false` by default).
- `config.emit_message_events` (`false` by default).

<details>
<summary>Full default initializer</summary>

```ruby
ChatGem.configure do |config|
  config.permission_adapter = ChatGem::Permission
  config.max_chat_participants = 10
  config.max_message_length = 1000
  config.message_history_limit = 200
  config.enable_mentions = true
  config.enable_emoji_aliases = true
  config.emoji_aliases = ChatGem::Configuration::DEFAULT_EMOJI_ALIASES.dup
  config.own_message_hex_color = nil
  config.other_message_hex_color = nil
  config.role_message_hex_colors = {}
  config.show_timestamp = true
  config.show_role = false
  config.active_chat_window = 5.minutes
  config.emit_typing_events = false
  config.emit_message_events = false
  config.show_self_signals = false
  config.replace_signals_on_message_submit = false
  config.message_css_class_resolver = nil
  config.render_message_html = false
  config.message_html_tags = %w[a b br code em i li ol p pre strong ul]
  config.message_html_attributes = %w[href target rel class]
  config.timestamp_formatter = ->(timestamp, _chat_message) { I18n.l(timestamp.in_time_zone, format: :long) }
  config.role_formatter = ->(role, _chat_message) { role.to_s.humanize }
end
```

</details>

## Chat Lifecycle

A chat is considered active when it has a regular message within the configured window (`config.active_chat_window`).
Signal rows do not count as activity. Closed chats (`closed_at` set) remain viewable but cannot receive new messages.

```ruby
ChatGem.configure do |config|
  config.active_chat_window = 5.minutes
end

chat.active?    # => true/false
chat.inactive?  # => true/false

ChatGem::Chat.active
ChatGem::Chat.inactive
ChatGem::Chat.active(window: 10.minutes)
```

## Mentions and Emoji

Mention suggestions are built from active chat memberships and can include:

- member handles such as `@alex`
- `@all`
- role targets such as `@ADMIN` and `@MODERATOR`

Mentions are permission-filtered and server-validated:

- `:mention_member` controls member handles.
- `:mention_all` controls `@all`.
- `:mention_role` controls role mentions.

Emoji aliases are enabled by default for plain-text message rendering.

```ruby
ChatGem.configure do |config|
  config.add_emoji_alias(:shipit, "🚢")
  config.add_emoji_alias("party_parrot", "🦜")
end
```

```ruby
ChatGem.configure do |config|
  config.emoji_aliases = ChatGem::Configuration::DEFAULT_EMOJI_ALIASES.merge(
    "shipit" => "🚢",
    "party_parrot" => "🦜"
  )
end
```

## Styling and Custom Markup 🎨

### Bubble colors

```ruby
ChatGem.configure do |config|
  config.own_message_hex_color = "#c9f2ff"
  config.other_message_hex_color = "#f6f8fb"
  config.role_message_hex_colors = {
    admin: "#ffe6e6",
    moderator: { own: "#fff0c2", other: "#fff7de" },
    support_agent: { default: "#e9f8ff" }
  }
end
```

Role-specific colors override own/other defaults. Invalid hex values are ignored.

### CSS class resolver (basic)

```ruby
ChatGem.configure do |config|
  config.message_css_class_resolver = ->(_chat_message, own_message) {
    own_message ? "msg-card msg-card--own" : "msg-card msg-card--other"
  }
end
```

```html
<article id="chat_gem_chat_message_42" class="chat-bubble chat-bubble--own msg-card msg-card--own">
  <header class="chat-meta">
    <span class="chat-meta__author">you@example.com</span>
    <time datetime="2026-02-18T16:40:00Z">February 18, 2026 4:40 PM</time>
  </header>
  <p class="chat-body">Hello world</p>
</article>
```

### CSS class resolver (role-aware)

```ruby
ChatGem.configure do |config|
  config.message_css_class_resolver = lambda { |chat_message, own_message|
    classes = ["msg-card"]
    classes << (own_message ? "msg-card--own" : "msg-card--other")
    classes << "msg-card--role-#{chat_message.participant_membership_role}" if chat_message.participant_membership_role.present?
    classes << "msg-card--long" if chat_message.body.to_s.length > 280
    classes
  }
end
```

### Full markup override

`message_css_class_resolver` controls classes only. To change structure, override the message partial in your host app.

1. Create `app/views/chat_gem/chat_messages/_message.html.erb`.
2. Copy the engine partial and customize it.
3. Keep `id="<%= dom_id(chat_message) %>"` on the wrapper so Turbo updates/removals keep working.

```erb
<% own_message = own_chat_message?(chat_message) %>
<% show_timestamp = ChatGem.configuration.show_timestamp %>
<article id="<%= dom_id(chat_message) %>" class="<%= chat_message_css_classes(chat_message: chat_message, own_message: own_message) %>">
  <div class="msg-card__header">
    <span class="chat-meta__author"><%= chat_message.participant_display_name %></span>
    <% if show_timestamp %>
      <time datetime="<%= chat_message.created_at.iso8601 %>"><%= chat_message.formatted_timestamp %></time>
    <% end %>
  </div>

  <div class="msg-card__body">
    <%= render_chat_message_body(chat_message) %>
  </div>

  <div class="msg-card__footer">
    <!-- custom badges/actions -->
  </div>
</article>
```

## Rich HTML Message Rendering

Enable sanitized HTML rendering for message bodies:

```ruby
ChatGem.configure do |config|
  config.render_message_html = true
  config.message_html_tags = %w[a b br code em i li ol p pre strong ul]
  config.message_html_attributes = %w[href target rel class]
end
```

Extend the allowlist as needed:

```ruby
ChatGem.configure do |config|
  config.render_message_html = true
  config.message_html_tags = ChatGem::Configuration::DEFAULT_MESSAGE_HTML_TAGS + %w[blockquote h4 mark]
  config.message_html_attributes = ChatGem::Configuration::DEFAULT_MESSAGE_HTML_ATTRIBUTES + %w[title]
end
```

Given:

```html
<h4 title="notice">Update</h4><blockquote><mark>Done</mark></blockquote><u>underline</u>
```

Rendered/sanitized output:

```html
<h4 title="notice">Update</h4><blockquote><mark>Done</mark></blockquote>underline
```

## Browser Events

### Typing lifecycle events

```ruby
ChatGem.configure do |config|
  config.emit_typing_events = true
end
```

```js
document.addEventListener("chat-gem:typing-started", function (event) {
  // event.detail.chatId
});

document.addEventListener("chat-gem:typing-ended", function (event) {
  // event.detail.chatId
});
```

### Message sent event

```ruby
ChatGem.configure do |config|
  config.emit_message_events = true
end
```

```js
document.addEventListener("chat-gem:message-sent", function (event) {
  // event.detail.chatId
});
```

## Participants, Roles, and Moderation

Use `ChatGem::ChatMembership` to add participants to a chat.
Any model using `acts_as_chat_participant` works (users, bots, service accounts).

```ruby
chat = ChatGem::Chat.find(chat_id)
participant = User.find(user_id)

ChatGem::ChatMembership.find_or_create_by!(chat: chat, participant: participant) do |membership|
  membership.role = :member
end
```

Configure participant limits:

```ruby
ChatGem.configure do |config|
  config.max_chat_participants = 10
  # Set to nil or 0 to disable the limit.
end
```

Built-in roles: `:member`, `:moderator`, `:admin`.

- `member`: view chat, post messages, mention members.
- `moderator`: member abilities plus invites, `@all`, `@ROLE`, mute/timeout/ban members, and delete member messages.
- `admin`: moderator abilities plus moderating moderators and closing/reopening chats.

Custom role registration:

```ruby
ChatGem.configure do |config|
  config.add_role(
    :support_agent,
    name: "Support Agent",
    rank: 1,
    permissions: %i[view_chat post_message delete_message]
  )
end
```

Assign a custom role:

```ruby
membership = ChatGem::ChatMembership.find_or_create_by!(chat: chat, participant: participant)
membership.role_key = :support_agent
membership.save!
```

Available permissions:
`:view_chat`, `:post_message`, `:mention_member`, `:mention_all`, `:mention_role`, `:invite_member`, `:mute_member`, `:timeout_member`, `:ban_member`, `:delete_message`, `:close_chat`, `:reopen_chat`

Higher `rank` can moderate lower `rank` (never self).

If a participant was removed (`removed_at` set), reactivate that membership:

```ruby
membership = ChatGem::ChatMembership.find_by!(chat: chat, participant: participant)
membership.update!(removed_at: nil, muted: false, timed_out_until: nil)
```

Use moderation service APIs for role-checked actions:

```ruby
chat = ChatGem::Chat.find(chat_id)
moderator = User.find(moderator_id)
member_membership = chat.chat_memberships.find_by!(participant_id: member_id, participant_type: "User")

ChatGem::Moderation.mute_member!(actor: moderator, membership: member_membership)
ChatGem::Moderation.timeout_member!(actor: moderator, membership: member_membership, until_time: 30.minutes.from_now)
ChatGem::Moderation.ban_member!(actor: moderator, membership: member_membership)
ChatGem::Moderation.delete_message!(actor: moderator, message: chat.chat_messages.find(message_id))

admin = User.find(admin_id)
ChatGem::Moderation.close_chat!(actor: admin, chat: chat)
ChatGem::Moderation.reopen_chat!(actor: admin, chat: chat)
```

## Programmatic Signals

Use signal helpers when a participant is working on an async/API step.

```ruby
chat = ChatGem::Chat.find(chat_id)
participant = User.find(user_id)

ChatGem::Signals.start!(chat: chat, participant: participant, signal_type: :thinking)
answer = ExternalAiClient.answer(prompt)
ChatGem::Signals.clear!(chat: chat, participant: participant)

ChatGem::ChatMessage.create!(
  chat: chat,
  participant: participant,
  kind: :message,
  body: answer
)
```

Replace signal state:

```ruby
ChatGem::Signals.start!(chat: chat, participant: participant, signal_type: :thinking)
ChatGem::Signals.replace!(chat: chat, participant: participant, signal_type: :planning)
```

Auto-clear signals with a block:

```ruby
answer = ChatGem::Signals.with(chat: chat, participant: participant, signal_type: :thinking) do
  ExternalAiClient.answer(prompt)
end

ChatGem::ChatMessage.create!(
  chat: chat,
  participant: participant,
  kind: :message,
  body: answer
)
```
