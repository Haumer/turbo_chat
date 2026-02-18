require_relative "../../test_helper"

module ChatGem
  class ApplicationHelperTest < ActionView::TestCase
    MessageStub = Struct.new(:participant_membership_role)
    BodyMessageStub = Struct.new(:body, :participant_membership_role)
    MentionPermissionStub = Struct.new(:can_mention_members?, :can_mention_all?, :can_mention_roles?)

    setup do
      config = ChatGem.configuration
      @original_enable_mentions = config.enable_mentions
      @original_enable_emoji_aliases = config.enable_emoji_aliases
      @original_emoji_aliases = config.emoji_aliases.deep_dup
      @original_render_message_html = config.render_message_html
      @original_own_message_hex_color = config.own_message_hex_color
      @original_other_message_hex_color = config.other_message_hex_color
      @original_role_message_hex_colors = config.role_message_hex_colors
    end

    teardown do
      config = ChatGem.configuration
      config.enable_mentions = @original_enable_mentions
      config.enable_emoji_aliases = @original_enable_emoji_aliases
      config.emoji_aliases = @original_emoji_aliases
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

    test "plain message rendering supports custom configured emoji aliases" do
      config = ChatGem.configuration
      config.enable_mentions = true
      config.enable_emoji_aliases = true
      config.render_message_html = false
      config.add_emoji_alias(:shipit, "🚢")

      rendered = render_chat_message_body(BodyMessageStub.new("ready :shipit:", nil)).to_s

      assert_includes rendered, "🚢"
    end

    test "chat mention options include chat members, @all, and role mentions" do
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
