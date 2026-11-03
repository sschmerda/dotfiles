# Working on this Doom configuration

These instructions apply to this directory and its descendants, including
`lisp/`. They do not apply to other dotfiles in the repository.

## Configuration structure

- `init.el` selects Doom modules and flags.
- `packages.el` declares additional packages and recipe overrides.
- `config.org` is the literate source for the configuration loader and its
  documentation. Doom tangles its Emacs Lisp blocks into `config.el`.
- `config.el` is generated: edit `config.org` instead.
- `lisp/` contains implementation files grouped by package or responsibility.
  Keep implementation there and load it from the appropriate `config.org`
  section using `load!`. Preserve load order, especially macOS setup and the
  Org directory setting before code that depends on them.
- `themes/` contains all local theme entries and shared palette/face helpers in
  one directory, registered by `lisp/themes-config.el`. Theme library symbols
  retain the `landscape-` and `custom-` prefixes; all selectable themes use
  `custom-`, including `custom-landscape-` for Landscape. Isolated checks live in
  `themes/tests/`; retain attribution and upstream terms in `themes/licenses/`.
- `ROADMAP.org` records deferred work. A roadmap entry is not authorization to
  implement it; work on the user's current request.

## Conventions

- Follow established Doom Emacs conventions where practical, including module
  configuration, package loading, keybindings and popup behavior. Prefer Doom's
  existing facilities over custom replacements when they meet the requirement.
- Use `my/` for public interactive commands intended for standalone use through
  `M-x` or global keybindings.
- Use `my--` for internal helpers, hooks, advice and mode-local actions. Internal
  modes and their associated keymaps retain this shared prefix.
- Use `my-` for custom variables. Keep state buffer-local when appropriate.
- Preserve lexical-binding headers. Use Doom's deferred configuration forms,
  such as `after!`, when accessing packages that may not have loaded yet.
- Check existing bindings before assigning keys. Keep command docstrings,
  which-key descriptions and `config.org` documentation consistent.
- Keep configuration portable across systems. Guard platform-specific behavior
  and discover executables and SDK paths rather than hardcoding this machine's
  username, installation paths or environment names.
- Distinguish local and TRAMP paths explicitly. Load local libraries and native
  modules in a local directory context; run remote tooling in its remote context.

## Validation and scope

- Preserve unrelated edits and existing commands. Stage or commit only when
  requested, and inspect the staged diff before committing.
- Prefer changes in this configuration over edits to installed Doom or package
  files under `~/.emacs.d/.local/`.
- Use checks appropriate to the change: Lisp syntax checks and `git diff --check`
  for edits, plus focused runtime verification for behavior changes. Plain
  `emacs -Q` does not provide Doom's configuration macros.
- Prefer isolated test processes, buffers and tmux servers. Avoid overriding
  core Emacs or TRAMP functions globally in the user's running editor. Do not
  initiate real remote connections merely to simulate a remote buffer.
- Clean up only test resources created for the task. Never terminate unrelated
  shells, sessions or processes during verification.
- Delete temporary files created during implementation as soon as they are no
  longer needed, including scratch scripts, fixtures, captures and build
  artifacts. Remove task-created leftovers before finishing; preserve user files.
- A syntax check does not establish visible behavior or performance. State what
  was actually tested and any remaining limitations.
- Explain when module or package changes require `doom sync` and a restart.
  Do not restart the user's active Emacs merely to validate a change.
