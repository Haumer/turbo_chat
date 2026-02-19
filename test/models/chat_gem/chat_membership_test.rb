require_relative "../../test_helper"

module ChatGem
  class ChatMembershipTest < ActiveSupport::TestCase
    test "role enum values" do
      user = User.create!(email: "roles@example.com")
      chat = ChatGem::Chat.create!(title: "Roles")

      membership = ChatGem::ChatMembership.create!(chat: chat, participant: user, role: :moderator)

      assert membership.moderator?
      assert membership.active?
    end

    test "pending invitation is inactive until accepted" do
      user = User.create!(email: "pending-membership@example.com")
      chat = ChatGem::Chat.create!(title: "Pending Membership")

      membership = ChatGem::ChatMembership.create!(
        chat: chat,
        participant: user,
        invitation_accepted: false
      )

      assert membership.pending?
      assert_not membership.active?

      membership.accept_invitation!
      assert membership.reload.active?
    end

    test "falls back to removed_at-only checks when invitation tracking column is unavailable" do
      user = User.create!(email: "legacy-membership@example.com")
      chat = ChatGem::Chat.create!(title: "Legacy Membership")
      membership = ChatGem::ChatMembership.create!(chat: chat, participant: user)

      ChatGem::ChatMembership.stub(:invitation_tracking_supported?, false) do
        assert membership.active?
        assert_not membership.pending?
        assert_equal [membership.id], ChatGem::ChatMembership.active.where(id: membership.id).pluck(:id)
        assert_empty ChatGem::ChatMembership.pending.where(id: membership.id)
      end
    end

    test "enforces max active participants per chat" do
      with_max_chat_participants(2) do
        chat = ChatGem::Chat.create!(title: "Participant Limit")
        user_one = User.create!(email: "limit-one@example.com")
        user_two = User.create!(email: "limit-two@example.com")
        user_three = User.create!(email: "limit-three@example.com")

        ChatGem::ChatMembership.create!(chat: chat, participant: user_one)
        ChatGem::ChatMembership.create!(chat: chat, participant: user_two)

        overflow = ChatGem::ChatMembership.new(chat: chat, participant: user_three)
        assert_not overflow.valid?
        assert_includes overflow.errors[:chat], "has reached the participant limit (2)"
      end
    end

    test "removed memberships do not count but reactivating still checks the limit" do
      with_max_chat_participants(1) do
        chat = ChatGem::Chat.create!(title: "Reactivation Limit")
        first_user = User.create!(email: "reactivate-one@example.com")
        second_user = User.create!(email: "reactivate-two@example.com")

        first_membership = ChatGem::ChatMembership.create!(chat: chat, participant: first_user)
        second_membership = ChatGem::ChatMembership.create!(
          chat: chat,
          participant: second_user,
          removed_at: 1.minute.ago
        )

        assert_not second_membership.update(removed_at: nil)
        assert_includes second_membership.errors[:chat], "has reached the participant limit (1)"

        first_membership.update!(removed_at: Time.current)
        assert second_membership.update(removed_at: nil)
      end
    end

    test "supports configured custom roles with name and permissions" do
      with_custom_role(
        :support_agent,
        name: "Support Agent",
        rank: 1,
        permissions: %i[view_chat post_message delete_message]
      ) do
        user = User.create!(email: "support-role@example.com")
        chat = ChatGem::Chat.create!(title: "Custom Role")

        membership = ChatGem::ChatMembership.create!(chat: chat, participant: user, role_key: :support_agent)

        assert_equal "support_agent", membership.effective_role_key
        assert_equal "Support Agent", membership.effective_role_name
        assert_equal 1, membership.effective_role_rank
        assert_equal %i[view_chat post_message delete_message], membership.effective_role_permissions
      end
    end

    test "invalid custom role key is rejected" do
      user = User.create!(email: "bad-role@example.com")
      chat = ChatGem::Chat.create!(title: "Invalid Role")

      membership = ChatGem::ChatMembership.new(chat: chat, participant: user, role_key: :unknown_role)

      assert_not membership.valid?
      assert_includes membership.errors[:custom_role_key], "is not configured"
    end

    private

    def with_max_chat_participants(limit)
      previous_limit = ChatGem.configuration.max_chat_participants
      ChatGem.configuration.max_chat_participants = limit
      yield
    ensure
      ChatGem.configuration.max_chat_participants = previous_limit
    end

    def with_custom_role(key, name:, rank:, permissions:)
      config = ChatGem.configuration
      config.add_role(key, name: name, rank: rank, permissions: permissions)
      yield
    ensure
      config.remove_role(key)
    end
  end
end
