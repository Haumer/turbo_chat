require "test_helper"

class ChatFlowTest < ActionDispatch::IntegrationTest
  class LegacyConfiguration
    def initialize(configuration, hidden_methods: %i[current_participant_resolver])
      @configuration = configuration
      @hidden_methods = hidden_methods.map(&:to_sym)
    end

    def method_missing(method_name, *args, &block)
      return super if hidden_method?(method_name)

      @configuration.public_send(method_name, *args, &block)
    end

    def respond_to_missing?(method_name, include_private = false)
      return false if hidden_method?(method_name)

      @configuration.respond_to?(method_name, include_private)
    end

    private

    def hidden_method?(method_name)
      @hidden_methods.include?(method_name.to_sym)
    end
  end

  test "renders chats index and shows a chat" do
    user = User.create!(email: "integration@example.com")
    chat = ChatGem::Chat.create!(title: "Integration Chat")
    ChatGem::ChatMembership.create!(chat: chat, participant: user)
    ChatGem::ChatMessage.create!(chat: chat, participant: user, body: "hello", kind: :message)

    get "/chat/chats"
    assert_response :success
    assert_includes response.body, "Integration Chat"

    get "/chat/chats/#{chat.id}"
    assert_response :success
    assert_includes response.body, "hello"
  end

  test "chat show includes turbo and actioncable wiring for live updates" do
    user = User.create!(email: "wiring@example.com")
    chat = ChatGem::Chat.create!(title: "Wiring Chat")
    ChatGem::ChatMembership.create!(chat: chat, participant: user)

    get "/chat/chats/#{chat.id}"
    assert_response :success

    assert_includes response.body, "action-cable-url"
    assert_match(/turbo/i, response.body)
    assert_includes response.body, "turbo-cable-stream-source"
  end

  test "resolves current participant via a private host controller method" do
    previous_method_name = ChatGem.configuration.current_participant_method
    previous_resolver = ChatGem.configuration.current_participant_resolver

    ApplicationController.class_eval do
      private

      def private_chat_current_participant
        chat_current_participant
      end
    end

    ChatGem.configure do |config|
      config.current_participant_method = :private_chat_current_participant
    end

    get "/chat/chats"
    assert_response :success
  ensure
    ChatGem.configure do |config|
      config.current_participant_method = previous_method_name
      config.current_participant_resolver = previous_resolver
    end
  end

  test "resolves current participant from username via configured resolver" do
    user = User.create!(email: "username-resolver@example.com")
    previous_method_name = ChatGem.configuration.current_participant_method
    previous_resolver = ChatGem.configuration.current_participant_resolver

    ApplicationController.class_eval do
      private

      def chat_current_participant_username
        "username-resolver@example.com"
      end
    end

    ChatGem.configure do |config|
      config.current_participant_method = :chat_current_participant_username
      config.current_participant_resolver = lambda { |value|
        case value
        when User
          value
        when String
          User.find_by(email: value)
        end
      }
    end

    chat = ChatGem::Chat.create!(title: "Username Resolver Chat")
    ChatGem::ChatMembership.create!(chat: chat, participant: user)

    get "/chat/chats"
    assert_response :success
    assert_includes response.body, "Username Resolver Chat"
  ensure
    ChatGem.configure do |config|
      config.current_participant_method = previous_method_name
      config.current_participant_resolver = previous_resolver
    end
  end

  test "falls back when configuration does not expose current_participant_resolver" do
    user = User.create!(email: "legacy-config@example.com")
    chat = ChatGem::Chat.create!(title: "Legacy Config Chat")
    ChatGem::ChatMembership.create!(chat: chat, participant: user)

    previous_configuration = ChatGem.configuration
    ChatGem.instance_variable_set(:@configuration, LegacyConfiguration.new(previous_configuration))

    get "/chat/chats/#{chat.id}"
    assert_response :success
    assert_includes response.body, "Legacy Config Chat"
  ensure
    ChatGem.instance_variable_set(:@configuration, previous_configuration)
  end

  test "chat show works when legacy configuration misses presentation flags" do
    user = User.create!(email: "legacy-flags@example.com")
    chat = ChatGem::Chat.create!(title: "Legacy Flags Chat")
    ChatGem::ChatMembership.create!(chat: chat, participant: user)
    ChatGem::ChatMessage.create!(chat: chat, participant: user, body: "legacy message", kind: :message)

    previous_configuration = ChatGem.configuration
    hidden_methods = %i[
      current_participant_resolver
      emit_typing_events
      emit_message_events
      show_timestamp
      show_role
      timestamp_formatter
      role_formatter
      active_chat_window
      permission_adapter
      role_definition
      role_definitions
      max_chat_participants
    ]

    ChatGem.instance_variable_set(
      :@configuration,
      LegacyConfiguration.new(previous_configuration, hidden_methods: hidden_methods)
    )

    get "/chat/chats/#{chat.id}"
    assert_response :success
    assert_includes response.body, "Legacy Flags Chat"
    assert_includes response.body, "legacy message"
  ensure
    ChatGem.instance_variable_set(:@configuration, previous_configuration)
  end
end
