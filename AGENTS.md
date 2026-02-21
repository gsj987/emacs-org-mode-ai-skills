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

- Add ERT tests in `tests/`
- Cover core logic
- Include failure scenarios


### Step 4 — Run Tests

Ensure tests pass.

If tests fail:
- Fix implementation
- Do not remove tests unless justified in PRD


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
- The agent may raise clarifying questions in the PRD file when requirements, constraints, or expected behavior are ambiguous.

## 5. Self-Check Before Completion

Before finishing a task, verify:

- PRD exists
- Code matches PRD
- Tests exist
- Tests pass
- README updated if needed
- Worklog updated

If any item missing → do not mark task complete.

## 6. Long-Term Goal

We are building: A Skill-based cognitive runtime system inside Emacs.

All implementations should preserve:
- Spec vs Run separation
- Proposal-based evolution
- Governance layer
