(function (namespace) {
  var constants = namespace.constants || {};
  var MENTION_BLUR_HIDE_DELAY_MS = constants.MENTION_BLUR_HIDE_DELAY_MS || 120;
  var GLOBAL_SCROLLBAR_CLASS = "chat-global-scrollbar";
  var GLOBAL_SCROLLBAR_HIDDEN_CLASS = "chat-global-scrollbar--hidden";

  var datasetFlagEnabled = namespace.datasetFlagEnabled;
  var parseMentionTokens = namespace.parseMentionTokens;
  var parseMentionOptions = namespace.parseMentionOptions;
  var mentionKind = namespace.mentionKind;
  var emptyMentionAutocomplete = namespace.emptyMentionAutocomplete;
  var setupMentionAutocomplete = namespace.setupMentionAutocomplete;
  var scrollMessageIntoView = namespace.scrollMessageIntoView;
  var scrollLastMessageIntoView = namespace.scrollLastMessageIntoView;
  var prefersReducedMotion = namespace.prefersReducedMotion || function () { return false; };

  function syncOwnMessageClasses(container) {
    if (!container || !container.dataset) {
      return;
    }

    var selfType = container.dataset.chatSelfParticipantType;
    var selfId = container.dataset.chatSelfParticipantId;
    var canEditOwnMessages = container.dataset.chatCanEditOwnMessages === "true";
    if (!selfType || !selfId) {
      return;
    }

    container
      .querySelectorAll("[data-chat-message-participant-type][data-chat-message-participant-id]")
      .forEach(function (messageNode) {
        var isOwnMessage =
          messageNode.dataset.chatMessageParticipantType === selfType &&
          messageNode.dataset.chatMessageParticipantId === selfId;
        var canEditMessage = isOwnMessage && canEditOwnMessages;
        messageNode.dataset.chatEditAllowed = canEditMessage ? "true" : "false";

        setupMessageInlineEditing(messageNode);
        messageNode.classList.toggle("chat-bubble--own", isOwnMessage);

        messageNode.querySelectorAll("[data-chat-message-edit-control]").forEach(function (editControl) {
          editControl.hidden = !canEditMessage || messageNode.dataset.chatInlineEditing === "true";
        });

        if (!canEditMessage) {
          messageNode.dispatchEvent(new CustomEvent("turbo-chat:inline-edit-close"));
          messageNode.querySelectorAll("[data-chat-message-view]").forEach(function (viewContainer) {
            viewContainer.hidden = false;
          });
          messageNode.querySelectorAll("[data-chat-message-edit]").forEach(function (editContainer) {
            editContainer.hidden = true;
          });
          messageNode.classList.remove("chat-bubble--editing");
          messageNode.dataset.chatInlineEditing = "false";
        }
      });
  }

  function mentionTokensForMessage(messageNode) {
    if (!messageNode) {
      return [];
    }

    var datasetMentions = parseMentionTokens(messageNode.dataset.chatMessageMentions);
    if (datasetMentions.length) {
      return datasetMentions;
    }

    var seen = {};
    var mentions = [];
    messageNode.querySelectorAll(".chat-mention").forEach(function (mentionNode) {
      var token = String(mentionNode.textContent || "").trim();
      if (!token || token.charAt(0) !== "@" || /\s/.test(token)) {
        return;
      }

      var dedupeKey = token.toLowerCase();
      if (seen[dedupeKey]) {
        return;
      }

      seen[dedupeKey] = true;
      mentions.push(token);
    });

    return mentions;
  }

  function ownMessageNode(container, messageNode) {
    if (!container || !messageNode) {
      return false;
    }

    var selfType = container.dataset.chatSelfParticipantType;
    var selfId = container.dataset.chatSelfParticipantId;
    if (!selfType || !selfId) {
      return false;
    }

    return (
      messageNode.dataset.chatMessageParticipantType === selfType &&
      messageNode.dataset.chatMessageParticipantId === selfId
    );
  }

  function mentionTargetsCurrentParticipant(token, context) {
    if (!context) {
      return false;
    }

    var normalizedToken = String(token || "").trim().toLowerCase();
    if (!normalizedToken) {
      return false;
    }

    if (context.excludeSelf && context.ownMessage) {
      return false;
    }

    if (normalizedToken === "@all") {
      return true;
    }

    if (context.selfRoleMentionToken && normalizedToken === context.selfRoleMentionToken) {
      return true;
    }

    return Boolean(context.selfMentionTokens[normalizedToken]);
  }

  function syncMentionHighlights(container, options) {
    if (!container || !container.dataset) {
      return;
    }

    options = options || {};
    var emitEvents = Boolean(options.emitEvents);
    var emitMentionEvents = datasetFlagEnabled(container, "chatEmitMentionEvents");
    var excludeSelf = datasetFlagEnabled(container, "chatMentionFilterExcludeSelf");
    var selfMentionTokens = {};
    parseMentionTokens(container.dataset.chatSelfMentionTokens).forEach(function (token) {
      selfMentionTokens[token.toLowerCase()] = true;
    });

    var selfRoleMentionToken = parseMentionTokens(container.dataset.chatSelfRoleMentionToken)[0];
    selfRoleMentionToken = selfRoleMentionToken ? selfRoleMentionToken.toLowerCase() : "";

    container
      .querySelectorAll("[data-chat-message-participant-type][data-chat-message-participant-id]")
      .forEach(function (messageNode) {
        var mentions = mentionTokensForMessage(messageNode);
        var mentionKinds = mentions
          .map(function (token) {
            return {
              token: token,
              kind: mentionKind(token)
            };
          })
          .filter(function (entry) {
            return Boolean(entry.kind);
          });

        var context = {
          excludeSelf: excludeSelf,
          ownMessage: ownMessageNode(container, messageNode),
          selfRoleMentionToken: selfRoleMentionToken,
          selfMentionTokens: selfMentionTokens
        };

        var targetedMentions = mentionKinds
          .map(function (entry) {
            return entry.token;
          })
          .filter(function (token) {
            return mentionTargetsCurrentParticipant(token, context);
          });

        var targetedMentionLookup = {};
        targetedMentions.forEach(function (token) {
          targetedMentionLookup[token.toLowerCase()] = true;
        });

        var targetsCurrentParticipant = targetedMentions.length > 0;
        messageNode.classList.remove("chat-bubble--mentioned");

        messageNode.querySelectorAll(".chat-mention").forEach(function (mentionNode) {
          var mentionToken = String(mentionNode.textContent || "").trim().toLowerCase();
          mentionNode.classList.toggle("chat-mention--targeted", Boolean(targetedMentionLookup[mentionToken]));
        });

        if (!emitEvents || !emitMentionEvents || messageNode.dataset.chatMentionEventEmitted === "true") {
          messageNode.dataset.chatMentionEventEmitted = "true";
          return;
        }

        messageNode.dataset.chatMentionEventEmitted = "true";
        if (!mentionKinds.length) {
          return;
        }

        var event = new CustomEvent("turbo-chat:mention", {
          bubbles: true,
          detail: {
            chatId: container.dataset.chatId || null,
            messageId: messageNode.dataset.chatMessageId || null,
            messageElementId: messageNode.id || null,
            participantType: messageNode.dataset.chatMessageParticipantType || null,
            participantId: messageNode.dataset.chatMessageParticipantId || null,
            mentions: mentionKinds.map(function (entry) {
              return entry.token;
            }),
            mentionKinds: mentionKinds,
            targetedMentions: targetedMentions,
            targetsCurrentParticipant: targetsCurrentParticipant
          }
        });
        container.dispatchEvent(event);
      });
  }

  function setupMessageInlineEditing(messageNode) {
    if (!messageNode || messageNode.dataset.chatInlineEditBound === "true") {
      return;
    }

    var editContainer = messageNode.querySelector("[data-chat-message-edit]");
    if (!editContainer) {
      return;
    }

    var viewContainer = messageNode.querySelector("[data-chat-message-view]");
    var textarea = editContainer.querySelector("[data-chat-inline-edit-input]") || editContainer.querySelector("textarea");
    var editButtons = messageNode.querySelectorAll("[data-chat-edit-start]");
    var cancelButtons = messageNode.querySelectorAll("[data-chat-edit-cancel]");
    var forms = messageNode.querySelectorAll("[data-chat-inline-edit-form]");
    var saveButtons = messageNode.querySelectorAll("[data-chat-edit-save]");
    var form = forms[0] || null;
    var originalBody = textarea ? textarea.value : "";
    var mentionContainer = editContainer.querySelector(".chat-inline-edit-field") || form || editContainer;
    var mentionAutocomplete = emptyMentionAutocomplete();

    if (form && textarea && datasetFlagEnabled(form, "chatEnableMentions")) {
      mentionAutocomplete = setupMentionAutocomplete(textarea, {
        mentionOptions: parseMentionOptions(form.dataset.chatMentionOptions),
        menuHost: mentionContainer,
        menuClassName: "chat-mentions-menu chat-mentions-menu--inline-edit"
      });
    }

    function canEditMessage() {
      return messageNode.dataset.chatEditAllowed === "true";
    }

    function canSubmitEdit() {
      if (!textarea) {
        return false;
      }

      return textarea.value.trim().length > 0 && textarea.value !== originalBody;
    }

    function updateSaveState() {
      var submitEnabled = canSubmitEdit();
      saveButtons.forEach(function (saveButton) {
        saveButton.disabled = !submitEnabled;
      });
    }

    function closeOtherEditors() {
      var messagesContainer = messageNode.closest(".chat-messages");
      if (!messagesContainer) {
        return;
      }

      messagesContainer
        .querySelectorAll("[data-chat-message-participant-type][data-chat-message-participant-id]")
        .forEach(function (otherMessageNode) {
          if (otherMessageNode === messageNode) {
            return;
          }

          otherMessageNode.dispatchEvent(new CustomEvent("turbo-chat:inline-edit-close"));
        });
    }

    function setEditing(editing, options) {
      options = options || {};
      if (editing && !canEditMessage()) {
        return;
      }

      if (!editing && options.restoreOriginal && textarea) {
        textarea.value = originalBody;
      }

      if (editing) {
        closeOtherEditors();
      }

      if (viewContainer) {
        viewContainer.hidden = editing;
      }
      editContainer.hidden = !editing;
      messageNode.dataset.chatInlineEditing = editing ? "true" : "false";
      messageNode.classList.toggle("chat-bubble--editing", editing);
      editButtons.forEach(function (button) {
        button.hidden = !canEditMessage() || editing;
      });
      updateSaveState();

      if (editing && textarea) {
        textarea.focus();
        if (typeof textarea.setSelectionRange === "function") {
          var length = textarea.value.length;
          textarea.setSelectionRange(length, length);
        }

        requestAnimationFrame(function () {
          scrollMessageIntoView(messageNode.closest(".chat-messages"), messageNode);
        });
      }

      if (!editing) {
        mentionAutocomplete.hideMenu();
      }
    }

    messageNode.dataset.chatInlineEditBound = "true";
    messageNode.addEventListener("turbo-chat:inline-edit-close", function () {
      setEditing(false, { restoreOriginal: true });
    });

    editButtons.forEach(function (button) {
      button.addEventListener("click", function () {
        setEditing(true);
      });
    });

    cancelButtons.forEach(function (button) {
      button.addEventListener("click", function () {
        setEditing(false, { restoreOriginal: true });
      });
    });

    if (textarea) {
      textarea.addEventListener("keydown", function (event) {
        if (mentionAutocomplete.handleKeydown(event)) {
          return;
        }

        if (event.key === "Escape") {
          event.preventDefault();
          setEditing(false, { restoreOriginal: true });
          return;
        }

        if (event.key === "Enter" && (event.metaKey || event.ctrlKey) && !event.shiftKey && !event.altKey) {
          event.preventDefault();
          if (!form || !canSubmitEdit()) {
            return;
          }

          if (typeof form.requestSubmit === "function") {
            form.requestSubmit();
          } else {
            form.submit();
          }
        }
      });

      textarea.addEventListener("input", function () {
        mentionAutocomplete.updateMenu();
        updateSaveState();
      });

      textarea.addEventListener("blur", function () {
        setTimeout(function () {
          mentionAutocomplete.hideMenu();
        }, MENTION_BLUR_HIDE_DELAY_MS);
      });
    }

    forms.forEach(function (form) {
      form.addEventListener("submit", function () {
        mentionAutocomplete.hideMenu();
      });

      form.addEventListener("turbo:submit-end", function (event) {
        if (event.detail && event.detail.success) {
          if (textarea) {
            originalBody = textarea.value;
          }
          setEditing(false);
          return;
        }

        updateSaveState();
      });
    });

    var initiallyEditing = !editContainer.hidden;
    if (viewContainer) {
      viewContainer.hidden = initiallyEditing;
    }
    messageNode.dataset.chatInlineEditing = initiallyEditing ? "true" : "false";
    messageNode.classList.toggle("chat-bubble--editing", initiallyEditing);
    editButtons.forEach(function (button) {
      button.hidden = !canEditMessage() || initiallyEditing;
    });
    updateSaveState();

    if (initiallyEditing) {
      closeOtherEditors();
    }
  }

  function setupMessageAutoScroll(container) {
    if (!container || container.dataset.chatAutoscrollBound === "true") {
      return;
    }

    container.dataset.chatAutoscrollBound = "true";
    requestAnimationFrame(function () {
      syncOwnMessageClasses(container);
      syncMentionHighlights(container, { emitEvents: false });
      scrollLastMessageIntoView(container);
    });

    var observer = new MutationObserver(function () {
      requestAnimationFrame(function () {
        syncOwnMessageClasses(container);
        syncMentionHighlights(container, { emitEvents: true });
        scrollLastMessageIntoView(container);
      });
    });

    observer.observe(container, { childList: true });

    setupUnboundedWheelScrollProxy(container);
  }

  function normalizeWheelDeltaY(event) {
    if (!event) {
      return 0;
    }

    var deltaY = event.deltaY;
    if (!deltaY) {
      return 0;
    }

    if (event.deltaMode === 1) {
      return deltaY * 16;
    }

    if (event.deltaMode === 2) {
      var viewportHeight = (typeof window !== "undefined" && window.innerHeight) || 800;
      return deltaY * viewportHeight;
    }

    return deltaY;
  }

  function shouldIgnoreWheelProxy(event, container) {
    if (!event) {
      return true;
    }

    if (container.contains(event.target)) {
      return true;
    }

    if (
      event.target &&
      typeof event.target.closest === "function" &&
      event.target.closest(
        ".chat-members-list-shell, .chat-invite-menu, .chat-mentions-menu, textarea, input, select, [contenteditable='true']"
      )
    ) {
      return true;
    }

    return false;
  }

  function clampScrollTop(container, scrollTop) {
    if (!container) {
      return 0;
    }

    var maxScrollTop = Math.max(0, container.scrollHeight - container.clientHeight);
    if (scrollTop < 0) {
      return 0;
    }

    if (scrollTop > maxScrollTop) {
      return maxScrollTop;
    }

    return scrollTop;
  }

  function startSmoothWheelScroll(state) {
    if (!state || state.smoothScrollRafId) {
      return;
    }

    function step() {
      state.smoothScrollRafId = null;

      var container = state.container;
      if (!container || !container.isConnected) {
        return;
      }

      var targetScrollTop = clampScrollTop(container, state.smoothTargetScrollTop);
      state.smoothTargetScrollTop = targetScrollTop;

      var currentScrollTop = container.scrollTop;
      var remainingDelta = targetScrollTop - currentScrollTop;
      if (Math.abs(remainingDelta) <= 0.5) {
        if (currentScrollTop !== targetScrollTop) {
          state.syncingFromWheelAnimation = true;
          container.scrollTop = targetScrollTop;
          state.syncingFromWheelAnimation = false;
          queueGlobalScrollbarSync(state);
        }
        return;
      }

      state.syncingFromWheelAnimation = true;
      container.scrollTop = currentScrollTop + remainingDelta * 0.22;
      state.syncingFromWheelAnimation = false;
      queueGlobalScrollbarSync(state);
      state.smoothScrollRafId = window.requestAnimationFrame(step);
    }

    state.smoothScrollRafId = window.requestAnimationFrame(step);
  }

  function proxyWheelToMessages(state, event) {
    var container = state && state.container;
    if (!container) {
      return false;
    }

    var deltaY = normalizeWheelDeltaY(event);
    if (!deltaY) {
      return false;
    }

    var currentTarget = typeof state.smoothTargetScrollTop === "number"
      ? state.smoothTargetScrollTop
      : container.scrollTop;
    var nextScrollTop = clampScrollTop(container, currentTarget + deltaY);

    if (nextScrollTop === currentTarget) {
      return false;
    }

    state.smoothTargetScrollTop = nextScrollTop;
    if (prefersReducedMotion()) {
      container.scrollTop = nextScrollTop;
      queueGlobalScrollbarSync(state);
      return true;
    }

    if (typeof window === "undefined" || typeof window.requestAnimationFrame !== "function") {
      container.scrollTop = nextScrollTop;
      queueGlobalScrollbarSync(state);
      return true;
    }

    startSmoothWheelScroll(state);
    return true;
  }

  function createGlobalScrollbar() {
    var scrollbar = document.createElement("div");
    scrollbar.className = GLOBAL_SCROLLBAR_CLASS + " " + GLOBAL_SCROLLBAR_HIDDEN_CLASS;
    scrollbar.setAttribute("aria-hidden", "true");

    var spacer = document.createElement("div");
    spacer.className = "chat-global-scrollbar-spacer";
    scrollbar.appendChild(spacer);

    if (document.body) {
      document.body.appendChild(scrollbar);
    }

    return { scrollbar: scrollbar, spacer: spacer };
  }

  function ensureGlobalScrollbar(state) {
    if (state.globalScrollbar && state.globalScrollbar.isConnected && state.globalScrollbarSpacer) {
      return;
    }

    var created = createGlobalScrollbar();
    state.globalScrollbar = created.scrollbar;
    state.globalScrollbarSpacer = created.spacer;

    state.globalScrollbar.addEventListener("scroll", function () {
      var container = state.container;
      if (!container || !container.isConnected || state.syncingFromMessages) {
        return;
      }

      state.syncingFromScrollbar = true;
      var targetTop = clampScrollTop(container, state.globalScrollbar.scrollTop);
      state.smoothTargetScrollTop = targetTop;
      container.scrollTop = targetTop;
      state.syncingFromScrollbar = false;
    });
  }

  function syncGlobalScrollbar(state) {
    var container = state.container;
    if (!container || !container.isConnected) {
      return;
    }

    ensureGlobalScrollbar(state);
    var globalScrollbar = state.globalScrollbar;
    var spacer = state.globalScrollbarSpacer;
    if (!globalScrollbar || !spacer) {
      return;
    }

    var maxScrollTop = Math.max(0, container.scrollHeight - container.clientHeight);
    var globalViewportHeight = globalScrollbar.clientHeight || ((typeof window !== "undefined" && window.innerHeight) || 0);
    var spacerHeight = Math.max(globalViewportHeight, Math.ceil(maxScrollTop + globalViewportHeight));
    spacer.style.height = spacerHeight + "px";

    var hideScrollbar = maxScrollTop <= 1;
    globalScrollbar.classList.toggle(GLOBAL_SCROLLBAR_HIDDEN_CLASS, hideScrollbar);
    if (hideScrollbar) {
      if (globalScrollbar.scrollTop !== 0) {
        globalScrollbar.scrollTop = 0;
      }
      return;
    }

    var targetScrollTop = Math.min(maxScrollTop, container.scrollTop);
    if (!state.smoothScrollRafId) {
      state.smoothTargetScrollTop = targetScrollTop;
    }
    if (Math.abs(globalScrollbar.scrollTop - targetScrollTop) > 1) {
      state.syncingFromMessages = true;
      globalScrollbar.scrollTop = targetScrollTop;
      state.syncingFromMessages = false;
    }
  }

  function queueGlobalScrollbarSync(state) {
    if (!state || state.syncRafId) {
      return;
    }

    if (typeof window === "undefined" || typeof window.requestAnimationFrame !== "function") {
      syncGlobalScrollbar(state);
      return;
    }

    state.syncRafId = window.requestAnimationFrame(function () {
      state.syncRafId = null;
      syncGlobalScrollbar(state);
    });
  }

  function bindContainerScrollProxy(state, container) {
    if (state.boundContainer === container) {
      return;
    }

    if (state.boundContainer && state.onContainerScroll) {
      state.boundContainer.removeEventListener("scroll", state.onContainerScroll);
    }

    if (state.mutationObserver) {
      state.mutationObserver.disconnect();
    }

    state.boundContainer = container;
    state.container = container;

    state.onContainerScroll = function () {
      if (!state.globalScrollbar || state.syncingFromScrollbar) {
        return;
      }

      if (!state.syncingFromWheelAnimation) {
        state.smoothTargetScrollTop = container.scrollTop;
      }
      state.syncingFromMessages = true;
      state.globalScrollbar.scrollTop = container.scrollTop;
      state.syncingFromMessages = false;
    };
    container.addEventListener("scroll", state.onContainerScroll, { passive: true });

    state.mutationObserver = new MutationObserver(function () {
      queueGlobalScrollbarSync(state);
    });
    state.mutationObserver.observe(container, { childList: true, subtree: true, characterData: true });

    queueGlobalScrollbarSync(state);
  }

  function cleanupDetachedGlobalScrollbars() {
    if (document.querySelector(".chat-shell--style-unbounded")) {
      return;
    }

    document.querySelectorAll("." + GLOBAL_SCROLLBAR_CLASS).forEach(function (node) {
      node.remove();
    });
  }

  function setupUnboundedWheelScrollProxy(container) {
    if (!container) {
      return;
    }

    var shell = container.closest(".chat-shell--style-unbounded");
    if (!shell) {
      return;
    }

    var state = shell.__chatWheelProxyState;
    if (!state) {
      state = {
        shell: shell,
        container: container,
        boundContainer: null,
        globalScrollbar: null,
        globalScrollbarSpacer: null,
        mutationObserver: null,
        syncingFromMessages: false,
        syncingFromScrollbar: false,
        syncRafId: null,
        onContainerScroll: null,
        smoothTargetScrollTop: container.scrollTop,
        smoothScrollRafId: null,
        syncingFromWheelAnimation: false
      };
      shell.__chatWheelProxyState = state;

      state.forwardWheel = function (event) {
        if (state.globalScrollbar && state.globalScrollbar.contains(event.target)) {
          return;
        }

        var activeContainer = state.container;
        if (!activeContainer || !activeContainer.isConnected) {
          return;
        }

        if (shouldIgnoreWheelProxy(event, activeContainer)) {
          return;
        }

        if (proxyWheelToMessages(state, event)) {
          event.preventDefault();
        }
      };

      state.forwardWheelOutsideShell = function (event) {
        if (!shell.isConnected || !state.container || !state.container.isConnected) {
          return;
        }

        if (shell.contains(event.target)) {
          return;
        }

        state.forwardWheel(event);
      };

      state.onViewportResize = function () {
        queueGlobalScrollbarSync(state);
      };

      shell.addEventListener("wheel", state.forwardWheel, { passive: false });
      document.addEventListener("wheel", state.forwardWheelOutsideShell, { passive: false });
      if (typeof window !== "undefined") {
        window.addEventListener("resize", state.onViewportResize);
        if (window.visualViewport && typeof window.visualViewport.addEventListener === "function") {
          window.visualViewport.addEventListener("resize", state.onViewportResize);
        }
      }
    } else {
      state.container = container;
    }

    bindContainerScrollProxy(state, container);
  }

  function syncAllGlobalScrollbars() {
    document.querySelectorAll(".chat-shell--style-unbounded").forEach(function (shell) {
      var state = shell.__chatWheelProxyState;
      if (!state || !state.container || !state.container.isConnected) {
        return;
      }

      queueGlobalScrollbarSync(state);
    });
  }

  function setupAllMessageAutoScroll() {
    document.querySelectorAll(".chat-messages").forEach(setupMessageAutoScroll);
    syncAllGlobalScrollbars();
    cleanupDetachedGlobalScrollbars();
  }

  namespace.setupAllMessageAutoScroll = setupAllMessageAutoScroll;
})(window.TurboChatUI = window.TurboChatUI || {});
