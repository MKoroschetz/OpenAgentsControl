<!-- Context: project-intelligence/nav | Priority: high | Version: 1.2 | Updated: 2026-08-15 -->

# Project Intelligence

> Start here for quick project understanding. These files bridge business and technical domains.

## Structure

```
.opencode/context/project-intelligence/
├── navigation.md              # This file - quick overview
├── business-domain.md         # Business context and problem statement
├── technical-domain.md        # Stack, architecture, technical decisions
├── business-tech-bridge.md    # How business needs map to solutions
├── decisions-log.md           # Major decisions with rationale
├── system-reference.md        # Living infra reference: versions, EOL, seasons, Docker sync
└── living-notes.md            # Active issues, debt, open questions
```

## Quick Routes

| What You Need | File | Description |
|---------------|------|-------------|
| Understand the "why" | `business-domain.md` | Problem, users, value proposition |
| Understand the "how" | `technical-domain.md` | Stack, architecture, integrations |
| See the connection | `business-tech-bridge.md` | Business → technical mapping |
| Know the context | `decisions-log.md` | Why decisions were made |
| Current state | `living-notes.md` | Active issues and open questions |
| **Infra versions/EOL/seasons** | `system-reference.md` | **Living reference: versions, EOL calendar, seasonal windows, Docker sync** |
| All of the above | Read all files in order | Full project intelligence |

## Usage

**New Team Member / Agent**:
1. Start with `navigation.md` (this file)
2. Read all files in order for complete understanding
3. Follow onboarding checklist in each file

**Quick Reference**:
- Business focus → `business-domain.md`
- Technical focus → `technical-domain.md`
- Decision context → `decisions-log.md`

## Tooling / Agents at a Glance

> Who handles what in **this** project. Generic agent capabilities live in `docs/agents/` — this table only maps the agent roster to aspaDB workflows.

| Workflow | Agent | Path |
|----------|-------|------|
| General coordination, questions, planning | OpenAgent | `.opencode/agent/core/openagent.md` |
| Complex coding, architecture, multi-file refactoring | OpenCoder | `.opencode/agent/core/opencoder.md` |
| SQL analysis, querying, reporting (incl. `reporter`-role work) | Data Analyst | `.opencode/agent/data/data-analyst.md` |
| Documentation and technical writing | Technical Writer | `.opencode/agent/content/technical-writer.md` |
| Task breakdown and tracking | TaskManager | `.opencode/agent/subagents/core/` |
| Code review / security / QA | CodeReviewer | `.opencode/agent/subagents/code/` |
| Build and type-check validation | BuildAgent | `.opencode/agent/subagents/code/` |

**Delegation pattern**: OpenAgent/OpenCoder handle most work directly and delegate to subagents (TaskManager, CoderAgent, TestEngineer, CodeReviewer, BuildAgent) for specialized steps. Infra/maintenance work (backups, PG upgrade) is runbook-driven — see `system-reference.md` and `docs/CORE-PLATFORM-UPGRADE.md`.

**Full agent docs**: `docs/agents/` (per-agent guides) and `docs/features/agent-system-blueprint.md` (architecture).

## Integration

This folder is referenced from:
- `.opencode/context/core/standards/project-intelligence.md` (standards and patterns)
- `.opencode/context/core/system/context-guide.md` (context loading)

See `.opencode/context/core/context-system.md` for the broader context architecture.

## Maintenance

Keep this folder current:
- Update when business direction changes
- Document decisions as they're made
- Review `living-notes.md` regularly
- Archive resolved items from decisions-log.md

**Management Guide**: See `.opencode/context/core/standards/project-intelligence-management.md` for complete lifecycle management including:
- How to update, add, and remove files
- How to create new subfolders
- Version tracking and frontmatter standards
- Quality checklists and anti-patterns
- Governance and ownership

See `.opencode/context/core/standards/project-intelligence.md` for the standard itself.
