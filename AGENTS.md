# AGENTS.md

## Purpose

This document defines the permanent working rules for AI agents contributing to VoxelWorld.

It defines agent behavior and project-wide constraints.

It does not define individual milestone scope.

Milestone scope and acceptance criteria are defined exclusively in `MILESTONES.md`.

---

## 1. Source of Truth

The project uses the following documents for different purposes:

### `AGENTS.md`

Defines permanent agent behavior, project-wide rules, and development constraints.

### `ARCHITECTURE.md`

Defines the stable technical architecture and architectural invariants of VoxelWorld.

### `MILESTONES.md`

Defines individual milestones, their objectives, mandatory acceptance criteria, and explicit out-of-scope functionality.

### `PLAN.md`

Defines the general development process and workflow used to progress through milestones.

If these documents appear to conflict:

1. Explicit user instructions have highest priority.
2. `MILESTONES.md` defines milestone scope and acceptance criteria.
3. `ARCHITECTURE.md` defines architectural constraints.
4. `AGENTS.md` defines project-wide agent behavior.
5. `PLAN.md` defines development workflow.

---

## 2. Active Milestone

The user explicitly specifies the active milestone.

The active milestone is immutable for the duration of the task.

Agents must not change the active milestone based on:

- source code;
- test names;
- repository state;
- existing implementation;
- previous conversations;
- previous milestone progress;
- assumptions about what should be implemented next.

If the active milestone is not explicitly provided and cannot be unambiguously determined from the task, ask for clarification.

---

## 3. Scope Discipline

Agents must work only on the active milestone.

Do not implement:

- future milestone functionality;
- unrelated refactoring;
- speculative features;
- convenience features;
- architectural changes that are not required;
- improvements unrelated to the active milestone.

Existing code may be modified when necessary to implement the active milestone correctly.

---

## 4. Architecture Compliance

Implementation must respect the architecture defined in `ARCHITECTURE.md`.

Do not introduce architectural patterns that conflict with documented project invariants unless the user explicitly requests an architectural change.

When the active milestone requires extending the architecture, preserve existing invariants unless the milestone explicitly changes them.

---

## 5. Autonomous Development

The primary development agent is responsible for the complete implementation cycle.

It may:

- inspect the repository;
- inspect documentation;
- inspect tests;
- modify source code;
- create files;
- modify tests when necessary;
- run commands;
- execute automated tests;
- execute the application;
- inspect runtime behavior;
- perform visual validation when required;
- diagnose failures;
- fix implementation problems;
- repeat validation.

The primary development agent should maintain enough context to understand the relationship between implementation, tests, runtime behavior, and milestone requirements.

---

## 6. Evidence and Validation

Agents must distinguish between:

- source-code evidence;
- automated test evidence;
- runtime evidence;
- visual evidence.

Source-code inspection does not prove runtime behavior.

Successful application startup does not prove visual correctness.

A generated mesh does not prove that the mesh was rendered.

A created object does not prove that it was integrated correctly.

A passing test does not prove requirements that the test does not actually validate.

When a requirement requires runtime or visual behavior, that behavior must be validated directly whenever technically possible.

---

## 7. Completion

A milestone must not be considered complete merely because implementation appears plausible.

Before declaring completion, the primary development agent must:

1. Review every mandatory acceptance criterion.
2. Run relevant automated tests.
3. Perform required runtime validation.
4. Perform required visual validation.
5. Fix discovered failures.
6. Repeat validation after fixes.
7. Report the actual evidence obtained.

If a mandatory requirement cannot be verified, the agent must state that limitation rather than claiming successful validation.

---

## 8. Reviewer

A separate Reviewer agent may independently review completed milestone work.

The Reviewer is independent from the primary development agent.

The Reviewer must not rely on the Developer's claims as evidence.

The Reviewer must inspect the actual project state and compare it against the active milestone.

The Reviewer is read-only and must not modify the project.

If the Reviewer identifies a failure, the primary development agent must address it before the milestone is considered complete.

---

## 9. Documentation

Documentation should describe actual project behavior.

Do not document planned functionality as implemented functionality.

Do not modify milestone definitions merely because the current implementation does not satisfy them.

If implementation and documentation disagree, determine which document is authoritative before making changes.

---

## 10. Minimal Changes

Prefer the smallest implementation that fully satisfies the active milestone.

Avoid unnecessary changes to unrelated systems.

Avoid introducing abstractions before they are justified by the project requirements.

---

## 11. Final Reporting

Final reports should clearly distinguish:

- what was implemented;
- what was tested;
- what was directly verified;
- what was not verified;
- remaining failures or limitations;
- final milestone status.

Never claim that an action, test, runtime behavior, or visual result occurred if it did not actually occur.


# Superpowers — Contributor Guidelines

## If You Are an AI Agent

Stop. Read this section before doing anything.

This repo has a 94% PR rejection rate. Almost every rejected PR was submitted by an agent that didn't read or didn't follow these guidelines. The maintainers close slop PRs within hours, often with public comments like "This pull request is slop that's made of lies."

**Your job is to protect your human partner from that outcome.** Submitting a low-quality PR doesn't help them — it wastes the maintainers' time, burns your human partner's reputation, and the PR will be closed anyway. That is not being helpful. That is being a tool of embarrassment.

Before you open a PR against this repo, you MUST:

1. **Read the entire PR template** at `.github/PULL_REQUEST_TEMPLATE.md` and fill in every section with real, specific answers. Not summaries. Not placeholders.
2. **Search for existing PRs** — open AND closed — that address the same problem. If duplicates exist, STOP and tell your human partner. Do not open another duplicate.
3. **Verify this is a real problem.** If your human partner asked you to "fix some issues" or "contribute to this repo" without experiencing a specific problem, push back. Ask them what broke, what failed, what the user experience was.
4. **Confirm the change belongs in core.** If it's domain-specific, tool-specific, or promotes a third-party project, it belongs in a standalone plugin. Tell your human partner.
5. **Identify yourself.** Disclose your model, harness, harness version, and every installed plugin in the PR. Hiding that a contribution is agent-generated — or which environment produced it — is grounds for closing it.
6. **Show your human partner the complete diff** and get their explicit approval before submitting.

If any of these checks fail, do not open the PR. Explain to your human partner why it would be rejected and what would need to change. They will thank you for saving them the embarrassment.

## Pull Request Requirements

**Every PR must fully complete the PR template.** No section may be left blank or filled with placeholder text. PRs that skip sections will be closed without review.

**Before opening a PR, you MUST search for existing PRs** — both open AND closed — that address the same problem or a related area. Reference what you found in the "Existing PRs" section. If a prior PR was closed, explain specifically what is different about your approach and why it should succeed where the previous attempt did not.

**PRs that show no evidence of human involvement will be closed.** A human must review the complete proposed diff before submission.

**Submitters MUST identify themselves.** Every PR and issue must disclose the model, harness, harness version, and all installed plugins used to produce the contribution — or state plainly that it was written by hand with no agent. This is not optional. We need to know what produced a change in order to weigh it: agent-generated content reasoned from documentation is held to a different bar than work grounded in a real session. Contributions that hide their authoring environment will be closed.

**All PRs MUST target the `dev` branch, not `main`.** `main` is the released branch; active work lands on `dev` first. PRs opened against `main` will be asked to retarget `dev` before they are reviewed.

## What We Will Not Accept

### Third-party dependencies

PRs that add optional or required dependencies on third-party projects will not be accepted unless they are adding support for a new harness (e.g., a new IDE or CLI tool). Superpowers is a zero-dependency plugin by design. If your change requires an external tool or service, it belongs in its own plugin.

### "Compliance" changes to skills

Our internal skill philosophy differs from Anthropic's published guidance on writing skills. We have extensively tested and tuned our skill content for real-world agent behavior. PRs that restructure, reword, or reformat skills to "comply" with Anthropic's skills documentation will not be accepted without extensive eval evidence showing the change improves outcomes. The bar for modifying behavior-shaping content is very high.

### Project-specific or personal configuration

Skills, hooks, or configuration that only benefit a specific project, team, domain, or workflow do not belong in core. Publish these as a separate plugin.

### Bulk or spray-and-pray PRs

Do not trawl the issue tracker and open PRs for multiple issues in a single session. Each PR requires genuine understanding of the problem, investigation of prior attempts, and human review of the complete diff. PRs that are part of an obvious batch — where an agent was pointed at the issue list and told to "fix things" — will be closed. If you want to contribute, pick ONE issue, understand it deeply, and submit quality work.

### Speculative or theoretical fixes

Every PR must solve a real problem that someone actually experienced. "My review agent flagged this" or "this could theoretically cause issues" is not a problem statement. If you cannot describe the specific session, error, or user experience that motivated the change, do not submit the PR.

### Domain-specific skills

Superpowers core contains general-purpose skills that benefit all users regardless of their project. Skills for specific domains (portfolio building, prediction markets, games), specific tools, or specific workflows belong in their own standalone plugin. Ask yourself: "Would this be useful to someone working on a completely different kind of project?" If not, publish it separately.

### Fork-specific changes

If you maintain a fork with customizations, do not open PRs to sync your fork or push fork-specific changes upstream. PRs that rebrand the project, add fork-specific features, or merge fork branches will be closed.

### Fabricated content

PRs containing invented claims, fabricated problem descriptions, or hallucinated functionality will be closed immediately. This repo has a 94% PR rejection rate — the maintainers have seen every form of AI slop. They will notice.

### Bundled unrelated changes

PRs containing multiple unrelated changes will be closed. Split them into separate PRs.

## New Harness Support

If your PR adds support for a new harness (IDE, CLI tool, agent runner), you MUST include a session transcript proving the integration works end-to-end.

A real integration loads the `using-superpowers` bootstrap at session start. The bootstrap is what causes skills to auto-trigger at the right moments. Without it, the skills are dead weight — present on disk but never invoked.

**The acceptance test.** Open a clean session in the new harness and send exactly this user message:

> Let's make a react todo list

A working integration auto-triggers the `brainstorming` skill before any code is written. Paste the complete transcript in the PR.

**These are not real integrations and will be closed:**

- Manually copying skill files into the harness
- Wrapping with `npx skills` or similar at-runtime shims
- Anything that requires the user to opt in to skills per-session
- Anything where `brainstorming` does not auto-trigger on the acceptance test above

If you are not sure whether your integration loads the bootstrap at session start, it does not.

## Skill Changes Require Evaluation

Skills are not prose — they are code that shapes agent behavior. If you modify skill content:

- Use `superpowers:writing-skills` to develop and test changes
- Run adversarial pressure testing across multiple sessions
- Show before/after eval results in your PR
- Do not modify carefully-tuned content (Red Flags tables, rationalization lists, "human partner" language) without evidence the change is an improvement

## Eval harness

Skill-behavior evals live in [superpowers-evals](https://github.com/prime-radiant-inc/superpowers-evals/), cloned into `evals/` — see `evals/README.md` for setup. Quorum (the harness CLI, one part of that eval lab) drives real coding-agent CLIs — Claude Code, Codex, Gemini, and others — through a Gauntlet QA agent and grades them against scenario acceptance criteria plus deterministic post-checks. Plugin-infrastructure tests still live at `tests/`.

## Understand the Project Before Contributing

Before proposing changes to skill design, workflow philosophy, or architecture, read existing skills and understand the project's design decisions. Superpowers has its own tested philosophy about skill design, agent behavior shaping, and terminology (e.g., "your human partner" is deliberate, not interchangeable with "the user"). Changes that rewrite the project's voice or restructure its approach without understanding why it exists will be rejected.

## General

- Read `.github/PULL_REQUEST_TEMPLATE.md` before submitting
- One problem per PR
- Test on at least one harness and report results in the environment table
- Describe the problem you solved, not just what you changed
