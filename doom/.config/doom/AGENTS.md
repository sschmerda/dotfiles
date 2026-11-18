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
- `lisp/languages/` groups programming-language settings, including mode options,
  environment integration, LSP and formatter selection. Add files when a language
  needs custom settings; shared formatting behavior stays in `lisp/format-config.el`.
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
- Every custom interactive feature must provide discoverable, context-specific
  help explaining its commands, keybindings and relevant options. Use a local
  `C-c C-h` binding by default, or `C-h` in a dedicated interface where appropriate.
  Preserve Emacs's standard help bindings in ordinary buffers, and keep the help
  text and documented bindings synchronized with the implementation.
- Keep configuration portable across systems. Guard platform-specific behavior
  and discover executables and SDK paths rather than hardcoding this machine's
  username, installation paths or environment names.
- Distinguish local and TRAMP paths explicitly. Load local libraries and native
  modules in a local directory context; run remote tooling in its remote context.

## Language support contract

- Required primary programming-language targets: **Python, R, Rust, Emacs Lisp,
  Go, C, C++, and Java**. Java is a support target even while its Doom module is
  disabled; this is not permission to enable it automatically.
- Also preserve the enabled Lua and shell workflows. Track JavaScript/TypeScript
  as planned targets while their modules/tooling are unavailable. Org, Markdown,
  LaTeX and data files retain their existing non-programming workflows.
- Every new language-facing feature must be checked against this target set.
  Prefer one shared implementation driven by provider capabilities. Add language
  adapters only for demonstrated differences; do not silently assume Python
  syntax, namespace rules, server behavior or environment conventions.
- Apply shared changes (documentation, signature help, search, themes, navigation,
  Git integration and layout) to every target where they are meaningful. For an
  intrinsically language-specific facility, such as Conda activation, explicitly
  mark other targets not applicable rather than inventing artificial equivalents.
  Emacs Lisp normally uses native Help/Eldoc/Xref instead of an invented LSP server.
- Preserve text and source buffers. Missing parser/server metadata must have a
  readable fallback or an explicit unsupported result. Never guess an import,
  discard a qualifier to choose an unrelated symbol, run example code, edit the
  originating document as a lookup trick, or start another LSP server for Help.
- Test pure behavior for each applicable adapter and real installed tooling for
  changed server interactions. Missing executables/grammars are recorded as
  unverified, not passed. Update the evidence table below when support changes;
  do not call all Doom functionality verified merely because one fixture passes.
- Local protocol tests do not establish TRAMP support, a functioning REPL/debugger,
  formatter availability, or complete in-editor integration. Verify those layers
  separately when changing them. Do not install/enable modules or contact remote
  hosts merely to fill gaps in this table without task authorization.

### Documentation reading view (2026-11-18)

Documentation displays the provider's text and explicit links, with syntax
highlighting, popup/centered presentation and cached Help history. It does not
resolve arbitrary names in prose/examples, create synthetic source documents,
scan source for matching identifiers or search workspace symbols from Help.
The source action requests a definition only at the original saved LSP source
position. Missing/unreadable sources fail explicitly. Native Emacs Lisp Help
retains its native buttons and navigation.

| Target | Shared behavior and verification boundary |
| --- | --- |
| Python | Shared reading view; parser-backed example highlighting has isolated tests, including prompts and long Markdown fences. No example-name lookup. |
| R, Rust, Go, C, C++, Java | Same provider-driven reading view and original-position source action; no language-specific resolution adapters. Isolated protocol/UI tests do not establish complete live server integration for each language. Java remains a target without enabling its module. |
| Emacs Lisp | Native Doom/Helpful/Eldoc/Xref; native Help behavior is covered by isolated window tests. No invented LSP server. |
| Lua / shell | Preserve enabled workflows using the same reading view. Live server integration remains unverified. |
| JavaScript / TypeScript | Planned targets; no live integration claim while tooling/modules are unavailable. |

Run the focused tests from the repository root:

```sh
emacs -Q --batch -l doom/.config/doom/lisp/tests/documentation-tests.el -f ert-run-tests-batch-and-exit
emacs -Q --batch -l doom/.config/doom/lisp/tests/signature-tests.el -f ert-run-tests-batch-and-exit
```

Package paths/grammar availability may differ across hosts; report skips and
missing dependencies explicitly. Add the feature's relevant formatter, environment,
search or theme tests rather than treating these documentation tests as universal.

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
