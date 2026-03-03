(function (namespace) {
  var constants = {
    SIGNAL_TTL_SECONDS: 60,
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

  function scrollLastMessageIntoView(container) {
    if (!container) {
      return;
    }

    var insertPosition = String(container.dataset.chatMessageInsertPosition || "").trim().toLowerCase();
    if (insertPosition === "append_start") {
      var firstMessage = container.firstElementChild;
      if (!firstMessage) {
        return;
      }

      container.scrollTop = Math.max(0, firstMessage.offsetTop - 2);
      return;
    }

    // Skip the signals container (always last child) to find the last actual message.
    var lastChild = container.lastElementChild;
    var lastMessage = (lastChild && lastChild.classList.contains("chat-signals"))
      ? lastChild.previousElementSibling
      : lastChild;
    if (!lastMessage) {
      return;
    }

    // Keep the last message fully visible with a tiny breathing space.
    var bottomPadding = containerBottomPadding(container);
    var lastBottom = lastMessage.offsetTop + lastMessage.offsetHeight;
    var targetScrollTop = Math.max(0, lastBottom - container.clientHeight + bottomPadding + 2);
    container.scrollTop = targetScrollTop;
  }

  function containerBottomPadding(container) {
    if (!container || typeof window === "undefined") {
      return 0;
    }

    var cssPadding = window.getComputedStyle(container).paddingBottom;
    var parsedPadding = parseFloat(cssPadding);
    if (isNaN(parsedPadding) || parsedPadding <= 0) {
      return 0;
    }

    return parsedPadding;
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
    var bottomPadding = Math.max(14, containerBottomPadding(container));
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
  namespace.scrollLastMessageIntoView = scrollLastMessageIntoView;
  namespace.containerBottomPadding = containerBottomPadding;
  namespace.prefersReducedMotion = prefersReducedMotion;
  namespace.scrollMessageIntoView = scrollMessageIntoView;
})(window.TurboChatUI = window.TurboChatUI || {});
