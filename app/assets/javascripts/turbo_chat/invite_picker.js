(function (namespace) {
  var MIN_QUERY_LENGTH = 2;
  var MAX_RESULTS = 8;
  var MENU_BLUR_HIDE_DELAY_MS = 120;

  function normalize(value) {
    return String(value || "").trim().toLowerCase();
  }

  function normalizeOption(option) {
    if (!option || typeof option !== "object") {
      return null;
    }

    var label = String(option.label || "").trim();
    var participantId = String(option.participant_id || option.participantId || "").trim();
    var search = normalize(option.search || label);
    if (!label || !participantId) {
      return null;
    }

    return {
      label: label,
      participantId: participantId,
      search: search
    };
  }

  function parseOptions(rawOptions) {
    if (!rawOptions) {
      return [];
    }

    var parsed = rawOptions;
    if (typeof rawOptions === "string") {
      try {
        parsed = JSON.parse(rawOptions);
      } catch (_error) {
        return [];
      }
    }

    if (!Array.isArray(parsed)) {
      return [];
    }

    var deduped = {};
    var options = [];
    parsed.forEach(function (entry) {
      var normalizedEntry = normalizeOption(entry);
      if (!normalizedEntry) {
        return;
      }

      if (deduped[normalizedEntry.participantId]) {
        return;
      }

      deduped[normalizedEntry.participantId] = true;
      options.push(normalizedEntry);
    });
    return options;
  }

  function serializeOptions(options) {
    return JSON.stringify(options.map(function (option) {
      return {
        label: option.label,
        participant_id: option.participantId,
        search: option.search
      };
    }));
  }

  function matchingOptions(options, query) {
    return options
      .filter(function (optionData) {
        return optionData.search.indexOf(query) !== -1;
      })
      .slice(0, MAX_RESULTS);
  }

  function selectedOptionForValue(options, value) {
    var selected = null;
    var normalizedValue = normalize(value);
    options.forEach(function (optionData) {
      if (!selected && normalize(optionData.label) === normalizedValue) {
        selected = optionData;
      }
    });
    return selected;
  }

  function setupInvitePicker(form) {
    if (!form) {
      return null;
    }

    if (form.dataset.chatInviteFilterBound === "true") {
      return form.__chatInvitePickerApi || null;
    }

    var queryInput = form.querySelector("[data-chat-invite-query-input]");
    var participantIdInput = form.querySelector("[data-chat-invite-participant-id-input]");
    var menu = form.querySelector("[data-chat-invite-menu]");
    var emptyHint = form.querySelector("[data-chat-invite-empty]");
    if (!queryInput || !participantIdInput || !menu) {
      return null;
    }

    form.dataset.chatInviteFilterBound = "true";
    var allOptions = parseOptions(form.dataset.chatInviteOptions);
    var filteredOptions = [];
    var activeIndex = 0;
    var selectedOption = null;
    var submitBtn = form.querySelector("[data-chat-invite-submit]");
    if (submitBtn) submitBtn.disabled = true;

    function persistOptions() {
      form.dataset.chatInviteOptions = serializeOptions(allOptions);
    }

    function clearSelection() {
      selectedOption = null;
      participantIdInput.value = "";
      if (submitBtn) submitBtn.disabled = true;
    }

    function setSelection(optionData) {
      if (!optionData) {
        clearSelection();
        return;
      }

      selectedOption = optionData;
      participantIdInput.value = optionData.participantId;
      queryInput.value = optionData.label;
      queryInput.setCustomValidity("");
      if (submitBtn) submitBtn.disabled = false;
      hideMenu();
    }

    function setActiveIndex(index) {
      if (!filteredOptions.length) {
        activeIndex = 0;
        return;
      }

      activeIndex = ((index % filteredOptions.length) + filteredOptions.length) % filteredOptions.length;
      menu.querySelectorAll("[data-chat-invite-option-index]").forEach(function (item, itemIndex) {
        item.classList.toggle("chat-invite-item--active", itemIndex === activeIndex);
      });
    }

    function hideMenu() {
      menu.hidden = true;
      menu.innerHTML = "";
      filteredOptions = [];
      activeIndex = 0;
    }

    function showHint(message) {
      if (!emptyHint) {
        return;
      }

      emptyHint.textContent = message;
      emptyHint.hidden = false;
    }

    function hideHint() {
      if (!emptyHint) {
        return;
      }

      emptyHint.hidden = true;
    }

    function renderMenu(options) {
      menu.innerHTML = "";
      options.forEach(function (optionData, index) {
        var item = document.createElement("button");
        item.type = "button";
        item.className = "chat-invite-item";
        item.setAttribute("data-chat-invite-option-index", String(index));
        item.textContent = optionData.label;
        if (index === activeIndex) {
          item.classList.add("chat-invite-item--active");
        }

        item.addEventListener("mousedown", function (event) {
          event.preventDefault();
        });
        item.addEventListener("click", function () {
          setSelection(optionData);
        });
        menu.appendChild(item);
      });

      menu.hidden = false;
    }

    function syncQueryState() {
      var query = normalize(queryInput.value);
      var exactMatch = selectedOptionForValue(allOptions, queryInput.value);
      if (exactMatch) {
        selectedOption = exactMatch;
        participantIdInput.value = exactMatch.participantId;
      } else {
        clearSelection();
      }

      if (query.length < MIN_QUERY_LENGTH) {
        hideMenu();
        if (!query.length) {
          hideHint();
        } else {
          showHint("Type at least 2 characters.");
        }
        return;
      }

      if (!allOptions.length && query.length) {
        hideMenu();
        showHint("All eligible participants have been invited.");
        return;
      }

      filteredOptions = matchingOptions(allOptions, query);
      if (!filteredOptions.length) {
        hideMenu();
        showHint("No matching participants.");
        return;
      }

      hideHint();
      activeIndex = 0;
      renderMenu(filteredOptions);
    }

    function upsertOption(optionData) {
      var normalizedOptionData = normalizeOption(optionData);
      if (!normalizedOptionData) {
        return;
      }

      allOptions = allOptions.filter(function (entry) {
        return entry.participantId !== normalizedOptionData.participantId;
      });
      allOptions.push(normalizedOptionData);
      persistOptions();
      syncQueryState();
    }

    function removeParticipant(participantId) {
      var normalizedParticipantId = String(participantId || "").trim();
      if (!normalizedParticipantId) {
        return;
      }

      allOptions = allOptions.filter(function (entry) {
        return entry.participantId !== normalizedParticipantId;
      });

      if (selectedOption && selectedOption.participantId === normalizedParticipantId) {
        clearSelection();
        queryInput.value = "";
      }

      persistOptions();
      syncQueryState();
    }

    function tryAutoSelectSingleMatch() {
      if (selectedOption && participantIdInput.value) {
        return true;
      }

      var query = normalize(queryInput.value);
      if (query.length < MIN_QUERY_LENGTH) {
        return false;
      }

      var matches = matchingOptions(allOptions, query);
      if (matches.length !== 1) {
        return false;
      }

      var onlyMatch = matches[0];
      if (!onlyMatch) {
        return false;
      }

      participantIdInput.value = onlyMatch.participantId;
      queryInput.value = onlyMatch.label;
      queryInput.setCustomValidity("");
      return true;
    }

    queryInput.addEventListener("input", function () {
      if (queryInput.validationMessage) {
        queryInput.setCustomValidity("");
      }

      syncQueryState();
    });
    queryInput.addEventListener("search", syncQueryState);
    queryInput.addEventListener("change", syncQueryState);
    queryInput.addEventListener("focus", function () {
      syncQueryState();
    });
    queryInput.addEventListener("blur", function () {
      setTimeout(function () {
        hideMenu();
      }, MENU_BLUR_HIDE_DELAY_MS);
    });
    queryInput.addEventListener("keydown", function (event) {
      if (menu.hidden || !filteredOptions.length) {
        return;
      }

      if (event.key === "ArrowDown") {
        event.preventDefault();
        setActiveIndex(activeIndex + 1);
        return;
      }

      if (event.key === "ArrowUp") {
        event.preventDefault();
        setActiveIndex(activeIndex - 1);
        return;
      }

      if (event.key === "Enter") {
        event.preventDefault();
        setSelection(filteredOptions[activeIndex]);
        return;
      }

      if (event.key === "Escape") {
        event.preventDefault();
        hideMenu();
      }
    });

    form.addEventListener("submit", function (event) {
      syncQueryState();
      if (tryAutoSelectSingleMatch()) {
        return;
      }

      if (!participantIdInput.value) {
        event.preventDefault();
        queryInput.setCustomValidity("Select one participant from the suggestions.");
        if (typeof queryInput.reportValidity === "function") {
          queryInput.reportValidity();
        }
      }
    });

    form.addEventListener("reset", function () {
      setTimeout(function () {
        clearSelection();
        queryInput.value = "";
        if (submitBtn) submitBtn.disabled = true;
        syncQueryState();
      }, 0);
    });

    form.__chatInvitePickerApi = {
      upsertOption: upsertOption,
      removeParticipant: removeParticipant
    };

    hideMenu();
    hideHint();
    persistOptions();
    return form.__chatInvitePickerApi;
  }

  function setupAllInvitePickers() {
    document.querySelectorAll("[data-chat-invite-form]").forEach(function (form) {
      setupInvitePicker(form);
    });
  }

  namespace.setupInvitePicker = setupInvitePicker;
  namespace.setupAllInvitePickers = setupAllInvitePickers;
})(window.TurboChatUI = window.TurboChatUI || {});
