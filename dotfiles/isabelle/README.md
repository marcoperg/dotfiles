# Isabelle development

This is an opt-in, separate **Isabelle2025-2-vsce** installation. The existing
`/Applications/Isabelle2026.app` is unchanged. No OpenCode frontend, provider,
model, authentication, or CLI configuration is changed.

Managed upstream checkouts live under `~/.local/share/isabelle-dev/`, not
`~/clip/Systems`. Configuration, pins, patches, and tests remain in dotfiles.

## Compatibility and pins

The checked upstream overlap is Isabelle2025-2: Fleury's latest release-specific
LSP branch is `Isabelle2025-2-vsce`; PIDE MCP has an `Isabelle2025-2` release
branch. MCP `main` targets a different development revision. Using the current
2026 app with these clients was therefore not assumed compatible.

| Source | Pinned revision |
|---|---|
| `m-fleury/isabelle-emacs`, including LSP client and server | `db6537b08703478050cfb5046d677c1bf96859f9` |
| `m-fleury/isar-mode` | `354b881f6a9e1b570a44c5819852a6f1cb2a2ebf` |
| `kappelmann/isabelle-pide-mcp` | `cd672ac6e31befcf4750835c43c29fa32b794152` |
| `emacs-lsp/lsp-mode` | `c6e3660d32813b02ba3de60045de734e680bbcc7` |

Tested with Emacs 30.2 and OpenCode V2 2.2.5. The lsp-mode pin corresponds to
the already-installed `20251221.1949` package; the separate source checkout
keeps the Isabelle client pinned without upgrading unrelated Emacs packages.
Existing package.el dependencies are retained. On a new machine, install them
with `M-x package-install RET lsp-mode` when first using Isabelle; this optional
integration does not install packages or check external paths at Emacs startup.

`pins.json` and the fork's `Admin/components/main` pin the source and components
(including JDK 21.0.9, Scala 3.3.4, and Poly/ML 5.9.2). Identically versioned
components are reused by symlink from the existing app when available; other
components are installed under `~/.isabelle/contrib`. The existing app is not
modified. Removing that app later requires reinstalling any shared components.

## Why source fixes are necessary

The architecture is reasonable, but the upstream Emacs sample is not a clean,
current drop-in configuration: it uses an old package-manager example and
Isabelle2020 paths. Do not copy it wholesale.

`isar-mode.patch` fixes the problems at their source:

- no replacement of Emacs's shared Quail translator or macOS font functions;
- a dedicated Quail rule table and copied translation keymap;
- no automatic input-method activation, or deactivation of another method;
- symbol conversion runs **before** saving, using literal replacements;
- no duplicate major-mode hook execution or redundant local-variable reset.

`lsp-isar.patch` makes the starter an interactive command for shortcuts/menus,
retains `C-x s`, uses local `C-c C-h` for Sledgehammer,
disables obsolete global TRAMP hacks, removes hard-coded personal library
paths, and makes caret tracking buffer-local. Synchronous output rendering
avoids the otherwise unconditional session-async dependency and extra Emacs
process. No new package manager or Emacs framework is introduced.

**Known limitation:** the server emits dedicated `PIDE/sledgehammer_output`
and `PIDE/sledgehammer_status` notifications that this Emacs client does not
handle. Standard proof-state output and diagnostics work; richer Sledgehammer
UI integration has not been verified. These notifications may produce warnings.
The setup does not claim full parity with Isabelle/jEdit.

## Setup and verification

### What must exist outside dotfiles

On another machine, install **Emacs 30.2** (the tested version), **Python 3.8+**,
**Git**, and **curl** first. A complete dotfiles checkout is required, not just
a copied `init.el`. Install the Lisp dependencies using
`M-x package-install RET lsp-mode`. Do not install a separate Java, Scala, or Poly/ML:
the pinned Isabelle component manifest selects and downloads those versions.

The remaining external state is reproducible, rather than hand-maintained:

| Location | Contents | How created |
|---|---|---|
| `~/.local/share/isabelle-dev/` | Four pinned upstream checkouts, patched sources, generated Scala jars | `setup.py --install` |
| `~/.isabelle/contrib/` | Pinned runtime components | Same installer |
| `~/.isabelle/Isabelle2025-2-vsce/etc/` | Version-specific settings and MCP registration | Same installer; settings template is tracked here |
| `~/.isabelle/Isabelle2025-2-vsce/heaps/` | Platform-specific compiled Pure/HOL images | First `isabelle-dev build` |
| `~/.emacs.d/elpa/` | Existing package.el dependencies | `M-x package-install RET lsp-mode` |

No additional hand-written code or secret configuration is required outside
dotfiles. The source changes in the external checkouts are reproduced from the
two tracked patch files. Do not copy heap caches or old absolute component
registrations between machines; run the installer and build locally instead.

Emacs autoloads the integration only when opening a `.thy` file or running
`M-x isar-mode`. Missing sources then produce an error with the install command;
missing Lisp dependencies name the package-install command. Unrelated Emacs
startup stays quiet. The CLI/MCP launcher likewise reports a
missing prover or MCP registration with the same recovery command, rather than
a Python traceback. `setup.py --verify` reports a missing checkout explicitly.

From `~/dotfiles`:

```sh
python3 dotfiles/isabelle/setup.py --install
python3 dotfiles/isabelle/setup.py --verify
dotfiles/bin/isabelle-dev build
```

Installation clones missing sources at the exact pins and applies the tracked
patches. It refuses to switch an existing checkout to a different revision.
Changed version-specific Isabelle settings are backed up before replacement.
`--verify` only checks source revisions and patches; it is not a proof check.

The first installation and HOL build can take substantial time and disk space.
Only the headless server components are installed, not a second VSCode app.
macOS may require GUI approval for downloaded executables; do not disable
Gatekeeper globally. No GUI approval was needed for the tested CLI processes.

## Use

Opening a `.thy` file enables `isar-mode` and starts its LSP workspace. Accept
the appropriate project root if lsp-mode asks. Offline editing is available
with `my/isabelle-auto-start` set to nil before opening the theory.

The **Isabelle** menu exposes proof commands, symbols, input-method selection,
keybinding help, and settings. In terminal Emacs, use `F10` to access menus.

| Command/key in a theory | Purpose |
|---|---|
| `C-c C-l` | Start the LSP prover manually |
| `C-c C-o` | Display live proof state |
| `C-c C-k` | Independently build the profile's smoke session |
| `C-c C-h` | Upstream Sledgehammer interface (limitations above) |
| `C-x s` | Standard `save-some-buffers`, unchanged |
| `C-x RET C-\` | Select an input method, e.g. `spanish-prefix` |
| `C-\` | Toggle the selected input method |

No input method is forced. Optionally select **Unicode tokens** in an Isabelle
buffer to enter shortcuts such as `\times`; they insert encoded Isabelle
symbols. Symbol display stays enabled independently of input. Saving converts
Unicode symbols to Isabelle's encoded source form before the disk write.

The setup neither enables nor disables Evil, and does not override its initial
state. Your existing Evil shortcuts and state preferences apply to theories.

`profile.json` is the shared authority for the prover, base logic (`HOL`), and
session directories. The included session is `Emacs_Isabelle_Smoke`, under
`~/dotfiles/tests/isabelle`. After changing the profile, reload `my-isabelle.el`
and restart the Emacs LSP workspace. Start new MCP sessions with matching options.

```sh
# Independent smoke check; always passes quick_and_dirty=false.
~/dotfiles/dotfiles/bin/isabelle-dev build
# Independent check for a real project's sessions.
~/dotfiles/dotfiles/bin/isabelle-dev check -D /path/to/project
# JSON arguments for the MCP start_session tool.
~/dotfiles/dotfiles/bin/isabelle-dev mcp-session-options
```

OpenCode's existing V2 config adds only `mcp.servers.isabelle` and two skill
search paths. Matching upstream skills are used directly from the pinned MCP
checkout; local `isabelle-environment` guidance explains this profile.
The global MCP server starts **without a prover session** to avoid loading HOL
in every unrelated OpenCode project. The agent starts one on demand.

**LSP and MCP have independent prover sessions.** They exchange saved files,
not unsaved editor state. Auto Revert reloads unmodified theory buffers;
unsaved edits are protected. Do not let an agent and a human edit the same
theory concurrently without coordinating. An interactive result is not a
substitute for the independent build.

## Tested

- `emacs --batch -Q -l tests/test_isabelle_lazy.el -f ert-run-tests-batch-and-exit`:
  startup leaves Isabelle unloaded; missing dependencies error only on mode
  entry; retrying after installation successfully loads the theory mode.
- `emacs --batch -Q -l tests/test_isabelle.el -f ert-run-tests-batch-and-exit`:
  global Quail/process functions preserved, Spanish translation and keymaps
  preserved before/after theory mode, optional Isabelle input, standard keys,
  `\<times>` rendering, one-save disk/buffer equality, native file-notification
  delivery, external reload safety, the mode-local menu, and actionable missing
  installation errors: **8 tests passed**.
- `emacs --batch -Q -l tests/test_isabelle_lsp.el`: real LSP initialization,
  proof-state feedback, deliberately unknown proof method producing a diagnostic,
  and correction clearing the error diagnostics.
- Agent-side native MCP calls: session startup, proof-state queries on `Smoke`,
  scratch theory editing, a failed proof of `False`, and correction to a clean
  proof of `True` (0 errors, bad commands, failures, or pending commands).
- `isabelle-dev build -v`: fresh Pure/HOL and smoke-session build completed with
  `quick_and_dirty=false`; no skipped proofs in the smoke theory.
- 25 downloaded component archives matched the pinned upstream SHA1 manifest.

The LSP tests exercise a real Emacs process and server, but not manual GUI
layout, clicking, mouse interaction, or the Sledgehammer UI. The interactive
Emacs configuration has been loaded without reloading unrelated init settings.

## Maintenance

- Keep paths, base logic, and session directories in `profile.json`; keep exact
  upstream revisions in `pins.json`. Do not add machine-specific paths to init.
- The external checkouts are installation artifacts, not the authoritative
  location for custom code. Preserve any source fix in the corresponding tracked
  `.patch` file, and run `setup.py --verify` to check the installed revisions and
  patches. Test both forward patch application and the resulting source changes
  when updating a patch; never reset a checkout containing other local work.
  The local `.gitattributes` exempts patch artifacts from whitespace checks:
  their context lines must retain upstream whitespace for `git apply`.
- Treat the Isabelle fork, lsp-isar, isar-mode, and PIDE MCP as a compatible set.
  To update, use fresh checkout directories in the profile rather than replacing
  a working installation. Recheck the upstream version overlap, rebase the
  patches, and run all three Emacs test commands above plus an independent build.
- On a release change, also update the version-specific user directory in
  `setup.py` and `isabelle-dev`, and review the template in `settings`. Do not
  copy absolute component registrations or heap caches from another machine.
- Keep dependency checks in the mode loader or launcher, not eager init.
  Preserve the lazy-startup test so unused Isabelle support stays silent.
- After configuration changes, reload only `my-isabelle.el`, not the whole init.
  Restart affected LSP/MCP sessions when changing their profile or server code.
  OpenCode watches its config; no frontend/authentication changes are necessary.

## Rollback

The pre-change init/config/reading-mode test were copied to
`~/.dotfiles.backups/isabelle-20261104-144801/`, preserving pre-existing local
mail and Ciao edits. Do not reset or restore whole files blindly if newer edits
have been made since that backup.

1. Remove the small Isabelle module-loading block from `dotfiles/emacs/init.el`
   (or restore just its previous Isabelle block from the backup).
2. Remove only `mcp.servers.isabelle` and the two Isabelle skill paths from
   `dotfiles/opencode-v2/opencode.jsonc`. Leave Ciao and all other settings alone.
3. Restart Emacs to remove loaded Isabelle definitions; OpenCode reloads its
   configuration automatically. Stop any active Isabelle sessions first.
4. The extra checkouts and `~/.isabelle/Isabelle2025-2-vsce` can be retained
   unused. If removing them, first unregister MCP using this pinned prover's
   `components -x` command. Do not remove shared component files or the 2026 app.

Reversing either tracked patch with `git apply --reverse` in its corresponding
source checkout is safe only after checking for additional local source edits;
never run the original buggy integration while it is still enabled in Emacs.
