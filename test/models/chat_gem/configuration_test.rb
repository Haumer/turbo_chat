require_relative "../../test_helper"

module ChatGem
  class ConfigurationTest < ActiveSupport::TestCase
    test "metadata defaults are timestamp on and role off" do
      config = ChatGem.configuration

      assert_equal 10, config.max_chat_participants
      assert_equal 1000, config.max_message_length
      assert_equal 200, config.message_history_limit
      assert_equal true, config.enable_mentions
      assert_equal true, config.enable_emoji_aliases
      assert_equal ChatGem::Configuration::DEFAULT_EMOJI_ALIASES, config.effective_emoji_aliases
      assert_nil config.own_message_hex_color
      assert_nil config.other_message_hex_color
      assert_equal({}, config.role_message_hex_colors)
      assert_equal true, config.show_timestamp
      assert_equal false, config.show_role
      assert_equal 5.minutes, config.active_chat_window
      assert_equal false, config.emit_typing_events
      assert_equal false, config.emit_message_events
      assert_equal false, config.show_self_signals
      assert_equal false, config.replace_signals_on_message_submit
      assert_nil config.message_css_class_resolver
      assert_equal false, config.render_message_html
      assert_equal %w[a b br code em i li ol p pre strong ul], config.message_html_tags
      assert_equal %w[href target rel class], config.message_html_attributes
      assert_respond_to config.timestamp_formatter, :call
      assert_respond_to config.role_formatter, :call
      assert_includes config.role_definitions.keys, "member"
      assert_includes config.role_definitions.keys, "moderator"
      assert_includes config.role_definitions.keys, "admin"
      assert_includes config.role_definition(:member)[:permissions], :mention_member
      assert_includes config.role_definition(:moderator)[:permissions], :mention_all
      assert_includes config.role_definition(:moderator)[:permissions], :invite_member
      assert_includes config.role_definition(:admin)[:permissions], :mention_role
      assert_includes config.role_definition(:admin)[:permissions], :invite_member
    end

    test "can register custom role with name permissions and rank" do
      config = ChatGem.configuration
      config.clear_additional_roles!

      config.add_role(
        :support_agent,
        name: "Support Agent",
        rank: 1,
        permissions: %i[view_chat post_message delete_message]
      )

      definition = config.role_definition(:support_agent)
      assert_equal "Support Agent", definition[:name]
      assert_equal 1, definition[:rank]
      assert_equal %i[view_chat post_message delete_message], definition[:permissions]
    ensure
      config.clear_additional_roles!
    end

    test "cannot override reserved built-in roles" do
      config = ChatGem.configuration

      error = assert_raises(ArgumentError) do
        config.add_role(:member, name: "Custom Member", rank: 9, permissions: %i[view_chat])
      end

      assert_includes error.message, "reserved"
    end

    test "can extend and reset emoji aliases" do
      config = ChatGem.configuration
      original_aliases = config.emoji_aliases

      config.add_emoji_alias(:shipit, "🚢")
      config.add_emoji_alias("party_parrot", "🦜")

      aliases = config.effective_emoji_aliases
      assert_equal "🚢", aliases["shipit"]
      assert_equal "🦜", aliases["party_parrot"]

      config.remove_emoji_alias("shipit")
      assert_not_includes config.effective_emoji_aliases.keys, "shipit"

      config.clear_emoji_aliases!
      assert_equal({}, config.effective_emoji_aliases)

      config.reset_emoji_aliases!
      assert_equal ChatGem::Configuration::DEFAULT_EMOJI_ALIASES, config.effective_emoji_aliases
    ensure
      config.emoji_aliases = original_aliases
    end
  end
end
