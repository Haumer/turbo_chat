(function () {
  "use strict";
  var namespace = (window.TurboChatUI = window.TurboChatUI || {});
  var prefersReducedMotion = namespace.prefersReducedMotion || function () { return false; };

  var GLOBAL_SCROLLBAR_CLASS = "chat-global-scrollbar";
  var GLOBAL_SCROLLBAR_HIDDEN_CLASS = "chat-global-scrollbar--hidden";

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

  namespace.setupUnboundedWheelScrollProxy = setupUnboundedWheelScrollProxy;
  namespace.syncAllGlobalScrollbars = syncAllGlobalScrollbars;
  namespace.cleanupDetachedGlobalScrollbars = cleanupDetachedGlobalScrollbars;
})();
