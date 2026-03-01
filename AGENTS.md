# AGENTS.md

This project follows a structured AI-assisted development workflow.

You (the agent) must follow this process for every task.


## 1. Project Philosophy

This is not just an Emacs plugin.
It is an experimental cognitive runtime system.

We prioritize:

- Clear specifications
- Separation of spec and state
- Controlled evolution
- Testable behavior
- Reproducibility

Never implement features without specification.


## 2. Required Workflow For Each Task

When assigned a new task:

### Step 1 — Write or Update PRD

- Create or update a file in `prd/` , the tempate is from `prd/000-template.org` in org-mode format.
- Clearly define:
  - Problem
  - Scope
  - Constraints and Expected behavior
  - Tasks

Do not write code before PRD exists.


### Step 2 — Implementation

- Implement feature in `elisp/`
- Follow Emacs Lisp best practices
- Keep functions small and testable
- Avoid global side effects unless necessary


### Step 3 — Write Tests

- Add ERT tests in `tests/org-ai-skills-test.el`
- Add BDD scenario tests in `tests/bdd/` following `tests/bdd/000-template.org`
- Cover core logic
- Include failure scenarios


### Step 4 — Run Tests

Ensure tests pass.

If tests fail:
- Fix implementation
- Do not remove tests unless justified in PRD
- Do not mark feature complete until all relevant test suites pass (ERT + BDD/E2E when applicable)


### Step 5 — Documentation Update

If behavior changes:

- Update README.org
- Update usage section if needed


### Step 6 — Worklog Entry

Append to the prd file in worklog section:

- What was implemented
- Test status

## 3. Coding Constraints

- No silent breaking changes
- No skipping tests
- No hidden state mutation
- No modifying Skill spec files during runtime

## 4. Execution Quality Rules

- Prioritize root-cause analysis and direct fixes; do not default to fallback or downgraded solutions unless constraints are explicitly documented in the PRD.
- **Never add fallback logic.** If root cause is unresolved, continue investigation and fix the cause directly instead of adding fallback paths.
- The agent may raise clarifying questions in the PRD file when requirements, constraints, or expected behavior are ambiguous.

## 5. Self-Check Before Completion

Before finishing a task, verify:

- PRD exists
- Code matches PRD
- Tests exist in both `tests/org-ai-skills-test.el` and `tests/bdd/` (for new feature behavior)
- Tests pass (all relevant ERT and BDD/E2E cases)
- README updated if needed
- Worklog updated

If any item missing → do not mark task complete.

## 6. Long-Term Goal

We are building: A Skill-based cognitive runtime system inside Emacs.

All implementations should preserve:
- Spec vs Run separation
- Proposal-based evolution
- Governance layer

## 7. Parallel Feature Development Strategy (Git Worktree + Multi-Codex)

When multiple features are developed in parallel, all agents must follow this protocol.

### 7.1 Branch and Worktree Setup

- Use one feature branch per PRD from the same baseline commit (usually `main`).
- Use one worktree per feature branch.
- Naming convention:
  - Branch: `feat/<prd-id>-<short-name>`
  - Worktree folder: `../org-ai-skills-<prd-id>`
- Example:
  - `git worktree add ../org-ai-skills-014 -b feat/014-observability main`

### 7.2 Ownership and File Boundaries

- Each branch must have a primary ownership area declared in its PRD.
- Avoid cross-branch edits to the same files unless explicitly planned.
- Shared foundational changes must be isolated into a dedicated foundation PR first.
- If overlap is unavoidable, document expected conflict points in each PRD.

### 7.3 PRD-First Enforcement Per Branch

- Each branch must create/update its own PRD before implementation.
- PRD must include:
  - Scope boundary
  - Constraints
  - Expected behavior
  - Task checklist
  - Worklog entries
- Do not start coding until PRD exists in that branch.

### 7.4 Test Isolation and Safety

- Every branch adds/updates only tests required by its own PRD scope.
- Tests must pass in the feature branch before opening PR.
- Do not delete or weaken existing tests to reduce merge friction.

### 7.5 Merge and Rebase Strategy

- Merge order:
  - Foundation/shared-infra branch first (if any).
  - Then features with lowest dependency depth.
- After each merge to `main`, remaining feature branches must rebase on latest `main`.
- Resolve conflicts with root-cause fixes, not temporary bypasses.

### 7.6 Required PR Checklist (Per Feature Branch)

- [ ] PRD exists and is up to date.
- [ ] Implementation matches PRD scope.
- [ ] ERT tests added/updated and passing.
- [ ] README updated when behavior changes.
- [ ] PRD worklog appended with implementation and test status.
- [ ] No unplanned edits outside declared ownership area.

## 8. Debugging and Observability Protocol

### 8.1 Non-Negotiable Rules

- Do not rely on assumptions when debugging asynchronous/runtime issues; verify each assumption with concrete logs or reproducible tests.
- Never jump to late-stage hypotheses first; debug must proceed by calling stage order.
- Never add fallback or downgrade paths to "make it work." Keep contracts strict and fix root cause directly.

### 8.2 Stage-First Debug Flow (Required)

For planner/execution/callback issues, follow this order and do not skip stages:

1. Stage A — Dispatch correctness
- Verify request payload, model, schema/response format, stream flag, tools, and timeout settings.
- Confirm runtime actually sends the expected request once.

2. Stage B — Callback transport/lifecycle
- Verify callback events arrive and classify each event shape (text/tool/reasoning/terminal).
- Verify terminal condition detection logic against real callback sequence.

3. Stage C — Response extraction
- Verify exact text chosen for parsing (and what was ignored).
- Confirm request-echo metadata is never treated as model output.

4. Stage D — Parser boundary/contract
- Verify parser input string is complete and matches contract.
- Validate JSON/object extraction boundaries and schema constraints.

5. Stage E — State transition/UI completion
- Verify run-state transitions (`running -> success/error/canceled`) and timeout behavior.
- Verify callback completion cannot leave control state stuck.

6. Stage F — Regression proof
- Add focused ERT for the root cause.
- Add/update BDD when behavior contract changed.
- Record exact failure signature and fix in PRD worklog.

### 8.3 Observability Baseline

- Keep default logs concise, but ensure each stage (A-E) has at least one inspectable signal.
- Add temporary deep logs only when needed for active incident diagnosis, and remove them during cleanup.
- If a bug required deep logs to solve, convert the minimum necessary signals into stable observability flags/settings.

### 8.4 Incident Triage Tips (Network vs Runtime)

- If failures show transport signatures (for example `Could not parse HTTP response`, missing `http-status`, or `header_bytes=0`), treat environment/network constraints as first hypothesis.
- In sandboxed runs, request escalation early for network-dependent E2E diagnosis instead of repeatedly retrying non-escalated commands.
- Before changing runtime logic, verify whether a direct provider probe (same key/model route) succeeds under current permissions.
- For long live runs, rely on heartbeat + sub-step signals (`step-execution`, `tool-call`, `tool-result`) to distinguish true stalls from active progress.
