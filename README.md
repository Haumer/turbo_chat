# ChatGem

Mountable Rails engine gem for lightweight chats using Turbo Streams.

## Participant Models

```ruby
class User < ApplicationRecord
  acts_as_chat_participant
end
```

If your host controller sometimes returns a username (string) instead of a model object, configure a resolver:

```ruby
ChatGem.configure do |config|
  config.current_participant_method = :chat_current_participant
  config.current_participant_resolver = lambda { |value, _controller|
    case value
    when User
      value
    when String
      User.find_by(email: value) || User.find_by(username: value)
    end
  }
end
```

## Message Metadata

```ruby
ChatGem.configure do |config|
  config.max_chat_participants = 10
  config.show_timestamp = true
  config.show_role = false
  config.active_chat_window = 5.minutes
  config.emit_typing_events = false
  config.emit_message_events = false
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
- `member`: can view chat and post messages (unless muted/timed out or chat is closed).
- `moderator`: member capabilities plus mute/timeout/ban members and delete member messages.
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

Available permissions: `:view_chat`, `:post_message`, `:mute_member`, `:timeout_member`, `:ban_member`, `:delete_message`, `:close_chat`, `:reopen_chat`.
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
