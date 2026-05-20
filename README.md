# AI-Orchestration Framework

> **A Plug-and-Play AI Orchestration Framework for AI-Assisted Software Development**
> This framework defines the rules of collaboration between human developers and AI development agents. It is primarily architected for Codex-based workflows with cross-compatibility support for Claude and other LLM agents. It activates instantly by dropping this file structure into your project root.

---

## 🚀 1. Introduction (What is this?)

This project is a **universal directive package exclusively for AI agents** designed to prevent context loss, ensure consistent high-quality code generation, and enforce safe Git workflows during autonomous development. 

It is strictly optimized for **multi-agent collaboration**, establishing clear operational boundaries between feature implementation and test code verification.

---

## 🎯 2. Objectives (Why we built this?)

* **True Universality**: Provides modular, standardized conventions independent of any specific application architecture or tech stack, allowing immediate reuse across any repository.
* **Hallucination Prevention**: Uses a highly disciplined hierarchy of constraints to stop AI from making invalid architectural assumptions or resorting to cutting corners.
* **Strict Quality & Test Isolation**: Separates production coding from test writing. When tests fail, it forces the AI to fix the production code rather than rewriting the tests to fit the broken code.
* **Safe Automation**: Implements strict guardrails requiring explicit human approval before executing any destructive or Git-state altering commands.

---

## 📂 3. Blueprint Folder Structure (Structure)

```text
your-project-root/
├── README.md                            ← This guide (Initial entry point for humans & AI)
├── AGENTS.md                            🔵 Universal — AI Persona / Safety Directives / Routing Table
├── CLAUDE.md                            🔵 Universal — Auto-Discovery / Tool Guide / Troubleshooting
└── docs/agents/
    ├── BACKEND_CONVENTIONS.md           🔵 Universal — Backend Coding Standards & Layer Principles
    ├── TESTING.md                       🔵 Universal — Test Conventions & §0 Multi-Agent Workflow
    └── WORKFLOW.md                      🔵 Universal — Git Branching / Lowercase Commits / PR Scopes
```

> 💡 **PRO TIP (Additional Guidance)**
> This framework is fully globalized and generalized. To inject your repository's specific technical profiles, architectural constraints, or business domain rules, simply add **your own project specification documents (e.g., `PROJECT.md`, `v2-project.md`, or PRDs)** directly under the `docs/agents/` folder. 
> Following the auto-scan routine defined in `CLAUDE.md §1`, the AI agent will automatically locate and ingest your custom files, seamlessly combining universal standards with your project's unique rules.

---

## 🔄 4. Core Automation Workflow (How it works)

All autonomous feature developments, bug fixes, and refactoring tasks strictly adhere to this **5-phase sequential loop**:

```text
 [Phase 2: Main Agent]          [Phase 3: Test Agent (/fork)]       [Phase 4: Main Agent Resumed]
┌──────────────────────┐       ┌────────────────────────────┐      ┌─────────────────────────────┐
│  Implement Feature   │ ───>  │ 1. Write Unit Tests        │ ───> │ 1. Run & Verify Unit Tests  │
│(Production Code Only)│       │ 2. Write E2E/Integrations  │      │ 2. Fix Production if Failed │
└──────────────────────┘       └────────────────────────────┘      └─────────────────────────────┘
                                                                                  │
 [Phase 5: Git & PR Workflow]                                                     ▼
┌─────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Run Full Combo Verification (spotless, compile, test, jacoco) ➔ Approved Lowercase Commit & PR  │
└─────────────────────────────────────────────────────────────────────────────────────────────────┘
```

1. **Phase 1: Planning & Branching** — Define work plan, identify affected modules, and create a feature branch only after explicit human approval.
2. **Phase 2: Implementation (Main Agent)** — Write core production code strictly adhering to `BACKEND_CONVENTIONS.md`. **Absolute Rule:** The main agent must not write or touch test files during this phase.
3. **Phase 3: Testing (Test Agent via `/fork`)** — The main agent pauses execution and prompts the user to spin up a dedicated Test Agent via `/fork`. The Test Agent writes isolated unit tests (Priority 1) followed by E2E/Integration tests (Priority 2), then terminates the session.
4. **Phase 4: Fix & Validation (Main Agent)** — The user returns to the Main Agent session. The agent executes the new tests. **Core Principle:** If a test fails, the agent must alter the production code to resolve the issue. Modifying tests to force-pass is strictly prohibited.
5. **Phase 5: Git Operations & PR** — Run the comprehensive local validation pipeline. Request individual approval before executing any Git command, then push using strict lowercase tracking formats (`type(scope):`).

---

## 🛠️ 5. Installation & Execution (How to use?)

### Step 1: Clone and Drop Files
Copy the boilerplate files from this repository into your target project using this exact layout:
* Place `AGENTS.md` and `CLAUDE.md` directly into your project **root**.
* Place the `docs/agents/` folder directly under your project's **`docs/`** directory.

### Step 2: Initialize the AI Agent Session
When starting a fresh conversation with your AI tool (e.g., Codex or Claude), seed the session by sending this exact prompt as your very first instruction:

> *"Read `AGENTS.md` at the project root first to understand your persona, safety directives, routing rules, and the strict 5-phase multi-agent development workflow before executing any tasks."*

The AI agent will instantly map out your environment, honor the execution boundaries, and begin safe, highly disciplined autonomous programming.

---

## 🇰🇷 한국어 요약 (Korean Summary)

본 프로젝트는 **인간 개발자와 AI 에이전트 간의 안전하고 효율적인 협업을 위해 설계된 AI 전용 지침서 패키지**입니다. 주로 Codex 기반의 워크플로우에 맞춰 정밀하게 설계되었으며, Claude와 같은 타 LLM 에이전트도 완벽하게 참고할 수 있도록 범용적인 마크다운 포맷으로 추상화되어 있습니다.

### 핵심 요약
1. **만능 공용화 구조**: 특정 프로젝트에 종속되지 않는 6개의 핵심 문서로만 구성되어 있어, 어떤 프로젝트 루트든 폴더째 그대로 복사·붙여넣기(`Plug-and-Play`)하여 바로 사용할 수 있습니다.
2. **멀티 에이전트 격리**: 기능 개발(메인 AI)과 테스트 코드 작성(테스트 AI, `/fork` 활용)의 역할을 철저히 분리하여 AI가 스스로 편법 코드를 짜거나 환각을 일으키는 것을 방지합니다.
3. **강력한 확장성**: 프로젝트 고유의 기술 스택 정보나 특수 제약 조건이 필요하다면, `docs/agents/` 폴더 하위에 개별 문서(예: `PROJECT.md`)를 추가하기만 하면 AI가 자동 발견(`§1 Auto-Discovery`)하여 똑똑하게 반영합니다.
4. **사용 방법**: 파일을 루트 및 `docs/` 하위에 복사한 뒤, AI 세션이 시작될 때 첫 명령어로 `"Read AGENTS.md at the project root first..."` 문장을 던져주면 AI가 스스로 규칙을 주입받고 엄격한 제어 하에 자율 개발을 수행합니다.