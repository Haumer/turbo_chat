# ChatGem

Mountable Rails engine gem for lightweight, realtime chats using Turbo Streams.

## Table of Contents

- [Quick Start](#quick-start)
- [Host App Contract](#host-app-contract)
- [Simple Example](#simple-example)
- [Feature Overview](#feature-overview)
- [Configuration](#configuration)
- [Core Concepts](#core-concepts)
  - [Chat Lifecycle](#chat-lifecycle)
  - [Mentions and Emoji](#mentions-and-emoji)
- [UI Customization](#ui-customization)
  - [Styling and Custom Markup](#styling-and-custom-markup)
  - [Rich HTML Message Rendering](#rich-html-message-rendering)
  - [Browser Events](#browser-events)
- [Participants, Roles, and Moderation](#participants-roles-and-moderation)
- [Programmatic Signals](#programmatic-signals)
- [Dependencies](#dependencies)
- [Maintainer](#maintainer)

## Quick Start

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

When upgrading `chat_gem`, also install engine migrations in the host app before migrating:

```bash
bin/rails chat_gem:install:migrations
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

## Simple Example

Create a chat, add the current participant, and link to the chat view:

```ruby
chat = ChatGem::Chat.create!(title: "Support")
ChatGem::ChatMembership.create!(chat: chat, participant: Current.user, role: :member)
```

```erb
<%= link_to "Open chat", chat_gem.chat_path(chat) %>
```

`chat_gem` is the default route helper prefix when mounted as `mount ChatGem::Engine => "/chat"`.

## Feature Overview

- Mountable chat UI with Turbo Stream updates.
- Message rows + signal rows (`typing`, `thinking`, `planning`).
- Role-aware permissions, mentions, moderation, and chat close/reopen.
- Configurable styling and optional sanitized HTML rendering.
- Optional browser events for typing and message submit lifecycle.
- Programmatic signal helpers for user-facing typing/thinking/planning states.

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
- `config.replace_signals_on_message_submit` (`false` by default; clears a participant's existing signals when they submit a regular message).

#### Mentions and emoji

- `config.enable_mentions` (`true` by default).
- `config.mention_filter_exclude_self` (`true` by default; hides current participant from mention autocomplete options).
- `config.mention_filter_hide_roles` (`true` by default; hides role mention options like `@ADMIN` from autocomplete).
- `config.enable_emoji_aliases` (`true` by default).
- `config.emoji_aliases` (`ChatGem::Configuration::DEFAULT_EMOJI_ALIASES.dup` by default).
- `config.blocked_words` (`[]` by default).
- `config.blocked_words_action` (`:reject` by default; supports `:reject` or `:scramble`).

#### Rendering and styling

- `config.show_timestamp` (`true` by default).
- `config.show_role` (`false` by default).
- `config.mention_mark_hex_color` (`nil` by default; sets viewer-targeted mention mark background color).
- `config.mention_highlight_hex_color` (`nil` by default; backward-compatible alias for mention mark color).
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
- `config.emit_mention_events` (`false` by default).
- `config.emit_invitation_events` (`false` by default).

<details>
<summary>Full default initializer</summary>

```ruby
ChatGem.configure do |config|
  config.permission_adapter = ChatGem::Permission
  config.max_chat_participants = 10
  config.max_message_length = 1000
  config.message_history_limit = 200
  config.enable_mentions = true
  config.mention_filter_exclude_self = true
  config.mention_filter_hide_roles = true
  config.enable_emoji_aliases = true
  config.emoji_aliases = ChatGem::Configuration::DEFAULT_EMOJI_ALIASES.dup
  config.blocked_words = []
  config.blocked_words_action = :reject
  config.mention_mark_hex_color = nil
  config.mention_highlight_hex_color = nil
  config.own_message_hex_color = nil
  config.other_message_hex_color = nil
  config.role_message_hex_colors = {}
  config.show_timestamp = true
  config.show_role = false
  config.active_chat_window = 5.minutes
  config.emit_typing_events = false
  config.emit_message_events = false
  config.emit_mention_events = false
  config.emit_invitation_events = false
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

## Core Concepts

### Chat Lifecycle

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

### Mentions and Emoji

Mention suggestions are built from active chat memberships and can include:

- member handles such as `@username`
- `@all`
- role targets such as `@ADMIN` and `@MODERATOR` (hidden by default in autocomplete; enable via `config.mention_filter_hide_roles = false`)

By default, autocomplete also excludes the current participant (`config.mention_filter_exclude_self = true`).

Mentions are permission-filtered and server-validated:

- `:mention_member` controls member handles.
- `:mention_all` controls `@all`.
- `:mention_role` controls role mentions.

Emoji aliases are enabled by default for plain-text message rendering.

#### Add aliases incrementally

```ruby
ChatGem.configure do |config|
  config.add_emoji_alias(:shipit, "🚢")
  config.add_emoji_alias("party_parrot", "🦜")
end
```

#### Override alias map

```ruby
ChatGem.configure do |config|
  config.emoji_aliases = ChatGem::Configuration::DEFAULT_EMOJI_ALIASES.merge(
    "shipit" => "🚢",
    "party_parrot" => "🦜"
  )
end
```

#### Blocked words moderation

Configure blocked words and choose whether to reject messages or scramble blocked words.

`scramble` now shuffles the blocked word's own characters (for example, `badword` -> `darbwod`).

```ruby
ChatGem.configure do |config|
  config.blocked_words = %w[foo bar]
  config.blocked_words_action = :reject
end
```

```ruby
ChatGem.configure do |config|
  config.blocked_words = %w[foo bar]
  config.blocked_words_action = :scramble
end
```

## UI Customization

### Styling and Custom Markup

#### Bubble colors

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

Viewer-targeted mentions can be color-customized:

```ruby
ChatGem.configure do |config|
  config.mention_mark_hex_color = "#cf1322"
end
```

#### CSS class resolver (basic)

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

#### CSS class resolver (role-aware)

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

#### Full markup override

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

### Rich HTML Message Rendering

#### Enable sanitized rendering

Enable sanitized HTML rendering for message bodies:

```ruby
ChatGem.configure do |config|
  config.render_message_html = true
  config.message_html_tags = %w[a b br code em i li ol p pre strong ul]
  config.message_html_attributes = %w[href target rel class]
end
```

#### Extend the allowlist

Extend the allowlist as needed:

```ruby
ChatGem.configure do |config|
  config.render_message_html = true
  config.message_html_tags = ChatGem::Configuration::DEFAULT_MESSAGE_HTML_TAGS + %w[blockquote h4 mark]
  config.message_html_attributes = ChatGem::Configuration::DEFAULT_MESSAGE_HTML_ATTRIBUTES + %w[title]
end
```

#### Simple Example

Given:

```html
<h4 title="notice">Update</h4><blockquote><mark>Done</mark></blockquote><u>underline</u>
```

Rendered/sanitized output:

```html
<h4 title="notice">Update</h4><blockquote><mark>Done</mark></blockquote>underline
```

### Browser Events

#### Typing lifecycle events

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

#### Message sent event

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

#### Mention event

```ruby
ChatGem.configure do |config|
  config.emit_mention_events = true
end
```

```js
document.addEventListener("chat-gem:mention", function (event) {
  // event.detail.chatId
  // event.detail.messageId
  // event.detail.mentions
  // event.detail.targetsCurrentParticipant
  // event.detail.targetedMentions
});
```

#### Invitation accepted event

```ruby
ChatGem.configure do |config|
  config.emit_invitation_events = true
end
```

When an invited participant accepts from the chats index (`PATCH /chat/chats/:id/accept`),
the chats index emits `chat-gem:invitation-accepted` on page load after redirect.

```js
document.addEventListener("chat-gem:invitation-accepted", function (event) {
  // event.detail.chatId
  // event.detail.chatTitle
  // event.detail.chatMembershipId
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

Invitations are pending until accepted by the invited participant.
`POST /chat/chats/:id/chat_memberships` creates or reopens a pending invite (`invitation_accepted: false`).
Pending invites are listed on the chats index for the invited participant, where they can accept (`PATCH /chat/chats/:id/accept`) or decline (`PATCH /chat/chats/:id/decline`).

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

Use signal helpers to show temporary participant states in normal chat flows (`typing`, `thinking`, `planning`).

### Start and clear a signal

```ruby
chat = ChatGem::Chat.find(chat_id)
participant = Current.user

ChatGem::Signals.start!(chat: chat, participant: participant, signal_type: :thinking)
# ...perform work (drafting, validation, lookup, etc.)...
ChatGem::Signals.clear!(chat: chat, participant: participant)
```

### Replace signal state

```ruby
ChatGem::Signals.start!(chat: chat, participant: participant, signal_type: :thinking)
ChatGem::Signals.replace!(chat: chat, participant: participant, signal_type: :planning)
```

### Auto-clear signals with a block

```ruby
final_text = ChatGem::Signals.with(chat: chat, participant: participant, signal_type: :thinking) do
  params[:body].to_s.strip
end

ChatGem::ChatMessage.create!(
  chat: chat,
  participant: participant,
  kind: :message,
  body: final_text
)
```

### Submit-time replacement on message send

When the composer submits a regular message, it stops the typing loop and requests signal clear.
For an additional server-side safeguard, enable submit-time cleanup:

```ruby
ChatGem.configure do |config|
  config.replace_signals_on_message_submit = true
end
```

With this enabled, existing signals for that participant are cleared before the message record is created.

## Dependencies

Runtime dependencies:

- Ruby `>= 3.1`
- Rails `>= 7.0`, `< 8.0`
- `turbo-rails` `>= 1.4`, `< 3.0`

Database adapter requirement:

- PostgreSQL or SQLite (required for the partial unique index used by chat memberships).

Development dependencies in this repository:

- `sqlite3` `~> 1.4`
- `minitest` `~> 5.27`

## Maintainer

[haumer](https://github.com/haumer)
