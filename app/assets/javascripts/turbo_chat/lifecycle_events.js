(function (namespace) {
  var datasetFlagEnabled = namespace.datasetFlagEnabled;
  var parseJsonObject = namespace.parseJsonObject;

  function setupInvitationEvents() {
    document.querySelectorAll("[data-chat-index]").forEach(function (element) {
      if (!element || !element.dataset || element.dataset.chatInvitationEventsBound === "true") {
        return;
      }

      element.dataset.chatInvitationEventsBound = "true";
      if (!datasetFlagEnabled(element, "chatEmitInvitationEvents")) {
        return;
      }

      var payload = parseJsonObject(element.dataset.chatInvitationAccepted);
      if (!payload) {
        return;
      }

      var event = new CustomEvent("turbo-chat:invitation-accepted", {
        bubbles: true,
        detail: {
          chatId: payload.chatId || null,
          chatTitle: payload.chatTitle || null,
          chatMembershipId: payload.chatMembershipId || null
        }
      });
      element.dispatchEvent(event);
    });
  }

  function setupChatLifecycleEvents() {
    document.querySelectorAll("[data-chat-lifecycle-event]").forEach(function (element) {
      if (!element || !element.dataset || element.dataset.chatLifecycleEventsBound === "true") {
        return;
      }

      element.dataset.chatLifecycleEventsBound = "true";
      if (!datasetFlagEnabled(element, "chatEmitChatLifecycleEvents")) {
        return;
      }

      var payload = parseJsonObject(element.dataset.chatLifecycleEvent);
      if (!payload) {
        return;
      }

      var eventName = String(payload.eventName || "").trim();
      if (!eventName) {
        return;
      }

      var event = new CustomEvent(eventName, {
        bubbles: true,
        detail: {
          action: payload.action || null,
          chatId: payload.chatId || null,
          chatTitle: payload.chatTitle || null,
          chatMembershipId: payload.chatMembershipId || null
        }
      });
      element.dispatchEvent(event);
    });
  }

  function setupTurboChatUi() {
    setupInvitationEvents();
    setupChatLifecycleEvents();

    if (typeof namespace.setupAllComposers === "function") {
      namespace.setupAllComposers();
    }
    if (typeof namespace.setupAllMessageAutoScroll === "function") {
      namespace.setupAllMessageAutoScroll();
    }
    if (typeof namespace.setupAllSignalContainers === "function") {
      namespace.setupAllSignalContainers();
    }
    if (typeof namespace.pruneSignals === "function") {
      namespace.pruneSignals();
    }
  }

  document.addEventListener("turbo:load", setupTurboChatUi);
  document.addEventListener("DOMContentLoaded", setupTurboChatUi);
  document.addEventListener("turbo:render", setupTurboChatUi);
  setInterval(function () {
    if (typeof namespace.pruneSignals === "function") {
      namespace.pruneSignals();
    }
  }, 1000);
})(window.TurboChatUI = window.TurboChatUI || {});
