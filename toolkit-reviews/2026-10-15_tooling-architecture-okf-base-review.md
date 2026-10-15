# Toolkit review: tooling architecture, OKF and BASE

Date: 2026-10-15

## Scope and basis

Reviewed:
- the 14 PowerShell scripts in `.toolkit/scripts/`
- the three new Python-based skills (`diagram-export`, `email-entwurf`, `fill-template`)
- `AGENTS.md.tmpl` and the mem-index templates
- the OKF spec (https://okf.md/spec, read in full)
- the BASE README (https://github.com/ai-swiss/base). I did not read its detailed standard, CLI or MCP docs.

Not checked: which PS scripts depend on Windows-only APIs (e.g. Office COM). Tool and standard references not fetched live come from background knowledge and should be verified before relying on them.

## Requirements as clarified

| Topic | Answer |
|---|---|
| Runtime | Assume Python. If the user rejects it, agree on an alternative runtime with the user. |
| Platforms | Priority 1 Windows, 2 Linux, 3 macOS. Not all needed immediately. |
| Users | Mainly technical. Skills must be able to use the same CLI tools. |
| mem-index | Key knowledge DB of every project. Collaborative via git. |
| Exports | Transient snapshots (wiki, flat files, PDF). Never written back to the project. |
| Privacy | Decided per project and per client. |

## 1. Tooling architecture

### Assessment

The new Python skills use a better pattern than the PS scripts:

1. The agent writes a declarative spec (`spec.json`, `ops.json`).
2. A deterministic script builds the artefact.
3. A validator checks it (`validate_drawio.py`).
4. The agent fixes problems and rebuilds.

This is the strongest current pattern for reliable agent tooling. Interactive PS tools (the `search-index.ps1` REPL, the wizards) work for humans but not for agents.

### Recommendations

- **One CLI with a stable contract.** A single `bender <verb>` entry point, Python core. Each command should:
  - run without prompts
  - support `--json` output and `--dry-run`
  - use fixed exit codes (`export_drawio.py` already uses 2 = missing dependency)
  - report validator diagnostics as machine-readable codes and locations
- **Thin launchers.** `bender.ps1` and a `bender` shell script locate Python and run the CLI. If Python is missing, ask the user which runtime to use, store it in `mandate.config.json`, and provide `bender doctor` to check the setup. The JSON/exit-code contract keeps the runtime swappable.
- **Zero-setup dependencies.** PEP 723 inline script metadata with `uv run` instead of `requirements.txt.tmpl` plus manual pip.
- **Skills call the same commands.** Skills invoke `bender ...` instead of `python .agents/skills/.../x.py`. A small per-tool manifest (name, JSON Schema for inputs, read-only or writes, exit codes) could generate CLI help and SKILL.md snippets, and makes a later MCP wrapper cheap.
- **Port agent-facing tools first.** `log add`, `lint`, `search --json`, `export`, `status`, docs-to-text. Keep interactive wizards in PS where still useful. Agents currently append to `log.md` by hand in a strict format, which is brittle; `bender log add --type query ...` removes that.
- **Search at the right size.** SQLite FTS5 (Python stdlib) gives BM25 ranking plus frontmatter filters. Keep the index local, derived and gitignored. Embeddings/vector RAG are overkill for hundreds of nodes and usually send client data to a remote embedding API, which conflicts with per-client privacy.
- **Tests.** pytest golden-file tests against a small fixture mem-index.
- **Doc conversion.** Evaluate local tools (e.g. MarkItDown, Docling) in place of any Windows-only conversion.

**Not first:** an MCP server. For local scripts, CLI plus skill costs less context. Add MCP only for harnesses without shell access.

## 2. OKF (Open Knowledge Format)

**Verdict: borrow ideas, don't chase conformance yet.** OKF is a v0.1 draft aimed at data catalogs; real-world adoption is unverified. The mem-index is already close to it (markdown tree, index, `log.md`, cross-links). Conformance needs only frontmatter with a non-empty `type` on every non-reserved `.md` file.

### Conflicts with the current mem-index

| OKF | bender today |
|---|---|
| Reserved `log.md`: date headings, newest first | Append-only at the bottom, `## [date] typ \| ...` |
| Standard markdown links | `[[wikilinks]]` |
| One concept per file | Aggregate nodes (`03_Anforderungen.md`) |

### Worth adopting

1. **Frontmatter on every node** (`type`, `description`, `tags`, `timestamp`), plus own keys such as `status`, `sources`, `sensitivity`. Enables lint, generated indexes, filtered exports and staleness checks. Highest value for lowest cost.
2. **A `# Citations` section** for provenance. Fits the "nothing invented" rule; the fill-template `.quellen.md` report is already a version of this.
3. **Tolerance for broken links.** Lint should only warn.
4. **Structured data as source of truth, generated markdown views.** Already done with `09_Master-Schedule.json`. Extend to requirements, open questions and action items. Also reduces git merge conflicts.

### Exports are read-only: make it a mechanism

Today this is only a convention.
- Stamp every export with `generated: true`, the source commit and a timestamp.
- Make `ingest` and `lint` refuse files carrying that stamp.
- Keep exports outside the paths the agent is allowed to read.

## 3. BASE

**Verdict: useful concepts, don't integrate.** BASE is young, French-authoritative, a self-declared standard with no third-party ratification or security review, and states it has no published measurements. Its CLI and Studio add a Node dependency. Its agent/process/sources model overlaps with `AGENTS.md` and `SKILL.md`, which Copilot and Codex already read natively.

### Ideas worth taking

- **Instruction versus mechanism.** The "strictly enforced" file-access rule in `AGENTS.md` is only an instruction, and skills lift it by instruction. Enforce it where it matters through bender tools that read via an allowlist. Direct file reads still bypass this; hard guarantees also need harness-level permissions or hooks (check what each harness supports).
- **Two-stage mediated writes.** Tools produce a plan or diff and apply only with `--apply`/`--yes`. Use for ingest, mem-index edits and `log add`, so prose "Gates" become real ones.
- **Declarative sources and write targets per skill.** `reads:` and `writes:` in SKILL.md frontmatter; lint checks skills against the rules instead of relying on prose "Quellen-Whitelist" text.
- **Sensitivity classes per project.** A per-project policy (in `mandate.config.json` or node frontmatter) classifies paths and nodes; tools filter on it. Suits client-by-client privacy. Only protects paths going through the tools.
- **Scenario replay.** A demo mandate with expected answers, replayed across models. Skills currently have no regression testing.

## 4. Suggested order

1. CLI contract, launcher and `doctor`.
2. Node frontmatter, `bender lint`, `bender log add`, generated index.
3. Port agent-facing PS tools to Python, keeping PS shims.
4. Plan/apply writes and read-only stamps on exports.
5. Per-project sensitivity policy.
6. Skill scenario tests.

**Not now:** full OKF conformance, BASE integration, MCP, embeddings.

## 5. Open decisions for you

- Is `bender` as a single CLI name and entry point acceptable, or should tools stay separate scripts?
- Frontmatter schema: which `type` values and custom keys fit a mandate mem-index?
- Keep `[[wikilinks]]` and the log format, or accept OKF-style changes for compatibility?
- Which PS scripts are worth keeping as PS-only (wizards) versus porting?
- Which harnesses (Copilot, Codex, others) must be supported, and what permission/hook controls do they offer?

## Next possible steps

- Sketch the CLI contract (verbs, flags, exit codes, JSON shapes).
- Draft the node frontmatter schema and a `lint` ruleset.
