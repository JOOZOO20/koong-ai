# AGENTS.md

> **This document defines the core personas, boundaries, and execution permissions for all AI Agents operating in this project.**
> - Git/Commit/PR Rules → `docs/agents/WORKFLOW.md`
> - Code Conventions → `docs/agents/BACKEND_CONVENTIONS.md`
> - Testing & Coverage → `docs/agents/TESTING.md`

---

## 1. Agent Personas & Work Scope

All agents are autonomous developer assistants. Your primary goal is to complete the tasks assigned to you without hallucinating out of your scope.

### 1.1 Task Assignment
- You will be assigned a specific agent number (e.g., Agent 1, Agent 2).
- You MUST read `docs/agents/V2_PROJECT.md` for project context.
- You MUST only work on tasks defined in your specific to-do list (`docs/agents/agent<N>-todo.md`). Do not touch other agents' tasks.

### 1.2 Scope Boundaries
- Do not modify core infrastructure, global configurations, or shared contracts unless explicitly requested.
- Maintain strict domain isolation. You are responsible ONLY for the domain assigned in your current task.

---

## 2. Core Operating Principles

### 2.1 Fully Autonomous Execution
You are operating in a **Fully Autonomous Loop**. Do not stop to ask the human for help when encountering compilation errors, test failures, or minor logical bugs. 
- You must read the logs, analyze the root cause, and fix the code yourself.
- Repeat the `./gradlew test` loop until all your domain tests pass 100%.

### 2.2 No Meta-Document Creation
- **DO NOT** create, modify, or commit files related to your own thought process, agent scope definitions, planning, or to-do lists (e.g., `agent-scope.md`, `plan.txt`). 
- **ONLY** modify real project artifacts (source code, tests, DB migrations).

### 2.3 Strict Naming & Language 
- **Branch/Commit Scope:** DO NOT use your agent identifier (e.g., "Agent 3") in branch names, commit messages, or PR titles. Follow `WORKFLOW.md` §1.3 and §3.1 strictly.
- **Language:** Code/Syntax in English. Explanations/Contexts in Korean.

---

## 3. Permissions & Human Interaction

This section defines what you can do autonomously and when you MUST stop and ask the human.

### 3.1 Git Command Permissions (Strictly Enforced)

You have full autonomy to execute safe, local workspace Git commands. You DO NOT need to ask for human approval for the following read-only or safe local commands:
- **✅ AUTO-APPROVED (DO NOT ASK):** - `git checkout -b <branch-name>`
  - `git checkout <branch-name>`
  - `git branch`
  - `git status`
  - `git diff`
  - `git log`

**🚨 REQUIRES HUMAN APPROVAL:**
You MUST halt and ask for explicit human permission BEFORE executing any state-changing or publishing Git commands:
- **❌ DO NOT EXECUTE WITHOUT ASKING:**
  - `git add` (Staging files)
  - `git commit`
  - `git push`

### 3.2 Terminal & Build Commands
- **✅ AUTO-APPROVED:** You are freely allowed to run build and test commands (e.g., `./gradlew compileJava`, `./gradlew test`, `./gradlew spotlessApply`) autonomously as many times as needed to verify your code.

### 3.3 When to Pause and Await Human
You should only output your final status and await human input when:
1. You have fully completed Phase 1 through Phase 4 of `WORKFLOW.md`.
2. Your local tests pass successfully (ignoring the 80% global coverage rule if working in a fragmented worktree).
3. You are ready for Phase 5 (Commit & PR) and need to request permission for `git add/commit/push`.

---

## 4. Initialization Protocol

Whenever you start a new session, you must:
1. Identify your Agent Number.
2. Read your specific `todo.md`.
3. Check the first uncompleted task `[ ]`.
4. Create a new branch (without asking for permission) following `WORKFLOW.md` §1.3.
5. Begin implementation.