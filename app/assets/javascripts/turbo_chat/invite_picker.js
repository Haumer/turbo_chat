(function (namespace) {
  function normalize(value) {
    return String(value || "").trim().toLowerCase();
  }

  function buildOptionData(option) {
    return {
      value: option.value,
      text: option.textContent || "",
      search: normalize((option.dataset && option.dataset.chatInviteSearch) || option.textContent || "")
    };
  }

  function cloneOption(optionData) {
    var option = document.createElement("option");
    option.value = optionData.value;
    option.textContent = optionData.text;
    if (optionData.search) {
      option.dataset.chatInviteSearch = optionData.search;
    }
    return option;
  }

  function selectedOptionData(options, value) {
    var selected = null;
    options.forEach(function (optionData) {
      if (!selected && optionData.value === value) {
        selected = optionData;
      }
    });
    return selected;
  }

  function setupInvitePicker(form) {
    if (!form || form.dataset.chatInviteFilterBound === "true") {
      return;
    }

    var searchInput = form.querySelector("[data-chat-invite-search-input]");
    var select = form.querySelector("[data-chat-invite-select]");
    var emptyHint = form.querySelector("[data-chat-invite-empty]");
    if (!searchInput || !select) {
      return;
    }

    form.dataset.chatInviteFilterBound = "true";

    var promptOption = null;
    var participantOptions = Array.prototype.slice.call(select.options).reduce(function (accumulator, option) {
      var optionData = buildOptionData(option);
      if (!optionData.value && !promptOption) {
        promptOption = optionData;
        return accumulator;
      }

      accumulator.push(optionData);
      return accumulator;
    }, []);

    function applyFilter() {
      var query = normalize(searchInput.value);
      var previouslySelectedValue = select.value;
      var filteredOptions = participantOptions.filter(function (optionData) {
        if (!query) {
          return true;
        }

        return optionData.search.indexOf(query) !== -1;
      });

      if (previouslySelectedValue) {
        var selected = selectedOptionData(participantOptions, previouslySelectedValue);
        var selectedStillVisible = selectedOptionData(filteredOptions, previouslySelectedValue);
        if (selected && !selectedStillVisible) {
          filteredOptions.unshift(selected);
        }
      }

      select.innerHTML = "";
      if (promptOption) {
        select.appendChild(cloneOption(promptOption));
      }

      filteredOptions.forEach(function (optionData) {
        var option = cloneOption(optionData);
        if (optionData.value === previouslySelectedValue) {
          option.selected = true;
        }
        select.appendChild(option);
      });

      if (emptyHint) {
        emptyHint.hidden = filteredOptions.length > 0 || !query;
      }
    }

    searchInput.addEventListener("input", applyFilter);
    searchInput.addEventListener("search", applyFilter);

    form.addEventListener("reset", function () {
      setTimeout(function () {
        searchInput.value = "";
        applyFilter();
      }, 0);
    });

    applyFilter();
  }

  function setupAllInvitePickers() {
    document.querySelectorAll("[data-chat-invite-form]").forEach(setupInvitePicker);
  }

  namespace.setupAllInvitePickers = setupAllInvitePickers;
})(window.TurboChatUI = window.TurboChatUI || {});
