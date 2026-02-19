require_relative "../application_system_test_case"

class ChatBrowserEventsTest < ApplicationSystemTestCase
  setup do
    reset_event_configuration!
    clear_chat_records!
  end

  teardown do
    reset_event_configuration!
    clear_chat_records!
  end

  test "inviting a participant emits chat-gem:chat-invited in browser" do
    ChatGem.configuration.emit_chat_lifecycle_events = true

    admin = User.create!(email: "system-invite-admin@example.com")
    invitee = User.create!(email: "system-invite-target@example.com")
    chat = ChatGem::Chat.create!(title: "System Invite")
    ChatGem::ChatMembership.create!(chat: chat, participant: admin, role: :admin)

    visit "/chat/chats/#{chat.id}"

    find("select[name='chat_membership[participant_id]'] option[value='#{invitee.id}']").select_option
    click_button "Invite"
    assert_current_path "/chat/chats/#{chat.id}", ignore_query: true

    install_event_capture(%w[chat-gem:chat-invited])
    rerun_lifecycle_event_bootstrap!

    event = wait_for_captured_event("chat-gem:chat-invited")
    assert_equal "invited", event.fetch("detail").fetch("action")
    assert_equal chat.id.to_s, event.fetch("detail").fetch("chatId")
  end

  test "declining an invitation emits chat-gem:chat-declined in browser" do
    ChatGem.configuration.emit_chat_lifecycle_events = true

    invitee = User.create!(email: "system-decline-invitee@example.com")
    admin = User.create!(email: "system-decline-admin@example.com")
    chat = ChatGem::Chat.create!(title: "System Decline")
    ChatGem::ChatMembership.create!(chat: chat, participant: admin, role: :admin)
    membership = ChatGem::ChatMembership.create!(
      chat: chat,
      participant: invitee,
      role: :member,
      invitation_accepted: false
    )

    visit "/chat/chats"
    click_button "Decline"
    assert_current_path "/chat/chats", ignore_query: true

    install_event_capture(%w[chat-gem:chat-declined])
    rerun_lifecycle_event_bootstrap!

    event = wait_for_captured_event("chat-gem:chat-declined")
    assert_equal "declined", event.fetch("detail").fetch("action")
    assert_equal chat.id.to_s, event.fetch("detail").fetch("chatId")
    assert_equal membership.id.to_s, event.fetch("detail").fetch("chatMembershipId").to_s
  end

  test "reopening a chat emits chat-gem:chat-reopened in browser" do
    ChatGem.configuration.emit_chat_lifecycle_events = true

    admin = User.create!(email: "system-reopen-admin@example.com")
    chat = ChatGem::Chat.create!(title: "System Reopen", closed_at: Time.current)
    ChatGem::ChatMembership.create!(chat: chat, participant: admin, role: :admin)

    visit "/chat/chats/#{chat.id}"
    click_button "Reopen"
    assert_current_path "/chat/chats/#{chat.id}", ignore_query: true

    install_event_capture(%w[chat-gem:chat-reopened])
    rerun_lifecycle_event_bootstrap!

    event = wait_for_captured_event("chat-gem:chat-reopened")
    assert_equal "reopened", event.fetch("detail").fetch("action")
    assert_equal chat.id.to_s, event.fetch("detail").fetch("chatId")
  end

  test "accepting an invitation emits chat-gem:chat-joined in browser" do
    ChatGem.configuration.emit_chat_lifecycle_events = true

    invitee = User.create!(email: "system-joined-invitee@example.com")
    chat = ChatGem::Chat.create!(title: "System Joined")
    membership = ChatGem::ChatMembership.create!(
      chat: chat,
      participant: invitee,
      role: :member,
      invitation_accepted: false
    )

    visit "/chat/chats"
    click_button "Accept"
    assert_current_path "/chat/chats", ignore_query: true

    install_event_capture(%w[chat-gem:chat-joined])
    rerun_lifecycle_event_bootstrap!

    event = wait_for_captured_event("chat-gem:chat-joined")
    assert_equal "joined", event.fetch("detail").fetch("action")
    assert_equal chat.id.to_s, event.fetch("detail").fetch("chatId")
    assert_equal membership.id.to_s, event.fetch("detail").fetch("chatMembershipId").to_s
  end

  test "leaving a chat emits chat-gem:chat-left in browser" do
    ChatGem.configuration.emit_chat_lifecycle_events = true

    participant = User.create!(email: "system-leave-participant@example.com")
    chat = ChatGem::Chat.create!(title: "System Leave")
    membership = ChatGem::ChatMembership.create!(chat: chat, participant: participant, role: :member)

    visit "/chat/chats/#{chat.id}"
    click_button "Leave"
    assert_current_path "/chat/chats", ignore_query: true

    install_event_capture(%w[chat-gem:chat-left])
    rerun_lifecycle_event_bootstrap!

    event = wait_for_captured_event("chat-gem:chat-left")
    assert_equal "left", event.fetch("detail").fetch("action")
    assert_equal chat.id.to_s, event.fetch("detail").fetch("chatId")
    assert_equal membership.id.to_s, event.fetch("detail").fetch("chatMembershipId").to_s
  end

  test "closing a chat emits chat-gem:chat-closed in browser" do
    ChatGem.configuration.emit_chat_lifecycle_events = true

    admin = User.create!(email: "system-close-admin@example.com")
    chat = ChatGem::Chat.create!(title: "System Close")
    ChatGem::ChatMembership.create!(chat: chat, participant: admin, role: :admin)

    visit "/chat/chats/#{chat.id}"
    click_button "Close"
    assert_current_path "/chat/chats/#{chat.id}", ignore_query: true

    install_event_capture(%w[chat-gem:chat-closed])
    rerun_lifecycle_event_bootstrap!

    event = wait_for_captured_event("chat-gem:chat-closed")
    assert_equal "closed", event.fetch("detail").fetch("action")
    assert_equal chat.id.to_s, event.fetch("detail").fetch("chatId")
  end

  test "accepting an invitation emits chat-gem:invitation-accepted in browser" do
    ChatGem.configuration.emit_invitation_events = true

    invitee = User.create!(email: "system-accept-invitee@example.com")
    chat = ChatGem::Chat.create!(title: "System Accept")
    membership = ChatGem::ChatMembership.create!(
      chat: chat,
      participant: invitee,
      role: :member,
      invitation_accepted: false
    )

    visit "/chat/chats"
    click_button "Accept"
    assert_current_path "/chat/chats", ignore_query: true

    install_event_capture(%w[chat-gem:invitation-accepted])
    rerun_lifecycle_event_bootstrap!

    event = wait_for_captured_event("chat-gem:invitation-accepted")
    assert_equal chat.id.to_s, event.fetch("detail").fetch("chatId")
    assert_equal membership.id.to_s, event.fetch("detail").fetch("chatMembershipId").to_s
  end

  test "typing and sending emits typing and message events in browser" do
    ChatGem.configuration.emit_typing_events = true
    ChatGem.configuration.emit_message_events = true

    user = User.create!(email: "system-message-user@example.com")
    chat = ChatGem::Chat.create!(title: "System Message Events")
    ChatGem::ChatMembership.create!(chat: chat, participant: user, role: :member)

    visit "/chat/chats/#{chat.id}"
    install_event_capture(%w[chat-gem:typing-started chat-gem:typing-ended chat-gem:message-sent])

    find("textarea[name='chat_message[body]']").send_keys("hello from system test")
    wait_for_captured_event("chat-gem:typing-started")

    click_button "Send"
    assert_text "hello from system test"
    wait_for_captured_event("chat-gem:message-sent")
    wait_for_captured_event("chat-gem:typing-ended")
  end

  private

  def clear_chat_records!
    ChatGem::ChatMessage.delete_all
    ChatGem::ChatMembership.delete_all
    ChatGem::Chat.delete_all
    User.delete_all
  end

  def reset_event_configuration!
    config = ChatGem.configuration
    config.emit_typing_events = false
    config.emit_message_events = false
    config.emit_invitation_events = false
    config.emit_chat_lifecycle_events = false
  end

  def install_event_capture(event_names)
    execute_script(<<~JS, event_names)
      var names = arguments[0] || [];
      window.__chatCapturedEvents = [];

      names.forEach(function (eventName) {
        document.addEventListener(eventName, function (event) {
          var detail = null;
          try {
            detail = JSON.parse(JSON.stringify(event.detail || null));
          } catch (_error) {
            detail = null;
          }

          window.__chatCapturedEvents.push({ name: eventName, detail: detail });
        });
      });
    JS
  end

  def rerun_lifecycle_event_bootstrap!
    execute_script(<<~JS)
      document.querySelectorAll("[data-chat-index]").forEach(function (element) {
        delete element.dataset.chatInvitationEventsBound;
      });

      document.querySelectorAll("[data-chat-lifecycle-event]").forEach(function (element) {
        delete element.dataset.chatLifecycleEventsBound;
      });

      document.dispatchEvent(new Event("turbo:load"));
    JS
  end

  def wait_for_captured_event(event_name, timeout: 5)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

    loop do
      events = evaluate_script("window.__chatCapturedEvents || []")
      matched_event = events.find { |event| event["name"] == event_name }
      return matched_event if matched_event

      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      raise "Timed out waiting for #{event_name}. Captured: #{events.inspect}" if now >= deadline

      sleep 0.05
    end
  end
end
