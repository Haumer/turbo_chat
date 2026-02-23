require_relative "../../test_helper"

module TurboChat
  class MessagesTest < ActiveSupport::TestCase
    test "send_message_as creates a message with source attributes" do
      participant = User.create!(email: "messages-send@example.com")
      chat = TurboChat::Chat.create!(title: "Messages Send")
      TurboChat::ChatMembership.create!(chat: chat, participant: participant, role: :member)
      sent_at = Time.zone.local(2026, 2, 23, 8, 0, 0)

      message = TurboChat::Messages.send_message_as(
        participant,
        chat,
        body: "hello from whatsapp",
        source: "whatsapp",
        external_id: "wa-msg-1",
        sent_at: sent_at
      )

      assert message.persisted?
      assert_equal "whatsapp", message.source
      assert_equal "wa-msg-1", message.external_id
      assert_equal sent_at.to_i, message.sent_at.to_i
    end

    test "send_message_as enforces posting permissions" do
      participant = User.create!(email: "messages-permission@example.com")
      chat = TurboChat::Chat.create!(title: "Messages Permission")
      membership = TurboChat::ChatMembership.create!(chat: chat, participant: participant, role: :member)
      membership.update!(muted: true)

      error = assert_raises(TurboChat::Messages::AuthorizationError) do
        TurboChat::Messages.send_message_as(participant, chat, body: "blocked", source: "whatsapp")
      end

      assert_includes error.message, "Not allowed"
      assert_equal 0, chat.chat_messages.message.count
    end

    test "ingest_external! is idempotent by chat source and external_id" do
      participant = User.create!(email: "messages-idempotent@example.com")
      chat = TurboChat::Chat.create!(title: "Messages Idempotent")
      TurboChat::ChatMembership.create!(chat: chat, participant: participant, role: :member)

      first = TurboChat::Messages.ingest_external!(
        chat: chat,
        participant: participant,
        body: "first payload",
        source: "whatsapp",
        external_id: "wa-dup-1"
      )
      second = TurboChat::Messages.ingest_external!(
        chat: chat,
        participant: participant,
        body: "second payload",
        source: "whatsapp",
        external_id: "wa-dup-1"
      )

      assert_equal first.id, second.id
      assert_equal 1, chat.chat_messages.message.where(source: "whatsapp", external_id: "wa-dup-1").count
      assert_equal "first payload", second.body
    end

    test "ingest_external! validates sent_at" do
      participant = User.create!(email: "messages-sent-at-invalid@example.com")
      chat = TurboChat::Chat.create!(title: "Messages Sent At Invalid")
      TurboChat::ChatMembership.create!(chat: chat, participant: participant, role: :member)

      error = assert_raises(TurboChat::Messages::InvalidMessageError) do
        TurboChat::Messages.ingest_external!(
          chat: chat,
          participant: participant,
          body: "hello",
          source: "whatsapp",
          external_id: "wa-2",
          sent_at: Object.new
        )
      end

      assert_includes error.message, "sent_at is invalid"
    end

    test "ingest_external! requires external_id" do
      participant = User.create!(email: "messages-missing-external-id@example.com")
      chat = TurboChat::Chat.create!(title: "Messages Missing External Id")
      TurboChat::ChatMembership.create!(chat: chat, participant: participant, role: :member)

      error = assert_raises(TurboChat::Messages::InvalidMessageError) do
        TurboChat::Messages.ingest_external!(
          chat: chat,
          participant: participant,
          body: "hello",
          source: "whatsapp",
          external_id: "   "
        )
      end

      assert_includes error.message, "external_id is required"
      assert_equal 0, chat.chat_messages.message.count
    end
  end
end
