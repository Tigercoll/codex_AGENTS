# codex_AGENTS

[中文说明 / Chinese README](./README.zh-CN.md)

Global Codex agent rules plus the local sync toolkit used to mirror and map [`agency-agents`](https://github.com/msitarzewski/agency-agents) expert templates.

## What this repo contains

- `AGENTS.md` - canonical global execution policy
- `agents-ch.md` - synchronized Chinese mirror of the same policy
- `tools/agency-sync/` - cross-platform sync scripts and shared role-profile config

## Repository layout

```text
.
|-- AGENTS.md
|-- agents-ch.md
`-- tools/
    `-- agency-sync/
        |-- agency-agent-profiles.json
        |-- sync-agency-agents.ps1
        |-- sync-agency-agents.sh
        |-- sync-agency-agents
        `-- sync-agency-agents.cmd
```

## What the sync toolkit does

The toolkit pulls role templates from `msitarzewski/agency-agents`, installs them into a fixed local directory, and generates a registry that the main agent must consult before delegating to expert roles.

Default outputs:

- Templates root:
  - Windows: `C:\Users\<you>\.codex\agents\agency-agents\`
  - Linux/macOS: `~/.codex/agents/agency-agents/`
- Machine-readable registry:
  - Windows: `C:\Users\<you>\.codex\agents\agency-agent-map.json`
  - Linux/macOS: `~/.codex/agents/agency-agent-map.json`
- Human-readable index:
  - Windows: `C:\Users\<you>\.codex\agents\agency-agent-map.md`
  - Linux/macOS: `~/.codex/agents/agency-agent-map.md`

## Why this exists

This repo packages the orchestration model used by the global rules:

- Main thread acts as orchestrator
- Planner-first flow for non-simple work
- Expert delegation resolves through a registry first
- Role templates live in a fixed directory
- Controlled second-level delegation is allowed within scope

## Usage

### Windows PowerShell

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\agency-sync\sync-agency-agents.ps1
```

### Windows CMD

```bat
tools\agency-sync\sync-agency-agents.cmd
```

### Linux / macOS

```bash
bash ./tools/agency-sync/sync-agency-agents.sh
```

### Unified launcher (Unix-style shell)

```bash
./tools/agency-sync/sync-agency-agents
```

## Common overrides

All sync entrypoints support the same core override model:

- repo URL
- branch
- source mirror path
- install root
- map JSON path
- map Markdown path
- shared profiles path

Example:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\agency-sync\sync-agency-agents.ps1 `
  -RepoUrl "https://github.com/msitarzewski/agency-agents.git" `
  -Branch "main"
```

```bash
bash ./tools/agency-sync/sync-agency-agents.sh \
  --repo-url "https://github.com/msitarzewski/agency-agents.git" \
  --branch "main"
```

## Notes

- `agency-agent-profiles.json` is the shared source of truth for category selection and auto-route role mappings.
- The PowerShell and shell implementations are intended to stay behaviorally aligned.
- The scripts are versioned here, but operational copies may also be installed under your local `.codex/bin` directory.

## Maintenance rule

If orchestration policy changes, update both:

- `AGENTS.md`
- `agents-ch.md`

in the same change set to avoid drift.
