(function () {
  "use strict";
  var namespace = (window.TurboChatUI = window.TurboChatUI || {});
  var setupInvitePicker = namespace.setupInvitePicker;

  function normalize(value) {
    return String(value || "").trim().toLowerCase();
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
    var canGrant = shell.dataset.chatCanGrantMemberPermissions === "true";
    var canMute = shell.dataset.chatCanMuteMember === "true";
    var canBan = shell.dataset.chatCanBanMember === "true";
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
      var rolePanel = memberNode.querySelector("[data-chat-member-manage-panel]");
      var moderationPanel = memberNode.querySelector("[data-chat-member-moderation-panel]");
      var actionsDiv = memberNode.querySelector(".chat-member-actions");

      var roleFormVisible = canGrant && controlsEnabled;
      var moderationVisible = (canMute || canBan) && controlsEnabled;
      var anyActionVisible = roleFormVisible || moderationVisible;

      if (isSelf) {
        if (toggle) toggle.hidden = true;
        if (actionsDiv) actionsDiv.style.display = "none";
        return;
      }

      if (actionsDiv) actionsDiv.style.display = "";

      memberNode.querySelectorAll("[data-chat-member-role-input], [data-chat-member-role-submit]").forEach(function (control) {
        control.disabled = !roleFormVisible;
      });

      if (moderationPanel) {
        moderationPanel.hidden = !moderationVisible;
        var muteBtn = moderationPanel.querySelector("[data-chat-member-mute-action]");
        var banBtn = moderationPanel.querySelector("[data-chat-member-ban-action]");
        if (muteBtn) muteBtn.disabled = !(canMute && controlsEnabled);
        if (banBtn) banBtn.disabled = !(canBan && controlsEnabled);
      }

      if (toggle) {
        toggle.hidden = !anyActionVisible;
        toggle.disabled = !anyActionVisible;
        if (!anyActionVisible) {
          toggle.setAttribute("aria-expanded", "false");
        }
      }

      if (rolePanel && !roleFormVisible) {
        rolePanel.hidden = true;
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

  function setupAllMemberListSync() {
    document.querySelectorAll("[data-chat-member-list]").forEach(setupMemberListSync);
  }

  namespace.setupAllMemberListSync = setupAllMemberListSync;
})();
