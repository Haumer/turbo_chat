(function (namespace) {
  var constants = {
    SIGNAL_TTL_SECONDS: 12,
    SIGNAL_START_DELAY_MS: 750,
    SIGNAL_IDLE_GRACE_MS: 2500,
    SIGNAL_HEARTBEAT_MS: 4000,
    SIGNAL_RETREAT_MS: 180,
    MENTION_MAX_RESULTS: 8,
    MENTION_BLUR_HIDE_DELAY_MS: 120,
    MEMBER_MENTION_TOKEN_PATTERN: /^@[a-z0-9_]{1,32}$/i,
    ROLE_MENTION_TOKEN_PATTERN: /^@[A-Z][A-Z0-9_]{0,31}$/
  };

  namespace.constants = constants;

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

  function parseJsonObject(raw) {
    if (!raw) {
      return null;
    }

    try {
      var parsed = JSON.parse(raw);
      if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
        return null;
      }

      return parsed;
    } catch (_error) {
      return null;
    }
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

    if (constants.ROLE_MENTION_TOKEN_PATTERN.test(mentionToken)) {
      return "role";
    }

    if (constants.MEMBER_MENTION_TOKEN_PATTERN.test(mentionToken)) {
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
        .slice(0, constants.MENTION_MAX_RESULTS);
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

  namespace.csrfToken = csrfToken;
  namespace.renderTurboStreamResponse = renderTurboStreamResponse;
  namespace.datasetFlagEnabled = datasetFlagEnabled;
  namespace.parseJsonObject = parseJsonObject;
  namespace.parseMentionOptions = parseMentionOptions;
  namespace.parseMentionTokens = parseMentionTokens;
  namespace.mentionKind = mentionKind;
  namespace.emptyMentionAutocomplete = emptyMentionAutocomplete;
  namespace.setupMentionAutocomplete = setupMentionAutocomplete;
  namespace.scrollLastMessageIntoView = scrollLastMessageIntoView;
  namespace.signalOverlayOffset = signalOverlayOffset;
  namespace.prefersReducedMotion = prefersReducedMotion;
  namespace.scrollMessageIntoView = scrollMessageIntoView;
})(window.TurboChatUI = window.TurboChatUI || {});
