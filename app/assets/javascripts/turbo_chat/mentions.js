(function () {
  "use strict";
  var namespace = (window.TurboChatUI = window.TurboChatUI || {});
  var constants = namespace.constants;

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
    var mentionOptionsResolver = options && typeof options.mentionOptionsResolver === "function"
      ? options.mentionOptionsResolver
      : null;
    var menuHost = options && options.menuHost ? options.menuHost : input.parentNode;
    var menuClassName = options && options.menuClassName ? options.menuClassName : "chat-mentions-menu";
    if ((!mentionOptions.length && !mentionOptionsResolver) || !menuHost) {
      return emptyMentionAutocomplete();
    }

    var mentionMenu = null;
    var mentionMatches = [];
    var mentionActiveIndex = 0;

    function availableMentionOptions() {
      if (mentionOptionsResolver) {
        var resolvedMentionOptions = mentionOptionsResolver();
        return Array.isArray(resolvedMentionOptions) ? resolvedMentionOptions : [];
      }

      return mentionOptions;
    }

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
      return availableMentionOptions()
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
      handleKeydown: handleMentionKeydown,
      setOptions: function (nextMentionOptions) {
        mentionOptions = Array.isArray(nextMentionOptions) ? nextMentionOptions : [];
        updateMentionMenu();
      }
    };
  }

  namespace.parseMentionOptions = parseMentionOptions;
  namespace.parseMentionTokens = parseMentionTokens;
  namespace.mentionKind = mentionKind;
  namespace.emptyMentionAutocomplete = emptyMentionAutocomplete;
  namespace.setupMentionAutocomplete = setupMentionAutocomplete;
})();
