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

    function persistOptions() {
      form.dataset.chatInviteOptions = serializeOptions(allOptions);
    }

    function clearSelection() {
      selectedOption = null;
      participantIdInput.value = "";
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

  function parseMemberEntry(node) {
    if (!node || !node.dataset || node.dataset.chatMemberEntry !== "true") {
      return null;
    }

    var chatId = String(node.dataset.chatId || "").trim();
    var participantType = String(node.dataset.chatMemberParticipantType || "").trim();
    var participantId = String(node.dataset.chatMemberParticipantId || "").trim();
    var mentionToken = String(node.dataset.chatMemberMentionToken || "").trim();
    var roleKey = String(node.dataset.chatMemberRoleKey || "").trim();
    var roleName = String(node.dataset.chatMemberRoleName || "").trim();
    var roleRank = parseInt(node.dataset.chatMemberRoleRank || "-1", 10);
    var name = String(node.dataset.chatMemberName || "").trim();
    var inviteLabel = String(node.dataset.chatMemberInviteLabel || "").trim();
    var search = normalize(node.dataset.chatMemberSearch || inviteLabel || name);

    if (!chatId || !participantType || !participantId) {
      return null;
    }

    return {
      identity: participantType + ":" + participantId,
      chatId: chatId,
      participantType: participantType,
      participantId: participantId,
      mentionToken: mentionToken,
      name: name,
      roleKey: roleKey,
      roleName: roleName,
      roleRank: isNaN(roleRank) ? -1 : roleRank,
      inviteOption: {
        label: inviteLabel,
        participantId: participantId,
        search: search
      }
    };
  }

  function collectMemberEntries(sourceNode, entryMap) {
    if (!sourceNode || sourceNode.nodeType !== 1) {
      return;
    }

    var sourceElement = sourceNode;
    var sourceEntry = parseMemberEntry(sourceElement);
    if (sourceEntry) {
      entryMap[sourceEntry.identity] = sourceEntry;
    }

    if (typeof sourceElement.querySelectorAll !== "function") {
      return;
    }

    sourceElement.querySelectorAll("[data-chat-member-entry='true']").forEach(function (memberEntryNode) {
      var memberEntry = parseMemberEntry(memberEntryNode);
      if (!memberEntry) {
        return;
      }

      entryMap[memberEntry.identity] = memberEntry;
    });
  }

  function findInvitePickerApis(chatId) {
    var apis = [];
    var normalizedChatId = String(chatId || "").trim();
    if (!normalizedChatId) {
      return apis;
    }

    document.querySelectorAll("[data-chat-invite-form]").forEach(function (form) {
      if (String(form.dataset.chatId || "").trim() !== normalizedChatId) {
        return;
      }

      var api = setupInvitePicker(form);
      if (api) {
        apis.push(api);
      }
    });

    return apis;
  }

  function memberListForChat(chatId) {
    var normalizedChatId = String(chatId || "").trim();
    if (!normalizedChatId) {
      return null;
    }

    var matchedList = null;
    document.querySelectorAll("[data-chat-member-list]").forEach(function (memberList) {
      if (!matchedList && String(memberList.dataset.chatId || "").trim() === normalizedChatId) {
        matchedList = memberList;
      }
    });
    return matchedList;
  }

  function shellForChat(chatId) {
    var normalizedChatId = String(chatId || "").trim();
    if (!normalizedChatId) {
      return null;
    }

    var matchedShell = null;
    document.querySelectorAll(".chat-shell[data-chat-id]").forEach(function (shell) {
      if (!matchedShell && String(shell.dataset.chatId || "").trim() === normalizedChatId) {
        matchedShell = shell;
      }
    });
    return matchedShell;
  }

  function syncInviteOptionsFromMemberMutations(chatId, mutationRecords) {
    var invitePickerApis = findInvitePickerApis(chatId);
    if (!invitePickerApis.length) {
      return;
    }

    var removedEntries = {};
    var addedEntries = {};

    mutationRecords.forEach(function (record) {
      if (!record) {
        return;
      }

      record.removedNodes.forEach(function (removedNode) {
        collectMemberEntries(removedNode, removedEntries);
      });

      record.addedNodes.forEach(function (addedNode) {
        collectMemberEntries(addedNode, addedEntries);
      });
    });

    Object.keys(removedEntries).forEach(function (entryKey) {
      if (addedEntries[entryKey]) {
        return;
      }

      var removedEntry = removedEntries[entryKey];
      invitePickerApis.forEach(function (invitePickerApi) {
        invitePickerApi.upsertOption(removedEntry.inviteOption);
      });
    });

    Object.keys(addedEntries).forEach(function (entryKey) {
      var addedEntry = addedEntries[entryKey];
      invitePickerApis.forEach(function (invitePickerApi) {
        invitePickerApi.removeParticipant(addedEntry.participantId);
      });
    });
  }

  function mentionOptionsForComposer(composer, memberEntries) {
    if (!composer || composer.dataset.chatEnableMentions !== "true") {
      return [];
    }

    var canMentionMembers = composer.dataset.chatCanMentionMembers === "true";
    var canMentionAll = composer.dataset.chatCanMentionAll === "true";
    var canMentionRoles = composer.dataset.chatCanMentionRoles === "true";
    var hideRoles = composer.dataset.chatMentionFilterHideRoles === "true";
    var excludeSelf = composer.dataset.chatMentionFilterExcludeSelf === "true";
    var selfType = String(composer.dataset.chatSelfParticipantType || "").trim();
    var selfId = String(composer.dataset.chatSelfParticipantId || "").trim();
    var mentionOptions = [];
    var seenTokens = {};

    function addMentionOption(optionData) {
      if (!optionData || !optionData.token) {
        return;
      }

      var dedupeToken = normalize(optionData.token);
      if (!dedupeToken || seenTokens[dedupeToken]) {
        return;
      }

      seenTokens[dedupeToken] = true;
      mentionOptions.push(optionData);
    }

    if (canMentionAll) {
      addMentionOption({ token: "@all", label: "All members", kind: "group" });
    }

    if (canMentionMembers) {
      memberEntries.forEach(function (memberEntry) {
        if (excludeSelf && memberEntry.participantType === selfType && memberEntry.participantId === selfId) {
          return;
        }

        if (!memberEntry.mentionToken) {
          return;
        }

        addMentionOption({
          token: memberEntry.mentionToken,
          label: memberEntry.name || memberEntry.mentionToken,
          kind: "member",
          participant_type: memberEntry.participantType,
          participant_id: memberEntry.participantId
        });
      });
    }

    if (canMentionRoles && !hideRoles) {
      memberEntries.forEach(function (memberEntry) {
        if (!memberEntry.roleKey) {
          return;
        }

        var roleToken = "@" + memberEntry.roleKey.toUpperCase();
        var roleLabel = (memberEntry.roleName || memberEntry.roleKey) + " role";
        addMentionOption({
          token: roleToken,
          label: roleLabel,
          kind: "role"
        });
      });
    }

    return mentionOptions;
  }

  function syncComposerMentionOptionsForChat(chatId) {
    var memberList = memberListForChat(chatId);
    if (!memberList) {
      return;
    }

    var memberEntries = [];
    memberList.querySelectorAll("[data-chat-member-entry='true']").forEach(function (memberNode) {
      var memberEntry = parseMemberEntry(memberNode);
      if (memberEntry) {
        memberEntries.push(memberEntry);
      }
    });

    document.querySelectorAll("[data-chat-composer]").forEach(function (composer) {
      if (String(composer.dataset.chatId || "").trim() !== String(chatId).trim()) {
        return;
      }

      if (!composer.__chatComposerApi || typeof composer.__chatComposerApi.setMentionOptions !== "function") {
        return;
      }

      composer.__chatComposerApi.setMentionOptions(mentionOptionsForComposer(composer, memberEntries));
    });
  }

  function setupMemberManageControlsForChat(chatId) {
    var memberList = memberListForChat(chatId);
    if (!memberList) {
      return;
    }

    memberList.querySelectorAll("[data-chat-member-entry='true']").forEach(function (memberNode) {
      if (!memberNode || memberNode.dataset.chatMemberManageBound === "true") {
        return;
      }

      var toggle = memberNode.querySelector("[data-chat-member-manage-toggle]");
      var panel = memberNode.querySelector("[data-chat-member-manage-panel]");
      if (!toggle || !panel) {
        return;
      }

      memberNode.dataset.chatMemberManageBound = "true";
      panel.hidden = true;
      toggle.setAttribute("aria-expanded", "false");

      toggle.addEventListener("click", function () {
        if (toggle.disabled) {
          return;
        }

        var expanded = toggle.getAttribute("aria-expanded") === "true";
        var parentList = memberNode.closest("[data-chat-member-list]");
        if (parentList) {
          parentList.querySelectorAll("[data-chat-member-manage-toggle]").forEach(function (otherToggle) {
            otherToggle.setAttribute("aria-expanded", "false");
          });
          parentList.querySelectorAll("[data-chat-member-manage-panel]").forEach(function (otherPanel) {
            otherPanel.hidden = true;
          });
        }

        if (expanded) {
          panel.hidden = true;
          toggle.setAttribute("aria-expanded", "false");
          return;
        }

        panel.hidden = false;
        toggle.setAttribute("aria-expanded", "true");
        var roleInput = panel.querySelector("[data-chat-member-role-input]");
        if (roleInput && !roleInput.disabled) {
          roleInput.focus();
        }
      });
    });
  }

  function syncRoleFormAccessForChat(chatId) {
    var memberList = memberListForChat(chatId);
    var shell = shellForChat(chatId);
    if (!memberList || !shell) {
      return;
    }

    var canManage = shell.dataset.chatCanManageMemberPermissions === "true";
    var selfType = String(shell.dataset.chatSelfParticipantType || "").trim();
    var selfId = String(shell.dataset.chatSelfParticipantId || "").trim();
    var selfRoleRank = -1;

    memberList.querySelectorAll("[data-chat-member-entry='true']").forEach(function (memberNode) {
      if (
        String(memberNode.dataset.chatMemberParticipantType || "").trim() === selfType &&
        String(memberNode.dataset.chatMemberParticipantId || "").trim() === selfId
      ) {
        var rank = parseInt(memberNode.dataset.chatMemberRoleRank || "-1", 10);
        selfRoleRank = isNaN(rank) ? -1 : rank;
      }
    });

    memberList.querySelectorAll("[data-chat-member-entry='true']").forEach(function (memberNode) {
      var targetType = String(memberNode.dataset.chatMemberParticipantType || "").trim();
      var targetId = String(memberNode.dataset.chatMemberParticipantId || "").trim();
      var targetRoleRank = parseInt(memberNode.dataset.chatMemberRoleRank || "-1", 10);
      if (isNaN(targetRoleRank)) {
        targetRoleRank = -1;
      }

      var isSelf = targetType === selfType && targetId === selfId;
      var targetManageableByRank = selfRoleRank < 0 || targetRoleRank < selfRoleRank;
      var controlsEnabled = canManage && !isSelf && targetManageableByRank;
      var toggle = memberNode.querySelector("[data-chat-member-manage-toggle]");
      var panel = memberNode.querySelector("[data-chat-member-manage-panel]");

      memberNode.querySelectorAll("[data-chat-member-role-input], [data-chat-member-role-submit]").forEach(function (control) {
        control.disabled = !controlsEnabled;
      });

      if (toggle) {
        toggle.disabled = !controlsEnabled;
        if (!controlsEnabled) {
          toggle.setAttribute("aria-expanded", "false");
        }
      }

      if (panel && !controlsEnabled) {
        panel.hidden = true;
      }
    });
  }

  function setupMemberListSync(memberList) {
    if (!memberList || memberList.dataset.chatMemberSyncBound === "true") {
      return;
    }

    var chatId = String(memberList.dataset.chatId || "").trim();
    if (!chatId) {
      return;
    }

    memberList.dataset.chatMemberSyncBound = "true";
    setupMemberManageControlsForChat(chatId);
    syncComposerMentionOptionsForChat(chatId);
    syncRoleFormAccessForChat(chatId);

    var observer = new MutationObserver(function (mutationRecords) {
      syncInviteOptionsFromMemberMutations(chatId, mutationRecords);
      setupMemberManageControlsForChat(chatId);
      syncComposerMentionOptionsForChat(chatId);
      syncRoleFormAccessForChat(chatId);
    });
    observer.observe(memberList, { childList: true });
  }

  function setupAllInvitePickers() {
    document.querySelectorAll("[data-chat-invite-form]").forEach(function (form) {
      setupInvitePicker(form);
    });
  }

  function setupAllMemberListSync() {
    document.querySelectorAll("[data-chat-member-list]").forEach(setupMemberListSync);
  }

  namespace.setupAllInvitePickers = setupAllInvitePickers;
  namespace.setupAllMemberListSync = setupAllMemberListSync;
})(window.TurboChatUI = window.TurboChatUI || {});
