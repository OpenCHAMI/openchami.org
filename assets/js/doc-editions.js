// SPDX-FileCopyrightText: © 2026 OpenCHAMI contributors
// SPDX-License-Identifier: MIT

// Native selection avoids dependence on the theme's Bootstrap dropdown handlers.
document.querySelectorAll('select[data-document-edition]').forEach((selector) => {
  selector.addEventListener('change', () => {
    // Editions share heading IDs, so keep the reader's place when the target has it.
    window.location.assign(selector.value + window.location.hash);
  });

  // Back and Forward can restore the abandoned choice, and re-picking it fires no change event.
  window.addEventListener('pageshow', () => {
    Array.from(selector.options).forEach((option) => {
      option.selected = option.defaultSelected;
    });
  });
});
