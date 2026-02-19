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

  test "inviting a participant emits turbo-chat:chat-invited in browser" do
    TurboChat.configuration.emit_chat_lifecycle_events = true

    admin = User.create!(email: "system-invite-admin@example.com")
    invitee = User.create!(email: "system-invite-target@example.com")
    chat = TurboChat::Chat.create!(title: "System Invite")
    TurboChat::ChatMembership.create!(chat: chat, participant: admin, role: :admin)

    visit "/chat/chats/#{chat.id}"

    find("select[name='chat_membership[participant_id]'] option[value='#{invitee.id}']").select_option
    click_button "Invite"
    assert_current_path "/chat/chats/#{chat.id}", ignore_query: true

    install_event_capture(%w[turbo-chat:chat-invited])
    rerun_lifecycle_event_bootstrap!

    event = wait_for_captured_event("turbo-chat:chat-invited")
    assert_equal "invited", event.fetch("detail").fetch("action")
    assert_equal chat.id.to_s, event.fetch("detail").fetch("chatId")
  end

  test "declining an invitation emits turbo-chat:chat-declined in browser" do
    TurboChat.configuration.emit_chat_lifecycle_events = true

    invitee = User.create!(email: "system-decline-invitee@example.com")
    admin = User.create!(email: "system-decline-admin@example.com")
    chat = TurboChat::Chat.create!(title: "System Decline")
    TurboChat::ChatMembership.create!(chat: chat, participant: admin, role: :admin)
    membership = TurboChat::ChatMembership.create!(
      chat: chat,
      participant: invitee,
      role: :member,
      invitation_accepted: false
    )

    visit "/chat/chats"
    click_button "Decline"
    assert_current_path "/chat/chats", ignore_query: true

    install_event_capture(%w[turbo-chat:chat-declined])
    rerun_lifecycle_event_bootstrap!

    event = wait_for_captured_event("turbo-chat:chat-declined")
    assert_equal "declined", event.fetch("detail").fetch("action")
    assert_equal chat.id.to_s, event.fetch("detail").fetch("chatId")
    assert_equal membership.id.to_s, event.fetch("detail").fetch("chatMembershipId").to_s
  end

  test "reopening a chat emits turbo-chat:chat-reopened in browser" do
    TurboChat.configuration.emit_chat_lifecycle_events = true

    admin = User.create!(email: "system-reopen-admin@example.com")
    chat = TurboChat::Chat.create!(title: "System Reopen", closed_at: Time.current)
    TurboChat::ChatMembership.create!(chat: chat, participant: admin, role: :admin)

    visit "/chat/chats/#{chat.id}"
    click_button "Reopen"
    assert_current_path "/chat/chats/#{chat.id}", ignore_query: true

    install_event_capture(%w[turbo-chat:chat-reopened])
    rerun_lifecycle_event_bootstrap!

    event = wait_for_captured_event("turbo-chat:chat-reopened")
    assert_equal "reopened", event.fetch("detail").fetch("action")
    assert_equal chat.id.to_s, event.fetch("detail").fetch("chatId")
  end

  test "accepting an invitation emits turbo-chat:chat-joined in browser" do
    TurboChat.configuration.emit_chat_lifecycle_events = true

    invitee = User.create!(email: "system-joined-invitee@example.com")
    chat = TurboChat::Chat.create!(title: "System Joined")
    membership = TurboChat::ChatMembership.create!(
      chat: chat,
      participant: invitee,
      role: :member,
      invitation_accepted: false
    )

    visit "/chat/chats"
    click_button "Accept"
    assert_current_path "/chat/chats", ignore_query: true

    install_event_capture(%w[turbo-chat:chat-joined])
    rerun_lifecycle_event_bootstrap!

    event = wait_for_captured_event("turbo-chat:chat-joined")
    assert_equal "joined", event.fetch("detail").fetch("action")
    assert_equal chat.id.to_s, event.fetch("detail").fetch("chatId")
    assert_equal membership.id.to_s, event.fetch("detail").fetch("chatMembershipId").to_s
  end

  test "leaving a chat emits turbo-chat:chat-left in browser" do
    TurboChat.configuration.emit_chat_lifecycle_events = true

    participant = User.create!(email: "system-leave-participant@example.com")
    chat = TurboChat::Chat.create!(title: "System Leave")
    membership = TurboChat::ChatMembership.create!(chat: chat, participant: participant, role: :member)

    visit "/chat/chats/#{chat.id}"
    accept_confirm("Leave this chat?") do
      click_button "Leave"
    end
    assert_current_path "/chat/chats", ignore_query: true

    install_event_capture(%w[turbo-chat:chat-left])
    rerun_lifecycle_event_bootstrap!

    event = wait_for_captured_event("turbo-chat:chat-left")
    assert_equal "left", event.fetch("detail").fetch("action")
    assert_equal chat.id.to_s, event.fetch("detail").fetch("chatId")
    assert_equal membership.id.to_s, event.fetch("detail").fetch("chatMembershipId").to_s
  end

  test "closing a chat emits turbo-chat:chat-closed in browser" do
    TurboChat.configuration.emit_chat_lifecycle_events = true

    admin = User.create!(email: "system-close-admin@example.com")
    chat = TurboChat::Chat.create!(title: "System Close")
    TurboChat::ChatMembership.create!(chat: chat, participant: admin, role: :admin)

    visit "/chat/chats/#{chat.id}"
    accept_confirm("Close this chat?") do
      click_button "Close"
    end
    assert_current_path "/chat/chats/#{chat.id}", ignore_query: true

    install_event_capture(%w[turbo-chat:chat-closed])
    rerun_lifecycle_event_bootstrap!

    event = wait_for_captured_event("turbo-chat:chat-closed")
    assert_equal "closed", event.fetch("detail").fetch("action")
    assert_equal chat.id.to_s, event.fetch("detail").fetch("chatId")
  end

  test "accepting an invitation emits turbo-chat:invitation-accepted in browser" do
    TurboChat.configuration.emit_invitation_events = true

    invitee = User.create!(email: "system-accept-invitee@example.com")
    chat = TurboChat::Chat.create!(title: "System Accept")
    membership = TurboChat::ChatMembership.create!(
      chat: chat,
      participant: invitee,
      role: :member,
      invitation_accepted: false
    )

    visit "/chat/chats"
    click_button "Accept"
    assert_current_path "/chat/chats", ignore_query: true

    install_event_capture(%w[turbo-chat:invitation-accepted])
    rerun_lifecycle_event_bootstrap!

    event = wait_for_captured_event("turbo-chat:invitation-accepted")
    assert_equal chat.id.to_s, event.fetch("detail").fetch("chatId")
    assert_equal membership.id.to_s, event.fetch("detail").fetch("chatMembershipId").to_s
  end

  test "typing and sending emits typing and message events in browser" do
    TurboChat.configuration.emit_typing_events = true
    TurboChat.configuration.emit_message_events = true

    user = User.create!(email: "system-message-user@example.com")
    chat = TurboChat::Chat.create!(title: "System Message Events")
    TurboChat::ChatMembership.create!(chat: chat, participant: user, role: :member)

    visit "/chat/chats/#{chat.id}"
    install_event_capture(%w[turbo-chat:typing-started turbo-chat:typing-ended turbo-chat:message-sent])

    find("textarea[name='chat_message[body]']").send_keys("hello from system test")
    wait_for_captured_event("turbo-chat:typing-started")

    click_button "Send"
    assert_text "hello from system test"
    wait_for_captured_event("turbo-chat:message-sent")
    wait_for_captured_event("turbo-chat:typing-ended")
  end

  private

  def clear_chat_records!
    TurboChat::ChatMessage.delete_all
    TurboChat::ChatMembership.delete_all
    TurboChat::Chat.delete_all
    User.delete_all
  end

  def reset_event_configuration!
    config = TurboChat.configuration
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
