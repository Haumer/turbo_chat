(function () {
  var SIGNAL_TTL_SECONDS = 12;
  var SIGNAL_START_DELAY_MS = 750;
  var SIGNAL_IDLE_GRACE_MS = 2500;
  var SIGNAL_HEARTBEAT_MS = 4000;
  var SIGNAL_RETREAT_MS = 180;

  function csrfToken() {
    var tag = document.querySelector("meta[name='csrf-token']");
    return tag ? tag.content : "";
  }

  function renderTurboStreamResponse(response) {
    if (!response) {
      return Promise.resolve();
    }

    return response.text().then(function (body) {
      if (!body) {
        return;
      }

      if (typeof Turbo !== "undefined" && body.indexOf("<turbo-stream") !== -1) {
        Turbo.renderStreamMessage(body);
      }
    });
  }

  function datasetFlagEnabled(node, key) {
    if (!node || !node.dataset) {
      return false;
    }

    return node.dataset[key] === "true";
  }

  function scrollLastMessageIntoView(container) {
    if (!container) {
      return;
    }

    var lastMessage = container.lastElementChild;
    if (!lastMessage) {
      return;
    }

    // Keep the last message fully visible with a tiny breathing space.
    var lastBottom = lastMessage.offsetTop + lastMessage.offsetHeight;
    var targetScrollTop = Math.max(0, lastBottom - container.clientHeight + 2);
    container.scrollTop = targetScrollTop;
  }

  function setupMessageAutoScroll(container) {
    if (!container || container.dataset.chatAutoscrollBound === "true") {
      return;
    }

    container.dataset.chatAutoscrollBound = "true";
    requestAnimationFrame(function () {
      scrollLastMessageIntoView(container);
    });

    var observer = new MutationObserver(function () {
      requestAnimationFrame(function () {
        scrollLastMessageIntoView(container);
      });
    });

    observer.observe(container, { childList: true });
  }

  function setupAllMessageAutoScroll() {
    document.querySelectorAll(".chat-messages").forEach(setupMessageAutoScroll);
  }

  function hideOwnSignals(container) {
    if (!container) {
      return;
    }

    if (datasetFlagEnabled(container, "chatShowSelfSignals")) {
      return;
    }

    var selfType = container.dataset.chatSelfParticipantType;
    var selfId = container.dataset.chatSelfParticipantId;
    if (!selfType || !selfId) {
      return;
    }

    container.querySelectorAll(".chat-typing-indicator").forEach(function (node) {
      if (
        node.dataset.chatSignalParticipantType === selfType &&
        node.dataset.chatSignalParticipantId === selfId
      ) {
        node.remove();
      }
    });
  }

  function syncSignalContainerState(container) {
    if (!container) {
      return;
    }

    hideOwnSignals(container);

    var hasVisibleSignals = container.querySelector(
      ".chat-typing-indicator:not(.chat-typing-indicator--leaving)"
    );
    container.classList.toggle("chat-signals--active", Boolean(hasVisibleSignals));
  }

  function setupSignalContainer(container) {
    if (!container) {
      return;
    }

    if (container.dataset.chatSignalsBound === "true") {
      syncSignalContainerState(container);
      return;
    }

    container.dataset.chatSignalsBound = "true";
    syncSignalContainerState(container);

    var observer = new MutationObserver(function () {
      syncSignalContainerState(container);
    });

    observer.observe(container, { childList: true });
  }

  function setupAllSignalContainers() {
    document.querySelectorAll(".chat-signals").forEach(setupSignalContainer);
  }

  function collapseSignalNode(node) {
    if (!node || node.dataset.chatSignalLeaving === "true") {
      return;
    }

    node.dataset.chatSignalLeaving = "true";
    node.classList.add("chat-typing-indicator--leaving");

    setTimeout(function () {
      if (!node.parentNode) {
        return;
      }

      var parent = node.parentNode;
      node.remove();
      if (parent.classList && parent.classList.contains("chat-signals")) {
        syncSignalContainerState(parent);
      }
    }, SIGNAL_RETREAT_MS);
  }

  function pruneSignals() {
    var now = Math.floor(Date.now() / 1000);
    document.querySelectorAll("[data-chat-signal-at]").forEach(function (node) {
      var at = parseInt(node.dataset.chatSignalAt || "0", 10);
      if (!at) {
        return;
      }

      if (now - at > SIGNAL_TTL_SECONDS) {
        collapseSignalNode(node);
      }
    });
  }

  function setupComposer(element) {
    if (element.dataset.chatComposerBound === "true") {
      return;
    }

    var messageInput = element.querySelector("[data-chat-message-input]");
    var messageForm = element.querySelector("[data-chat-message-form]");
    var signalForm = element.querySelector("[data-chat-signal-form]");
    if (!messageInput || !signalForm || !messageForm) {
      return;
    }

    element.dataset.chatComposerBound = "true";

    var signalStartTimeoutId = null;
    var signalIdleTimeoutId = null;
    var signalHeartbeatIntervalId = null;
    var signalActive = false;
    var signalRequestInFlight = false;
    var pendingSignalClear = false;
    var emitTypingEvents = datasetFlagEnabled(element, "chatEmitTypingEvents");
    var emitMessageEvents = datasetFlagEnabled(element, "chatEmitMessageEvents");
    var typingEventEmitted = false;

    function emitTypingEvent(eventName) {
      if (!emitTypingEvents) {
        return;
      }

      var event = new CustomEvent(eventName, {
        bubbles: true,
        detail: {
          chatId: element.dataset.chatId || null
        }
      });
      element.dispatchEvent(event);
    }

    function emitMessageSentEvent() {
      if (!emitMessageEvents) {
        return;
      }

      var event = new CustomEvent("chat-gem:message-sent", {
        bubbles: true,
        detail: {
          chatId: element.dataset.chatId || null
        }
      });
      element.dispatchEvent(event);
    }

    function postSignal(options) {
      if (signalRequestInFlight) {
        if (options && options.clear) {
          pendingSignalClear = true;
        }
        return;
      }

      signalRequestInFlight = true;
      var formData = new FormData(signalForm);
      formData.set("chat_message[kind]", "signal");
      formData.set("chat_message[signal_type]", "typing");
      formData.set("chat_message[body]", "");
      if (options && options.clear) {
        formData.set("chat_message[clear]", "1");
      } else {
        formData.delete("chat_message[clear]");
      }

      fetch(signalForm.action, {
        method: "POST",
        body: formData,
        credentials: "same-origin",
        headers: {
          "X-CSRF-Token": csrfToken(),
          "Accept": "text/vnd.turbo-stream.html"
        }
      })
        .then(renderTurboStreamResponse)
        .catch(function () {})
        .finally(function () {
          signalRequestInFlight = false;
          if (pendingSignalClear) {
            pendingSignalClear = false;
            postSignal({ clear: true });
          }
        });
    }

    function clearSignalStartTimer() {
      if (!signalStartTimeoutId) {
        return;
      }

      clearTimeout(signalStartTimeoutId);
      signalStartTimeoutId = null;
    }

    function clearSignalIdleTimer() {
      if (!signalIdleTimeoutId) {
        return;
      }

      clearTimeout(signalIdleTimeoutId);
      signalIdleTimeoutId = null;
    }

    function clearSignalHeartbeat() {
      if (!signalHeartbeatIntervalId) {
        return;
      }

      clearInterval(signalHeartbeatIntervalId);
      signalHeartbeatIntervalId = null;
    }

    function resetSignalIdleTimer() {
      clearSignalIdleTimer();
      signalIdleTimeoutId = setTimeout(function () {
        stopSignalLoop();
      }, SIGNAL_IDLE_GRACE_MS);
    }

    function sendTypingSignal() {
      pendingSignalClear = false;
      postSignal();
    }

    function startSignalLoop() {
      if (signalActive) {
        resetSignalIdleTimer();
        return;
      }

      signalActive = true;
      if (!typingEventEmitted) {
        emitTypingEvent("chat-gem:typing-started");
        typingEventEmitted = true;
      }
      sendTypingSignal();
      signalHeartbeatIntervalId = setInterval(function () {
        if (!messageInput.value.trim()) {
          stopSignalLoop();
          return;
        }

        sendTypingSignal();
      }, SIGNAL_HEARTBEAT_MS);
      resetSignalIdleTimer();
    }

    function queueSignalStart() {
      if (signalActive) {
        resetSignalIdleTimer();
        return;
      }

      if (signalStartTimeoutId) {
        return;
      }

      signalStartTimeoutId = setTimeout(function () {
        signalStartTimeoutId = null;
        if (!messageInput.value.trim()) {
          return;
        }

        startSignalLoop();
      }, SIGNAL_START_DELAY_MS);
    }

    function stopSignalLoop() {
      clearSignalStartTimer();
      clearSignalIdleTimer();
      clearSignalHeartbeat();
      if (!signalActive) {
        return;
      }

      signalActive = false;
      if (typingEventEmitted) {
        emitTypingEvent("chat-gem:typing-ended");
        typingEventEmitted = false;
      }
      postSignal({ clear: true });
    }

    messageInput.addEventListener("keydown", function (event) {
      if (event.key !== "Enter") {
        return;
      }

      // Submit on Enter. Keep newline for modified Enter (Shift/Ctrl/Alt/Meta).
      if (event.shiftKey || event.ctrlKey || event.altKey || event.metaKey) {
        return;
      }

      event.preventDefault();
      if (!messageInput.value.trim()) {
        return;
      }

      if (typeof messageForm.requestSubmit === "function") {
        messageForm.requestSubmit();
      } else {
        messageForm.submit();
      }
    });

    messageForm.addEventListener("turbo:submit-end", function (event) {
      if (event.detail && event.detail.success) {
        messageInput.value = "";
        emitMessageSentEvent();
      }

      stopSignalLoop();
    });

    messageForm.addEventListener("submit", function () {
      stopSignalLoop();
    });

    messageInput.addEventListener("input", function () {
      if (!messageInput.value.trim()) {
        stopSignalLoop();
        return;
      }

      queueSignalStart();
      if (signalActive) {
        resetSignalIdleTimer();
      }
    });

    messageInput.addEventListener("blur", function () {
      stopSignalLoop();
    });
  }

  function setupAllComposers() {
    document.querySelectorAll("[data-chat-composer]").forEach(setupComposer);
  }

  function setupChatGemUi() {
    setupAllComposers();
    setupAllMessageAutoScroll();
    setupAllSignalContainers();
    pruneSignals();
  }

  document.addEventListener("turbo:load", setupChatGemUi);
  document.addEventListener("DOMContentLoaded", setupChatGemUi);
  document.addEventListener("turbo:render", setupChatGemUi);
  setInterval(pruneSignals, 1000);
})();
