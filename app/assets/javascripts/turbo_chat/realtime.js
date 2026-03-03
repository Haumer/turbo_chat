(function (namespace) {
  var constants = namespace.constants || {};
  var SIGNAL_TTL_SECONDS = constants.SIGNAL_TTL_SECONDS || 60;
  var SIGNAL_START_DELAY_MS = constants.SIGNAL_START_DELAY_MS || 750;
  var SIGNAL_IDLE_GRACE_MS = constants.SIGNAL_IDLE_GRACE_MS || 2500;
  var SIGNAL_HEARTBEAT_MS = constants.SIGNAL_HEARTBEAT_MS || 4000;
  var SIGNAL_RETREAT_MS = constants.SIGNAL_RETREAT_MS || 180;
  var SIGNAL_EMPTY_GRACE_MS = constants.SIGNAL_EMPTY_GRACE_MS || 180;
  var MENTION_BLUR_HIDE_DELAY_MS = constants.MENTION_BLUR_HIDE_DELAY_MS || 120;
  var COMPOSER_MAX_HEIGHT_PX = constants.COMPOSER_MAX_HEIGHT_PX || 210;

  var csrfToken = namespace.csrfToken;
  var renderTurboStreamResponse = namespace.renderTurboStreamResponse;
  var datasetFlagEnabled = namespace.datasetFlagEnabled;
  var parseMentionOptions = namespace.parseMentionOptions;
  var setupMentionAutocomplete = namespace.setupMentionAutocomplete;
  var scrollLastMessageIntoView = namespace.scrollLastMessageIntoView;
  var containerBottomPadding = namespace.containerBottomPadding;

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

  function visibleSignalNode(container) {
    if (!container) {
      return null;
    }

    return container.querySelector(".chat-typing-indicator:not(.chat-typing-indicator--leaving)");
  }

  function clearSignalDeactivateTimer(container) {
    if (!container || !container.__chatSignalDeactivateTimeoutId) {
      return;
    }

    clearTimeout(container.__chatSignalDeactivateTimeoutId);
    container.__chatSignalDeactivateTimeoutId = null;
  }

  function signalTtlSecondsForNode(node) {
    if (!node || typeof node.closest !== "function") {
      return SIGNAL_TTL_SECONDS;
    }

    var container = node.closest(".chat-signals");
    if (!container || !container.dataset) {
      return SIGNAL_TTL_SECONDS;
    }

    var parsedTtl = parseInt(container.dataset.chatSignalTtlSeconds || "", 10);
    if (isNaN(parsedTtl) || parsedTtl <= 0) {
      return SIGNAL_TTL_SECONDS;
    }

    return parsedTtl;
  }

  function queueSignalDeactivate(container) {
    if (!container || container.__chatSignalDeactivateTimeoutId) {
      return;
    }

    container.__chatSignalDeactivateTimeoutId = setTimeout(function () {
      container.__chatSignalDeactivateTimeoutId = null;
      if (!container.isConnected) {
        return;
      }

      syncSignalContainerState(container, { forceInactive: true });
    }, SIGNAL_EMPTY_GRACE_MS);
  }

  function shouldStickMessagesToBottom(messagesContainer) {
    if (!messagesContainer) {
      return false;
    }

    var reservedBottomPadding = containerBottomPadding(messagesContainer);
    var distanceFromBottom = messagesContainer.scrollHeight -
      (messagesContainer.scrollTop + messagesContainer.clientHeight) -
      reservedBottomPadding;
    return distanceFromBottom <= 24;
  }

  function syncSignalContainerState(container, options) {
    if (!container) {
      return;
    }

    options = options || {};
    hideOwnSignals(container);

    var hasVisibleSignals = Boolean(visibleSignalNode(container));

    if (!hasVisibleSignals && !options.forceInactive && container.classList.contains("chat-signals--active")) {
      queueSignalDeactivate(container);
      return;
    }

    if (hasVisibleSignals) {
      clearSignalDeactivateTimer(container);
    }

    container.classList.toggle("chat-signals--active", hasVisibleSignals);

    if (hasVisibleSignals) {
      var messagesContainer = container.closest(".chat-messages");
      if (messagesContainer && shouldStickMessagesToBottom(messagesContainer)) {
        requestAnimationFrame(function () {
          scrollLastMessageIntoView(messagesContainer);
        });
      }
    }
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

    var syncRafId = null;
    function queueSignalContainerSync() {
      if (syncRafId) {
        return;
      }

      if (typeof window === "undefined" || typeof window.requestAnimationFrame !== "function") {
        syncSignalContainerState(container);
        return;
      }

      syncRafId = window.requestAnimationFrame(function () {
        syncRafId = null;
        if (!container.isConnected) {
          return;
        }
        syncSignalContainerState(container);
      });
    }

    var observer = new MutationObserver(function () {
      queueSignalContainerSync();
    });

    observer.observe(container, { childList: true, subtree: true, characterData: true });
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

      if (now - at > signalTtlSecondsForNode(node)) {
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
    var unboundedShell = element.closest(".chat-shell--style-unbounded");
    var composerClearanceRafId = null;
    var mentionsEnabled = datasetFlagEnabled(element, "chatEnableMentions");
    var mentionOptions = mentionsEnabled ? parseMentionOptions(element.dataset.chatMentionOptions) : [];
    var mentionAutocomplete = setupMentionAutocomplete(messageInput, {
      mentionOptions: mentionOptions,
      mentionOptionsResolver: function () {
        return mentionOptions;
      },
      menuHost: element
    });
    var typingEventEmitted = false;

    function updateMentionOptions(nextMentionOptions) {
      mentionOptions = Array.isArray(nextMentionOptions) ? nextMentionOptions : [];
      if (typeof mentionAutocomplete.setOptions === "function") {
        mentionAutocomplete.setOptions(mentionOptions);
      }
      element.dataset.chatMentionOptions = JSON.stringify(mentionOptions);
    }

    element.__chatComposerApi = {
      setMentionOptions: updateMentionOptions
    };

    function syncComposerClearance() {
      if (!unboundedShell) {
        return;
      }

      var viewportHeight = (typeof window !== "undefined" && window.innerHeight) || document.documentElement.clientHeight || 0;
      var composerRect = element.getBoundingClientRect();
      if (viewportHeight > 0 && composerRect && composerRect.height > 0) {
        var coveredHeight = Math.max(0, viewportHeight - composerRect.top);
        if (coveredHeight > 0) {
          unboundedShell.style.setProperty("--chat-floating-composer-clearance", Math.ceil(coveredHeight + 8) + "px");
          return;
        }
      }

      var composerShell = element.querySelector(".chat-composer-shell");
      if (!composerShell) {
        return;
      }

      var composerHeight = Math.ceil(composerShell.getBoundingClientRect().height);
      if (!composerHeight || composerHeight <= 0) {
        return;
      }

      var clearance = composerHeight + 28;
      unboundedShell.style.setProperty("--chat-floating-composer-clearance", clearance + "px");
    }

    function queueComposerClearanceSync() {
      if (!unboundedShell || typeof window === "undefined" || typeof window.requestAnimationFrame !== "function") {
        syncComposerClearance();
        return;
      }

      if (composerClearanceRafId) {
        return;
      }

      composerClearanceRafId = window.requestAnimationFrame(function () {
        composerClearanceRafId = null;
        syncComposerClearance();
      });
    }

    function autoResizeComposerInput() {
      messageInput.style.height = "auto";
      var contentHeight = messageInput.scrollHeight;
      var nextHeight = Math.min(contentHeight, COMPOSER_MAX_HEIGHT_PX);
      messageInput.style.height = nextHeight + "px";
      messageInput.style.overflowY = contentHeight > COMPOSER_MAX_HEIGHT_PX ? "auto" : "hidden";
      queueComposerClearanceSync();
    }

    autoResizeComposerInput();
    if (typeof window !== "undefined") {
      window.addEventListener("resize", queueComposerClearanceSync);
      if (window.visualViewport && typeof window.visualViewport.addEventListener === "function") {
        window.visualViewport.addEventListener("resize", queueComposerClearanceSync);
      }
    }

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

      var event = new CustomEvent("turbo-chat:message-sent", {
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
        emitTypingEvent("turbo-chat:typing-started");
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
        emitTypingEvent("turbo-chat:typing-ended");
        typingEventEmitted = false;
      }
      postSignal({ clear: true });
    }

    messageInput.addEventListener("keydown", function (event) {
      if (mentionAutocomplete.handleKeydown(event)) {
        return;
      }

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
        autoResizeComposerInput();
        mentionAutocomplete.hideMenu();
        emitMessageSentEvent();
      }

      stopSignalLoop();
    });

    messageForm.addEventListener("submit", function () {
      stopSignalLoop();
    });

    messageInput.addEventListener("input", function () {
      autoResizeComposerInput();
      if (!messageInput.value.trim()) {
        stopSignalLoop();
        mentionAutocomplete.hideMenu();
        return;
      }

      mentionAutocomplete.updateMenu();
      queueSignalStart();
      if (signalActive) {
        resetSignalIdleTimer();
      }
    });

    messageInput.addEventListener("blur", function () {
      setTimeout(function () {
        mentionAutocomplete.hideMenu();
      }, MENTION_BLUR_HIDE_DELAY_MS);
      stopSignalLoop();
    });
  }

  function setupAllComposers() {
    document.querySelectorAll("[data-chat-composer]").forEach(setupComposer);
  }

  namespace.setupAllSignalContainers = setupAllSignalContainers;
  namespace.setupAllComposers = setupAllComposers;
  namespace.pruneSignals = pruneSignals;
})(window.TurboChatUI = window.TurboChatUI || {});
