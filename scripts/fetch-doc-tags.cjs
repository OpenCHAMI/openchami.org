// SPDX-FileCopyrightText: © 2026 OpenCHAMI contributors
// SPDX-License-Identifier: MIT
'use strict';
const { execFileSync } = require('node:child_process');
const path = require('node:path');
const cwd = path.resolve(__dirname, '..');
const shallow = execFileSync('git', ['rev-parse', '--is-shallow-repository'], { cwd, encoding: 'utf8' }).trim() === 'true';
// Mirror origin's tags so deleted and corrected tags reach existing clones, and fetch main so
// generation can tell which tags are published, even from single-branch hosted checkouts.
execFileSync('git', ['fetch', ...(shallow ? ['--unshallow'] : []), '--prune', 'origin', '+refs/heads/main:refs/remotes/origin/main', '+refs/tags/*:refs/tags/*'], { cwd, stdio: 'inherit' });
