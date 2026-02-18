# ChatGem

Mountable Rails engine gem for lightweight chats using Turbo Streams.

## Participant Models

```ruby
class User < ApplicationRecord
  acts_as_chat_participant
end
```

Expose the current chat participant from your host `ApplicationController`:

```ruby
class ApplicationController < ActionController::Base
  helper_method :chat_current_participant

  def chat_current_participant
    Current.user
  end
end
```

`chat_current_participant` must return a model that uses `acts_as_chat_participant` (or `nil` when unauthenticated).

## Message Metadata

```ruby
ChatGem.configure do |config|
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

### Chat Lifecycle (Active/Inactive)

A chat is considered active when it has a regular message in the configured window (default: 5 minutes).
Signal rows (`typing`, `thinking`, `planning`) do not count as activity.
When a chat is closed (`closed_at` set), members can still view it but cannot post new messages.

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

### Optional Typing Lifecycle Events (Off By Default)

Enable browser events if your host app wants hooks for local typing lifecycle:

```ruby
ChatGem.configure do |config|
  config.emit_typing_events = true
end
```

Typing indicators from your own participant are hidden by default.
Set `config.show_self_signals = true` to show your own typing/thinking/planning indicators.
Set `config.replace_signals_on_message_submit = true` to automatically clear/replace a participant's signal rows when that participant posts a regular message.
By default, regular messages are limited to `1000` characters (`config.max_message_length`).
By default, chat views load the latest `200` regular messages (`config.message_history_limit`). Set it to `nil` or `0` to disable the limit.
Mentions and emoji aliases are enabled by default (`config.enable_mentions`, `config.enable_emoji_aliases`).

Use `config.message_css_class_resolver` to apply custom classes to the entire message card (`<article class="chat-bubble ...">`).

Use message color options when you want inline bubble color control with validated hex values:

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

Mention suggestions in the composer are scoped to active chat members and include:
- member handles such as `@alex`
- `@all`
- role targets such as `@ADMIN` and `@MODERATOR`

Mention options are filtered by role permissions:
- `:mention_member` for member handles
- `:mention_all` for `@all`
- `:mention_role` for role mentions like `@ADMIN`

Role-restricted mentions are enforced server-side. Unauthorized mention tokens fail validation.

Emoji aliases support common tokens such as `:smile:`, `:thumbsup:`, `:rocket:`, and `:thinking:`.
You can extend aliases at runtime:

```ruby
ChatGem.configure do |config|
  config.add_emoji_alias(:shipit, "🚢")
  config.add_emoji_alias("party_parrot", "🦜")
end
```

Or fully replace the alias map:

```ruby
ChatGem.configure do |config|
  config.emoji_aliases = ChatGem::Configuration::DEFAULT_EMOJI_ALIASES.merge(
    "shipit" => "🚢",
    "party_parrot" => "🦜"
  )
end
```

Simple example:

```ruby
ChatGem.configure do |config|
  config.message_css_class_resolver = ->(_chat_message, own_message) {
    own_message ? "msg-card msg-card--own" : "msg-card msg-card--other"
  }
end
```

Resulting rendered HTML (example):

```html
<article id="chat_gem_chat_message_42" class="chat-bubble chat-bubble--own msg-card msg-card--own">
  <header class="chat-meta">
    <span class="chat-meta__author">you@example.com</span>
    <time datetime="2026-02-18T16:40:00Z">February 18, 2026 4:40 PM</time>
  </header>
  <p class="chat-body">Hello world</p>
</article>
```

Complex example:

```ruby
ChatGem.configure do |config|
  config.message_css_class_resolver = lambda { |chat_message, own_message|
    classes = ["msg-card"]
    classes << (own_message ? "msg-card--own" : "msg-card--other")
    classes << "msg-card--role-#{chat_message.participant_membership_role}" if chat_message.participant_membership_role.present?
    classes << "msg-card--ai" if chat_message.participant_type == "Bot"
    classes << "msg-card--long" if chat_message.body.to_s.length > 280
    classes
  }
end
```

Resulting rendered HTML (example):

```html
<article id="chat_gem_chat_message_73" class="chat-bubble msg-card msg-card--other msg-card--role-support_agent msg-card--ai msg-card--long">
  <header class="chat-meta">
    <span class="chat-meta__author">Support Bot</span>
    <time datetime="2026-02-18T16:41:00Z">February 18, 2026 4:41 PM</time>
  </header>
  <p class="chat-body">Here is a longer automated response...</p>
</article>
```

Need to change the card structure (for example, add a second `div`, actions row, or footer)?
`message_css_class_resolver` only controls classes. For full markup changes, override the message partial in your host app.

1. Create `app/views/chat_gem/chat_messages/_message.html.erb` in your host app.
2. Copy the engine partial and customize it.
3. Keep `id="<%= dom_id(chat_message) %>"` on the wrapper so Turbo updates/removals keep working.

Example override (with an extra card section):

```erb
<% own_message = respond_to?(:current_chat_participant, true) && (chat_message.participant == current_chat_participant) %>
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

Set `config.render_message_html = true` to render sanitized HTML in message bodies:

```ruby
ChatGem.configure do |config|
  config.render_message_html = true
  config.message_html_tags = %w[a b br code em i li ol p pre strong ul]
  config.message_html_attributes = %w[href target rel class]
end
```

Example: extend the allowlist with extra tags/attributes:

```ruby
ChatGem.configure do |config|
  config.render_message_html = true
  config.message_html_tags = ChatGem::Configuration::DEFAULT_MESSAGE_HTML_TAGS + %w[blockquote h4 mark]
  config.message_html_attributes = ChatGem::Configuration::DEFAULT_MESSAGE_HTML_ATTRIBUTES + %w[title]
end
```

Given this message body:

```html
<h4 title="notice">Update</h4><blockquote><mark>Done</mark></blockquote><u>underline</u>
```

Rendered/sanitized output:

```html
<h4 title="notice">Update</h4><blockquote><mark>Done</mark></blockquote>underline
```

Listen in your app JavaScript:

```js
document.addEventListener("chat-gem:typing-started", function (event) {
  // event.detail.chatId
});

document.addEventListener("chat-gem:typing-ended", function (event) {
  // event.detail.chatId
});
```

### Optional Message Sent Event (Off By Default)

Enable browser event emission when a message submit succeeds:

```ruby
ChatGem.configure do |config|
  config.emit_message_events = true
end
```

Listen in your app JavaScript:

```js
document.addEventListener("chat-gem:message-sent", function (event) {
  // event.detail.chatId
});
```

## Add Participants To A Chat

Use `ChatGem::ChatMembership` to add either humans or bots to a chat.
By default, each chat allows up to 10 active participants. Removed memberships (`removed_at` set) do not count.

```ruby
chat = ChatGem::Chat.find(chat_id)

# Human
user = User.find(user_id)
ChatGem::ChatMembership.find_or_create_by!(chat: chat, participant: user) do |membership|
  membership.role = :member
end

# Bot
bot = Bot.find(bot_id)
ChatGem::ChatMembership.find_or_create_by!(chat: chat, participant: bot) do |membership|
  membership.role = :member
end
```

Configure the limit:

```ruby
ChatGem.configure do |config|
  config.max_chat_participants = 10
  # Set to nil or 0 to disable the limit.
end
```

Available roles: `:member`, `:moderator`, `:admin`.

Role capabilities in the default permission adapter:
- `member`: can view chat, post messages, and mention members.
- `moderator`: member capabilities plus `@all`, `@ROLE`, mute/timeout/ban members, and delete member messages.
- `admin`: moderator capabilities plus moderating moderators and closing/reopening chats.

Register custom roles with a name, rank, and explicit permissions:

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

Assign a custom role to a membership:

```ruby
membership = ChatGem::ChatMembership.find_or_create_by!(chat: chat, participant: user)
membership.role_key = :support_agent
membership.save!
```

Available permissions: `:view_chat`, `:post_message`, `:mention_member`, `:mention_all`, `:mention_role`, `:mute_member`, `:timeout_member`, `:ban_member`, `:delete_message`, `:close_chat`, `:reopen_chat`.
Higher `rank` can moderate lower `rank` (and cannot moderate self).

Moderation actions only apply to active memberships in the same chat, and you cannot moderate yourself.

If a participant was removed previously (`removed_at` set), reactivate that same membership:

```ruby
membership = ChatGem::ChatMembership.find_by!(chat: chat, participant: user_or_bot)
membership.update!(removed_at: nil, muted: false, timed_out_until: nil)
```

Use the moderation service for role-checked actions:

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

## Programmatic Signals (Typing/Thinking/Planning)

Use signals to show activity while a participant (human or bot) is working on an API call.

```ruby
chat = ChatGem::Chat.find(chat_id)
bot = Bot.find(bot_id)

ChatGem::Signals.start!(chat: chat, participant: bot, signal_type: :thinking)
answer = ExternalAiClient.answer(prompt)
ChatGem::Signals.clear!(chat: chat, participant: bot)

ChatGem::ChatMessage.create!(
  chat: chat,
  participant: bot,
  kind: :message,
  body: answer
)
```

To replace a signal (for example `thinking` -> `planning`), call `start!` or `replace!` again:

```ruby
ChatGem::Signals.start!(chat: chat, participant: bot, signal_type: :thinking)
ChatGem::Signals.replace!(chat: chat, participant: bot, signal_type: :planning)
```

Use `with` to automatically clear the signal after success or failure:

```ruby
answer = ChatGem::Signals.with(chat: chat, participant: bot, signal_type: :thinking) do
  ExternalAiClient.answer(prompt)
end

ChatGem::ChatMessage.create!(
  chat: chat,
  participant: bot,
  kind: :message,
  body: answer
)
```
