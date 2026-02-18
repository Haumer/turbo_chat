(function () {
  var SIGNAL_TTL_SECONDS = 12;
  var SIGNAL_START_DELAY_MS = 750;
  var SIGNAL_IDLE_GRACE_MS = 2500;
  var SIGNAL_HEARTBEAT_MS = 4000;
  var SIGNAL_RETREAT_MS = 180;
  var MENTION_MAX_RESULTS = 8;
  var MENTION_BLUR_HIDE_DELAY_MS = 120;
  var MEMBER_MENTION_TOKEN_PATTERN = /^@[a-z0-9_]{1,32}$/i;
  var ROLE_MENTION_TOKEN_PATTERN = /^@[A-Z][A-Z0-9_]{0,31}$/;

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

  function parseMentionOptions(raw) {
    if (!raw) {
      return [];
    }

    var parsed;
    try {
      parsed = JSON.parse(raw);
    } catch (_error) {
      return [];
    }

    if (!Array.isArray(parsed)) {
      return [];
    }

    var seen = {};
    var options = [];

    parsed.forEach(function (entry) {
      if (!entry || typeof entry !== "object") {
        return;
      }

      var token = String(entry.token || "").trim();
      if (!token || token.charAt(0) !== "@" || /\s/.test(token)) {
        return;
      }

      var dedupeKey = token.toLowerCase();
      if (seen[dedupeKey]) {
        return;
      }

      seen[dedupeKey] = true;
      options.push({
        token: token,
        label: String(entry.label || token),
        kind: String(entry.kind || "member")
      });
    });

    return options;
  }

  function parseMentionTokens(raw) {
    if (!raw) {
      return [];
    }

    var parsed = raw;
    if (typeof raw === "string") {
      var trimmed = raw.trim();
      if (!trimmed) {
        return [];
      }

      if (trimmed.charAt(0) === "[") {
        try {
          parsed = JSON.parse(trimmed);
        } catch (_error) {
          parsed = trimmed.split(",");
        }
      } else {
        parsed = trimmed.split(",");
      }
    }

    var source = Array.isArray(parsed) ? parsed : [parsed];
    var seen = {};
    var tokens = [];

    source.forEach(function (entry) {
      var token = String(entry || "").trim();
      if (!token || token.charAt(0) !== "@" || /\s/.test(token)) {
        return;
      }

      var dedupeKey = token.toLowerCase();
      if (seen[dedupeKey]) {
        return;
      }

      seen[dedupeKey] = true;
      tokens.push(token);
    });

    return tokens;
  }

  function mentionKind(token) {
    var mentionToken = String(token || "").trim();
    if (!mentionToken) {
      return null;
    }

    if (mentionToken.toLowerCase() === "@all") {
      return "group";
    }

    if (ROLE_MENTION_TOKEN_PATTERN.test(mentionToken)) {
      return "role";
    }

    if (MEMBER_MENTION_TOKEN_PATTERN.test(mentionToken)) {
      return "member";
    }

    return null;
  }

  function emptyMentionAutocomplete() {
    return {
      hideMenu: function () {},
      updateMenu: function () {},
      handleKeydown: function () {
        return false;
      }
    };
  }

  function setupMentionAutocomplete(input, options) {
    if (!input) {
      return emptyMentionAutocomplete();
    }

    var mentionOptions = Array.isArray(options && options.mentionOptions) ? options.mentionOptions : [];
    var menuHost = options && options.menuHost ? options.menuHost : input.parentNode;
    var menuClassName = options && options.menuClassName ? options.menuClassName : "chat-mentions-menu";
    if (!mentionOptions.length || !menuHost) {
      return emptyMentionAutocomplete();
    }

    var mentionMenu = null;
    var mentionMatches = [];
    var mentionActiveIndex = 0;

    function ensureMentionMenu() {
      if (mentionMenu) {
        return mentionMenu;
      }

      mentionMenu = document.createElement("div");
      mentionMenu.className = menuClassName;
      mentionMenu.hidden = true;
      menuHost.appendChild(mentionMenu);
      return mentionMenu;
    }

    function hideMentionMenu() {
      if (!mentionMenu) {
        return;
      }

      mentionMenu.hidden = true;
      mentionMenu.classList.remove("chat-mentions-menu--open");
      mentionMenu.innerHTML = "";
      mentionMatches = [];
      mentionActiveIndex = 0;
    }

    function setMentionActiveIndex(index) {
      if (!mentionMatches.length) {
        return;
      }

      mentionActiveIndex = ((index % mentionMatches.length) + mentionMatches.length) % mentionMatches.length;
      if (!mentionMenu) {
        return;
      }

      mentionMenu.querySelectorAll(".chat-mentions-item").forEach(function (item, itemIndex) {
        item.classList.toggle("chat-mentions-item--active", itemIndex === mentionActiveIndex);
      });
    }

    function mentionContext() {
      var caret = input.selectionStart;
      if (typeof caret !== "number") {
        return null;
      }

      var beforeCaret = input.value.slice(0, caret);
      var atIndex = beforeCaret.lastIndexOf("@");
      if (atIndex < 0) {
        return null;
      }

      var previousCharacter = atIndex > 0 ? beforeCaret.charAt(atIndex - 1) : "";
      if (/[a-zA-Z0-9_]/.test(previousCharacter)) {
        return null;
      }

      var query = beforeCaret.slice(atIndex + 1);
      if (!/^[a-zA-Z0-9_]*$/.test(query)) {
        return null;
      }

      return {
        start: atIndex,
        end: caret,
        query: query
      };
    }

    function matchingMentionOptions(query) {
      var normalizedQuery = String(query || "").toLowerCase();
      return mentionOptions
        .filter(function (option) {
          return option.token.slice(1).toLowerCase().indexOf(normalizedQuery) === 0;
        })
        .slice(0, MENTION_MAX_RESULTS);
    }

    function insertMentionOption(option) {
      var context = mentionContext();
      if (!context) {
        hideMentionMenu();
        return;
      }

      var before = input.value.slice(0, context.start);
      var after = input.value.slice(context.end);
      var needsTrailingSpace = !after.match(/^[\s,.!?;:)]/);
      var insertion = option.token + (needsTrailingSpace ? " " : "");
      input.value = before + insertion + after;

      var caretPosition = before.length + insertion.length;
      input.setSelectionRange(caretPosition, caretPosition);
      input.focus();

      hideMentionMenu();
      input.dispatchEvent(new Event("input", { bubbles: true }));
    }

    function renderMentionMenu() {
      if (!mentionMatches.length) {
        hideMentionMenu();
        return;
      }

      var menu = ensureMentionMenu();
      menu.innerHTML = "";
      mentionMatches.forEach(function (option, index) {
        var item = document.createElement("button");
        item.type = "button";
        item.className = "chat-mentions-item";
        item.setAttribute("data-chat-mention-index", String(index));
        if (index === mentionActiveIndex) {
          item.classList.add("chat-mentions-item--active");
        }

        var token = document.createElement("span");
        token.className = "chat-mentions-item__token";
        token.textContent = option.token;

        var label = document.createElement("span");
        label.className = "chat-mentions-item__label";
        label.textContent = option.label;

        item.appendChild(token);
        item.appendChild(label);
        item.addEventListener("mousedown", function (event) {
          event.preventDefault();
        });
        item.addEventListener("click", function () {
          insertMentionOption(option);
        });
        menu.appendChild(item);
      });

      menu.hidden = false;
      menu.classList.add("chat-mentions-menu--open");
    }

    function selectActiveMention() {
      if (!mentionMatches.length) {
        return false;
      }

      insertMentionOption(mentionMatches[mentionActiveIndex]);
      return true;
    }

    function updateMentionMenu() {
      var context = mentionContext();
      if (!context) {
        hideMentionMenu();
        return;
      }

      mentionMatches = matchingMentionOptions(context.query);
      if (!mentionMatches.length) {
        hideMentionMenu();
        return;
      }

      mentionActiveIndex = 0;
      renderMentionMenu();
    }

    function handleMentionKeydown(event) {
      if (!mentionMenu || mentionMenu.hidden || !mentionMatches.length) {
        return false;
      }

      if (event.key === "ArrowDown") {
        event.preventDefault();
        setMentionActiveIndex(mentionActiveIndex + 1);
        return true;
      }

      if (event.key === "ArrowUp") {
        event.preventDefault();
        setMentionActiveIndex(mentionActiveIndex - 1);
        return true;
      }

      if (event.key === "Enter" || event.key === "Tab") {
        event.preventDefault();
        return selectActiveMention();
      }

      if (event.key === "Escape") {
        event.preventDefault();
        hideMentionMenu();
        return true;
      }

      return false;
    }

    return {
      hideMenu: hideMentionMenu,
      updateMenu: updateMentionMenu,
      handleKeydown: handleMentionKeydown
    };
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
    var targetScrollTop = Math.max(0, lastBottom - container.clientHeight + signalOverlayOffset(container) + 2);
    container.scrollTop = targetScrollTop;
  }

  function signalOverlayOffset(container) {
    if (!container || typeof window === "undefined") {
      return 0;
    }

    var chatWindow = container.closest(".chat-window");
    if (!chatWindow) {
      return 0;
    }

    var cssOffset = window.getComputedStyle(chatWindow).getPropertyValue("--chat-signal-offset");
    var parsedOffset = parseFloat(cssOffset);
    if (isNaN(parsedOffset) || parsedOffset <= 0) {
      return 0;
    }

    return parsedOffset;
  }

  function prefersReducedMotion() {
    return (
      typeof window !== "undefined" &&
      typeof window.matchMedia === "function" &&
      window.matchMedia("(prefers-reduced-motion: reduce)").matches
    );
  }

  function scrollMessageIntoView(container, messageNode) {
    if (!container || !messageNode) {
      return;
    }

    var containerRect = container.getBoundingClientRect();
    var messageRect = messageNode.getBoundingClientRect();
    var topPadding = 12;
    var bottomPadding = 14 + signalOverlayOffset(container);
    var aboveVisibleArea = messageRect.top < containerRect.top + topPadding;
    var belowVisibleArea = messageRect.bottom > containerRect.bottom - bottomPadding;
    if (!aboveVisibleArea && !belowVisibleArea) {
      return;
    }

    var delta = aboveVisibleArea
      ? messageRect.top - (containerRect.top + topPadding)
      : messageRect.bottom - (containerRect.bottom - bottomPadding);
    var nextTop = Math.max(0, container.scrollTop + delta);

    if (typeof container.scrollTo === "function") {
      container.scrollTo({
        top: nextTop,
        behavior: prefersReducedMotion() ? "auto" : "smooth"
      });
      return;
    }

    container.scrollTop = nextTop;
  }

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
          messageNode.dispatchEvent(new CustomEvent("chat-gem:inline-edit-close"));
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

        var event = new CustomEvent("chat-gem:mention", {
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

          otherMessageNode.dispatchEvent(new CustomEvent("chat-gem:inline-edit-close"));
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
    messageNode.addEventListener("chat-gem:inline-edit-close", function () {
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

    var chatWindow = container.closest(".chat-window");
    if (chatWindow) {
      var messagesContainer = chatWindow.querySelector(".chat-messages");
      var shouldStickToBottom = false;
      if (messagesContainer) {
        var distanceFromBottom = messagesContainer.scrollHeight - (messagesContainer.scrollTop + messagesContainer.clientHeight);
        shouldStickToBottom = distanceFromBottom <= 24;
      }

      var signalOffset = hasVisibleSignals ? Math.ceil(container.scrollHeight) + 8 : 0;
      chatWindow.style.setProperty("--chat-signal-offset", signalOffset + "px");
      chatWindow.classList.toggle("chat-window--signals-active", signalOffset > 0);

      if (messagesContainer && shouldStickToBottom) {
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
    var mentionsEnabled = datasetFlagEnabled(element, "chatEnableMentions");
    var mentionOptions = mentionsEnabled ? parseMentionOptions(element.dataset.chatMentionOptions) : [];
    var mentionAutocomplete = setupMentionAutocomplete(messageInput, {
      mentionOptions: mentionOptions,
      menuHost: element
    });
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
        mentionAutocomplete.hideMenu();
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
