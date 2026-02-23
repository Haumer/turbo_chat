require_relative "../../test_helper"

module TurboChat
  class ParticipantIdentityTest < ActiveSupport::TestCase
    test "display_name prefers username over name and email" do
      participant = Struct.new(:username, :name, :email).new("agent_alex", "Alex", "alex@example.com")

      assert_equal "agent_alex", TurboChat::ParticipantIdentity.display_name(participant)
    end

    test "display_name returns fallback when participant is nil" do
      assert_equal "Unknown", TurboChat::ParticipantIdentity.display_name(nil)
      assert_nil TurboChat::ParticipantIdentity.display_name(nil, unknown: nil)
    end

    test "email returns normalized participant email when present" do
      participant = Struct.new(:email).new("alex@example.com")

      assert_equal "alex@example.com", TurboChat::ParticipantIdentity.email(participant)
      assert_nil TurboChat::ParticipantIdentity.email(Struct.new(:email).new("   "))
    end

    test "mention_base_identifier prefers username then email local-part then name" do
      username_participant = Struct.new(:username, :name, :email).new("agent_alex", "Alex", "alex@example.com")
      email_participant = Struct.new(:username, :name, :email).new(nil, "Alex", "alex@example.com")
      name_participant = Struct.new(:username, :name, :email).new(nil, "Alex", nil)

      assert_equal "agent_alex", TurboChat::ParticipantIdentity.mention_base_identifier(username_participant)
      assert_equal "alex", TurboChat::ParticipantIdentity.mention_base_identifier(email_participant)
      assert_equal "Alex", TurboChat::ParticipantIdentity.mention_base_identifier(name_participant)
    end
  end
end
