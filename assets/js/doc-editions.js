// SPDX-FileCopyrightText: © 2026 OpenCHAMI contributors
// SPDX-License-Identifier: MIT

// Native selection avoids dependence on the theme's Bootstrap dropdown handlers.
document.querySelectorAll('select[data-document-edition]').forEach((selector) => {
  selector.addEventListener('change', () => {
    window.location.assign(selector.value);
  });
});
