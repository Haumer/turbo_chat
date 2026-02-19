require_relative "../../test_helper"

module ChatGem
  class ApplicationHelperTest < ActionView::TestCase
    MessageStub = Struct.new(:participant_membership_role)
    BodyMessageStub = Struct.new(:body, :participant_membership_role)
    OwnedMessageStub = Struct.new(:participant_type, :participant_id)
    MentionPermissionStub = Struct.new(:can_mention_members?, :can_mention_all?, :can_mention_roles?)

    setup do
      config = ChatGem.configuration
      @original_enable_mentions = config.enable_mentions
      @original_mention_filter_exclude_self = config.mention_filter_exclude_self
      @original_mention_filter_hide_roles = config.mention_filter_hide_roles
      @original_enable_emoji_aliases = config.enable_emoji_aliases
      @original_emoji_aliases = config.emoji_aliases.deep_dup
      @original_mention_mark_hex_color = config.mention_mark_hex_color
      @original_mention_highlight_hex_color = config.mention_highlight_hex_color
      @original_emit_invitation_events = config.emit_invitation_events
      @original_emit_chat_lifecycle_events = config.emit_chat_lifecycle_events
      @original_render_message_html = config.render_message_html
      @original_own_message_hex_color = config.own_message_hex_color
      @original_other_message_hex_color = config.other_message_hex_color
      @original_role_message_hex_colors = config.role_message_hex_colors
    end

    teardown do
      config = ChatGem.configuration
      config.enable_mentions = @original_enable_mentions
      config.mention_filter_exclude_self = @original_mention_filter_exclude_self
      config.mention_filter_hide_roles = @original_mention_filter_hide_roles
      config.enable_emoji_aliases = @original_enable_emoji_aliases
      config.emoji_aliases = @original_emoji_aliases
      config.mention_mark_hex_color = @original_mention_mark_hex_color
      config.mention_highlight_hex_color = @original_mention_highlight_hex_color
      config.emit_invitation_events = @original_emit_invitation_events
      config.emit_chat_lifecycle_events = @original_emit_chat_lifecycle_events
      config.render_message_html = @original_render_message_html
      config.own_message_hex_color = @original_own_message_hex_color
      config.other_message_hex_color = @original_other_message_hex_color
      config.role_message_hex_colors = @original_role_message_hex_colors
    end

    test "supports custom own and other message hex colors" do
      config = ChatGem.configuration
      config.own_message_hex_color = "#123abc"
      config.other_message_hex_color = "fedcba"
      config.role_message_hex_colors = {}

      message = MessageStub.new(nil)

      assert_equal "--chat-bubble-bg: #123abc; --chat-bubble-border: #123abc;", chat_message_inline_style(chat_message: message, own_message: true)
      assert_equal "--chat-bubble-bg: #fedcba; --chat-bubble-border: #fedcba;", chat_message_inline_style(chat_message: message, own_message: false)
    end

    test "role-specific colors override own and other defaults" do
      config = ChatGem.configuration
      config.own_message_hex_color = "#111111"
      config.other_message_hex_color = "#222222"
      config.role_message_hex_colors = {
        "admin" => "#ab12cd",
        "moderator" => { own: "#334455", other: "#667788" }
      }

      admin_message = MessageStub.new("admin")
      moderator_message = MessageStub.new("moderator")

      assert_equal "--chat-bubble-bg: #ab12cd; --chat-bubble-border: #ab12cd;", chat_message_inline_style(chat_message: admin_message, own_message: false)
      assert_equal "--chat-bubble-bg: #334455; --chat-bubble-border: #334455;", chat_message_inline_style(chat_message: moderator_message, own_message: true)
      assert_equal "--chat-bubble-bg: #667788; --chat-bubble-border: #667788;", chat_message_inline_style(chat_message: moderator_message, own_message: false)
    end

    test "invalid role color falls back to own or other default color" do
      config = ChatGem.configuration
      config.own_message_hex_color = "#00aa00"
      config.other_message_hex_color = "#aa0000"
      config.role_message_hex_colors = {
        "admin" => { own: "invalid", other: "#12x456" }
      }

      admin_message = MessageStub.new("admin")

      assert_equal "--chat-bubble-bg: #00aa00; --chat-bubble-border: #00aa00;", chat_message_inline_style(chat_message: admin_message, own_message: true)
      assert_equal "--chat-bubble-bg: #aa0000; --chat-bubble-border: #aa0000;", chat_message_inline_style(chat_message: admin_message, own_message: false)
    end

    test "plain message rendering supports mentions and emoji aliases" do
      config = ChatGem.configuration
      config.enable_mentions = true
      config.enable_emoji_aliases = true
      config.render_message_html = false

      rendered = render_chat_message_body(BodyMessageStub.new("hello @alex :smile:", nil)).to_s

      assert_includes rendered, %(<span class="chat-mention">@alex</span>)
      assert_includes rendered, "😄"
    end

    test "mention container style uses configured mention mark color" do
      config = ChatGem.configuration
      config.mention_mark_hex_color = "cf1322"

      assert_equal "--chat-mention-highlight-color: #cf1322; --chat-mention-mark-background: #cf132238;", chat_mentions_container_inline_style
    end

    test "mention container style falls back to mention highlight color for compatibility" do
      config = ChatGem.configuration
      config.mention_mark_hex_color = nil
      config.mention_highlight_hex_color = "cf1322"

      assert_equal "--chat-mention-highlight-color: #cf1322; --chat-mention-mark-background: #cf132238;", chat_mentions_container_inline_style
    end

    test "mention helper configuration fallbacks support legacy configuration objects" do
      legacy_config = Struct.new(:enable_mentions).new(true)

      ChatGem.stub(:configuration, legacy_config) do
        assert_nil chat_mentions_container_inline_style
        assert_equal true, chat_mention_filter_exclude_self?
        assert_equal true, chat_mention_filter_hide_roles?
        assert_equal false, chat_emit_mention_events?
        assert_equal false, chat_emit_invitation_events?
        assert_equal false, chat_emit_chat_lifecycle_events?
      end
    end

    test "chat_emit_invitation_events? follows configuration" do
      ChatGem.configuration.emit_invitation_events = true

      assert_equal true, chat_emit_invitation_events?
    end

    test "chat_emit_chat_lifecycle_events? follows configuration" do
      ChatGem.configuration.emit_chat_lifecycle_events = true

      assert_equal true, chat_emit_chat_lifecycle_events?
    end

    test "chat_message_mention_tokens extracts unique mention tokens" do
      config = ChatGem.configuration
      config.enable_mentions = true

      message = BodyMessageStub.new("hey @alex @all @alex", nil)
      assert_equal ["@alex", "@all"], chat_message_mention_tokens(message)
    end

    test "own_chat_message? matches participant type and id" do
      participant = User.create!(email: "owner-check@example.com")
      own_message = OwnedMessageStub.new("User", participant.id)
      other_message = OwnedMessageStub.new("User", participant.id + 1)
      other_type_message = OwnedMessageStub.new("Admin", participant.id)

      assert own_chat_message?(own_message, participant: participant)
      assert_not own_chat_message?(other_message, participant: participant)
      assert_not own_chat_message?(other_type_message, participant: participant)
    end

    test "chat_participant_name prefers username when present" do
      participant = Struct.new(:username, :name, :email).new("agent_alex", "Alex", "alex@example.com")

      assert_equal "agent_alex", chat_participant_name(participant)
    end

    test "plain message rendering supports custom configured emoji aliases" do
      config = ChatGem.configuration
      config.enable_mentions = true
      config.enable_emoji_aliases = true
      config.render_message_html = false
      config.add_emoji_alias(:shipit, "🚢")

      rendered = render_chat_message_body(BodyMessageStub.new("ready :shipit:", nil)).to_s

      assert_includes rendered, "🚢"
    end

    test "can_edit_chat_message? delegates to configured permission adapter" do
      chat = ChatGem::Chat.create!(title: "Helper Edit Permission")
      owner = User.create!(email: "helper-edit-owner@example.com")
      other = User.create!(email: "helper-edit-other@example.com")
      ChatGem::ChatMembership.create!(chat: chat, participant: owner, role: :member)
      ChatGem::ChatMembership.create!(chat: chat, participant: other, role: :member)

      message = ChatGem::ChatMessage.new(chat: chat, participant: owner, kind: :message, body: "hello")

      assert can_edit_chat_message?(message, participant: owner)
      assert_not can_edit_chat_message?(message, participant: other)
    end

    test "can_edit_chat_message? returns true when rendered without participant context" do
      chat = ChatGem::Chat.new(id: 10)
      message = ChatGem::ChatMessage.new(id: 20, chat: chat, participant_type: "User", participant_id: 3, kind: :message, body: "hi")

      assert can_edit_chat_message?(message)
    end

    test "chat mention options include chat members, @all, and role mentions" do
      config = ChatGem.configuration
      config.mention_filter_hide_roles = false

      chat = ChatGem::Chat.create!(title: "Mention Targets")
      first_user = User.create!(email: "alex@example.com")
      second_user = User.create!(email: "alex@other.test")
      ChatGem::ChatMembership.create!(chat: chat, participant: first_user, role: :admin)
      ChatGem::ChatMembership.create!(chat: chat, participant: second_user, role: :member)

      permission = MentionPermissionStub.new(true, true, true)
      tokens = chat_mention_options(chat: chat, permission: permission).map { |entry| entry[:token] }

      assert_includes tokens, "@all"
      assert_includes tokens, "@alex"
      assert_includes tokens, "@alex_2"
      assert_includes tokens, "@ADMIN"
      assert_includes tokens, "@MEMBER"
    end

    test "chat mention options hide role mentions by default" do
      config = ChatGem.configuration
      config.mention_filter_hide_roles = true

      chat = ChatGem::Chat.create!(title: "Role Mention Hidden")
      user = User.create!(email: "role-hidden@example.com")
      ChatGem::ChatMembership.create!(chat: chat, participant: user, role: :moderator)

      permission = MentionPermissionStub.new(true, true, true)
      tokens = chat_mention_options(chat: chat, permission: permission).map { |entry| entry[:token] }

      assert_not_includes tokens, "@MODERATOR"
    end

    test "chat mention options exclude current participant by default" do
      config = ChatGem.configuration
      config.mention_filter_exclude_self = true

      chat = ChatGem::Chat.create!(title: "Self Mention Filter")
      current_user = User.create!(email: "current-self-filter@example.com")
      other_user = User.create!(email: "other-self-filter@example.com")
      ChatGem::ChatMembership.create!(chat: chat, participant: current_user, role: :member)
      ChatGem::ChatMembership.create!(chat: chat, participant: other_user, role: :member)

      define_singleton_method(:current_chat_participant) { current_user }
      permission = MentionPermissionStub.new(true, false, false)
      options = chat_mention_options(chat: chat, permission: permission)
      tokens = options.map { |entry| entry[:token] }
      labels = options.map { |entry| entry[:label] }

      assert_not_includes labels, current_user.email
      assert_includes labels, other_user.email
      assert_not_includes tokens, "@current_self_filter"
    end

    test "chat mention options are filtered by mention permissions" do
      chat = ChatGem::Chat.create!(title: "Restricted Mention Targets")
      first_user = User.create!(email: "jane@example.com")
      ChatGem::ChatMembership.create!(chat: chat, participant: first_user, role: :moderator)

      member_only = MentionPermissionStub.new(true, false, false)
      tokens = chat_mention_options(chat: chat, permission: member_only).map { |entry| entry[:token] }

      assert_includes tokens, "@jane"
      assert_not_includes tokens, "@all"
      assert_not_includes tokens, "@MODERATOR"
      assert chat_mentions_enabled_for?(chat: chat, permission: member_only)
    end
  end
end
