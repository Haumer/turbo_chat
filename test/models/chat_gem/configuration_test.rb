require "test_helper"

module ChatGem
  class ConfigurationTest < ActiveSupport::TestCase
    test "metadata defaults are timestamp on and role off" do
      config = ChatGem.configuration

      assert_equal 10, config.max_chat_participants
      assert_equal true, config.show_timestamp
      assert_equal false, config.show_role
      assert_equal 5.minutes, config.active_chat_window
      assert_equal false, config.emit_typing_events
      assert_equal false, config.emit_message_events
      assert_respond_to config.timestamp_formatter, :call
      assert_respond_to config.role_formatter, :call
      assert_respond_to config.current_participant_resolver, :call
      assert_includes config.role_definitions.keys, "member"
      assert_includes config.role_definitions.keys, "moderator"
      assert_includes config.role_definitions.keys, "admin"
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
  end
end
