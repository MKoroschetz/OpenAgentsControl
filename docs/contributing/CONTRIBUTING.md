# Contributing to OpenAgents Control

Thank you for your interest in contributing! This guide will help you add new components to the registry and understand the repository structure.

## 📚 Documentation

- **[Development Guide](DEVELOPMENT.md)** - Complete guide for developing on this repo (agents, commands, tools, testing)
- **[Agent Creation System](../../.opencode/command/openagents/new-agents/README.md)** - ⭐ NEW: Research-backed agent creation with templates
- **[Code of Conduct](CODE_OF_CONDUCT.md)** - Community guidelines
- **[Adding Evaluators](ADDING_EVALUATOR.md)** - How to add new test evaluators

## Repository Structure

```
opencode-agents/
├── .opencode/
│   ├── agent/              # Agents (category-based)
│   │   ├── core/
│   │   │   ├── openagent.md        # Universal orchestrator
│   │   │   └── opencoder.md        # Development specialist
│   │   ├── meta/
│   │   │   └── system-builder.md   # System architect
│   │   ├── development/
│   │   │   ├── frontend-specialist.md
│   │   │   └── backend-specialist.md
│   │   ├── content/
│   │   │   └── copywriter.md
│   │   └── subagents/          # Specialized subagents
│   ├── prompts/            # Prompt library (variants and experiments)
│   │   ├── core/
│   │   │   ├── openagent/
│   │   │   │   ├── gpt.md
│   │   │   │   └── llama.md
│   │   │   └── opencoder/
│   │   │       └── gpt.md
│   │   └── development/
│   │       └── frontend-specialist/
│   │           └── gpt.md
│   ├── command/            # Slash commands
│   ├── tool/               # Utility tools
│   ├── plugin/             # Integrations
│   └── context/            # Context files
├── evals/
│   ├── agents/             # Agent test suites
│   ├── framework/          # Testing framework
│   └── results/            # Test results
├── scripts/
│   ├── prompts/            # Prompt management
│   └── tests/              # Test utilities
└── docs/
    ├── agents/             # Agent documentation
    ├── contributing/       # Contribution guides
    └── guides/             # User guides
```

> **Note**: Agent files now use category-based organization. Core agents are in `core/`, 
> development specialists in `development/`, etc. When referencing agents, use the 
> category prefix: `core/openagent`, `development/frontend-specialist`.

### Key Directories

- **`.opencode/agent/core/`** - Core system agents (openagent.md, opencoder.md)
- **`.opencode/agent/meta/`** - Meta-level agents (system-builder.md)
- **`.opencode/agent/development/`** - Development specialist agents
- **`.opencode/agent/content/`** - Content creation agents
- **`.opencode/agent/subagents/`** - Specialized subagents
- **`.opencode/prompts/`** - Library of prompt variants for different models (category-based)
- **`evals/`** - Testing framework and test suites
- **`scripts/`** - Automation and utility scripts
- **`docs/`** - Documentation and guides

## Quick Start

1. Fork the repository
2. Create a new branch for your feature
3. Add your component
4. Test it works
5. Submit a pull request

## Adding New Components

### Component Types

- **Agents** (`.opencode/agent/*.md`) - Main AI agents
- **Subagents** (`.opencode/agent/subagents/*.md`) - Specialized helpers
- **Commands** (`.opencode/command/*.md`) - Slash commands
- **Tools** (`.opencode/tool/*/index.ts`) - Utility tools
- **Plugins** (`.opencode/plugin/*.ts`) - Integrations
- **Contexts** (`.opencode/context/**/*.md`) - Context files

### Component Structure

#### For Markdown Files (Agents, Commands, Contexts)

All markdown files should include YAML frontmatter:

```markdown
---
id: devops-specialist
name: DevOps Specialist
description: "Brief description of what this does"
category: development
type: standard
version: 1.0.0
author: community
mode: primary  # For agents only
temperature: 0.1  # Optional - for agents only
tools:  # For agents only
  read: true
  edit: true
  write: true
permissions:  # Optional
  bash:
    "*": "deny"
---

# Component Name

Your component content here...
```

**Required fields:**
- `description` - Brief description (all components)

**Agent-specific fields:**
- `mode` - Agent mode (primary, secondary, etc.)
- `model` - AI model to use
- `temperature` - Temperature setting
- `tools` - Available tools
- `permissions` - Security permissions

#### For TypeScript Files (Tools, Plugins)

Include JSDoc comments at the top:

```typescript
/**
 * Tool Name
 * 
 * Brief description of what this tool does
 */

export function myTool() {
  // Implementation
}
```

### File Naming Conventions

- **kebab-case** for file names: `my-new-agent.md`
- **PascalCase** for TypeScript types/interfaces
- **camelCase** for variables and functions

### Adding Your Component

1. **Create the component file** in the appropriate directory:
   ```bash
   # Example: Adding a new agent
   touch .opencode/agent/my-new-agent.md
   ```

2. **Add frontmatter and content** following the structure above

3. **Test your component**:
   ```bash
   # Validate structure
   ./scripts/registry/validate-component.sh
   ```

4. **Update the registry** (automatic on merge to main):
   ```bash
   # Manual update (optional)
   ./scripts/registry/register-component.sh
   ```

## Component Categories

When adding components, they're automatically categorized:

- **core** - Essential components included in minimal installs
- **extended** - Additional features for developer profile
- **advanced** - Experimental or specialized components

The auto-registration script assigns categories based on component type and location.

## Testing Your Component

### Local Testing

1. **Install locally**:
   ```bash
   # Test the installer
   ./install.sh --list
   ```

2. **Validate structure**:
   ```bash
   ./scripts/registry/validate-component.sh
   ```

3. **Test with OpenCode**:
   ```bash
   opencode --agent your-new-agent
   ```

### Automated Testing

When you submit a PR, GitHub Actions will:
- Validate component structure
- Validate prompts use defaults
- Update the registry
- Run validation checks

**Important**: PRs will fail if agents don't use their default prompts. This ensures the main branch stays stable.

## Prompt Library System

OpenCode uses a model-specific prompt library to support different AI models while keeping the main branch stable.

### How It Works

```
.opencode/
├── agent/              # Active prompts (always default in PRs)
│   ├── openagent.md
│   └── opencoder.md
└── prompts/            # Prompt library (model-specific variants)
    ├── openagent/
    │   ├── gpt.md          # GPT-4 optimized
    │   ├── gemini.md       # Gemini optimized
    │   ├── grok.md         # Grok optimized
    │   ├── llama.md        # Llama/OSS optimized
    │   ├── TEMPLATE.md     # Template for new variants
    │   ├── README.md       # Capabilities table
    │   └── results/        # Test results (all variants)
    └── opencoder/
        └── ...

**Architecture:**
- Agent files (`.opencode/agent/*.md`) = Canonical defaults
- Prompt variants (`.opencode/prompts/<agent>/<model>.md`) = Model-specific optimizations
```

### For Contributors

#### Testing a Prompt Variant

```bash
# Test a specific variant
./scripts/prompts/test-prompt.sh core/openagent sonnet-4

# View results
cat .opencode/prompts/core/openagent/results/sonnet-4-results.json
```

#### Creating a New Variant

1. **Copy the template:**
   ```bash
   cp .opencode/prompts/core/openagent/TEMPLATE.md .opencode/prompts/core/openagent/my-variant.md
   ```

2. **Edit your variant:**
   - Add variant info (target model, focus, author)
   - Document changes from default
   - Write your prompt

3. **Test it:**
   ```bash
   ./scripts/prompts/test-prompt.sh core/openagent my-variant
   ```

4. **Update the README:**
   - Add your variant to the capabilities table in `.opencode/prompts/core/openagent/README.md`
   - Document test results
   - Explain what it optimizes for

5. **Submit PR:**
   - Include your variant file (e.g., `my-variant.md`)
   - Include updated README with results
   - **Do NOT change the default prompt**
   - **Do NOT change `.opencode/agent/core/openagent.md`**

#### PR Requirements for Prompts

**All PRs must use default prompts.** CI automatically validates this.

Before submitting a PR:
```bash
# Ensure you're using defaults
./scripts/prompts/validate-pr.sh

# If validation fails, restore defaults
./scripts/prompts/use-prompt.sh core/openagent default
./scripts/prompts/use-prompt.sh core/opencoder default
```

#### Why This System?

- **Stability**: Main branch always uses tested defaults
- **Experimentation**: Contributors can optimize for specific models
- **Transparency**: Test results are documented for each variant
- **Flexibility**: Users can choose the best prompt for their model

### For Maintainers

#### Promoting a Variant to Default

When a variant proves superior:

1. **Verify test results:**
   ```bash
   cat .opencode/prompts/core/openagent/results/variant-results.json
   ```

2. **Update agent file (canonical default):**
   ```bash
   cp .opencode/prompts/core/openagent/variant.md .opencode/agent/core/openagent.md
   ```

3. **Update capabilities table** in README

4. **Commit with clear message:**
   ```bash
   git add .opencode/agent/core/openagent.md
   git commit -m "feat(openagent): promote variant to default - improved X by Y%"
   ```

**Note:** In the new architecture, agent files are the canonical defaults. There are no `default.md` files in the prompts directory.

## Commit Message Guidelines

```
type(scope): brief imperative summary (≤72 chars)

Why: what this fixes or enables, and what led to it. Reference docs by
filename when relevant. Prefix `!` for breaking changes (only on `feat`/
`fix`, e.g. `feat(scope)!:`) and add a footer describing the migration
impact.

Files changed:
- /path/file.py v1.2.3: what changed
```

**Types** (enforced):

Primary: `feat` `fix` `docs` `refactor` `test` `chore` `perf`
Also enforced: `style` `ci` `build` `revert` — prerelease commits use `[alpha]` / `[beta]` / `[rc]` prefixes

**Scopes** (lowercase, kebab-case — no spaces)

`cellular-transport` `mqtt` `sensor` `power` `config`

**Rules**
- Subject: imperative mood, why-focused — "implement", not "implemented/implementing"
- Blank line between subject and body; avoid bare one-line commits
- File versions match the project's in-file version headers
- Keep type/scope pairs consistent for searchable history

**Example**
```
feat(transport): implement LTETransport

Replaces broken PPPTransport (see transport-layer-analysis.md).
Uses sim70xx primitives for connection/data I/O.

Files changed:
- /lib/transport.py v1.3.0: added LTETransport class
- /docs/transport-layer-analysis.md v1.1.0: updated status
```

**Enforcement**: commits are validated locally by `scripts/hooks/commit-msg`
(self-contained, no dependencies). Enable it in any clone with:

```bash
cp scripts/hooks/commit-msg .git/hooks/commit-msg && chmod +x .git/hooks/commit-msg
```

Override when intentional: `git commit --no-verify`. PR titles are validated
in CI by `.github/workflows/pr-checks.yml`.

## Pull Request Guidelines

### PR Title Format

Use conventional commits (same format as commit messages):
- `feat(transport): implement LTETransport`
- `fix: correct issue in Y command`
- `docs: update Z documentation`
- `chore: update dependencies`

### PR Description

Include:
1. **What** - What component are you adding/changing?
2. **Why** - Why is this useful?
3. **How** - How does it work?
4. **Testing** - How did you test it?

Example:
```markdown
## What
Adds a new `database-agent` for managing database migrations.

## Why
Automates common database tasks and ensures migration safety.

## How
- Scans migration files
- Validates migration order
- Runs migrations with rollback support

## Testing
- [x] Validated with `./scripts/registry/validate-component.sh`
- [x] Tested with PostgreSQL and MySQL
- [x] Tested rollback scenarios
```

## Component Dependencies

If your component depends on others, declare them in the registry:

```json
{
  "id": "my-component",
  "dependencies": ["tool:env", "agent:task-manager"]
}
```

The installer will automatically install dependencies.

## Registry Auto-Update

The registry is automatically updated when:
- You push to `main` branch
- Changes are made to `.opencode/` directory

The GitHub Action:
1. Scans all components
2. Extracts metadata
3. Updates `registry.json`
4. Commits changes

You don't need to manually edit `registry.json`!

## Code Style

### Markdown
- Use clear, concise language
- Include examples
- Add code blocks with syntax highlighting
- Use proper heading hierarchy

### TypeScript
- Follow existing code style
- Add JSDoc comments
- Use TypeScript types (no `any`)
- Export functions explicitly

### Bash Scripts
- Use `set -e` for error handling
- Add comments for complex logic
- Use meaningful variable names
- Include help text

## Quick Reference

### Creating a New Agent

```bash
# Use the automated system (recommended)
/create-agent my-agent-name

# Or manually follow the development guide
# See: docs/contributing/DEVELOPMENT.md#creating-new-agents
```

### Running Tests

```bash
cd evals/framework
npm test -- --agent=my-agent
```

### Validating Before PR

```bash
# Validate structure
./scripts/registry/validate-component.sh

# Ensure using defaults
./scripts/prompts/validate-pr.sh

# Run tests
cd evals/framework && npm test
```

### Common Commands

```bash
# List available components
./install.sh --list

# Validate registry
make validate-registry

# Update registry
make update-registry

# Test a prompt variant
./scripts/prompts/test-prompt.sh openagent my-variant
```

## Questions?

- **Issues**: Open an issue for bugs or feature requests
- **Discussions**: Use GitHub Discussions for questions
- **Security**: Email security issues privately
- **Development Help**: See [DEVELOPMENT.md](DEVELOPMENT.md) for detailed guides

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

---

Thank you for contributing! 🎉
