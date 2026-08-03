---
name: koong-new
description: Bootstraps a brand-new backend project from zero code — recommends a stack in plain Korean, scaffolds it, git-inits, optionally creates a private GitHub repo, runs /koong-init, then hands off to /koong with the user's original request. Use when the directory has no source code.
---

# /koong-new — 새 프로젝트 부트스트랩

## 1. Stack choice (ONE jargon-free question)

```
새 프로젝트를 만들게요. 하나만 여쭤볼게요:
나중에 화면(웹사이트)도 같이 만들고 싶으세요?
① 네, 언젠가는요 (추천 → Next.js로 만들어요: 한 프로젝트로 화면까지 확장 가능)
② 아니요, 데이터 처리 기능만 필요해요 (→ FastAPI로 만들어요)
③ 제가 직접 고를게요 (java-spring / python-fastapi / node-nextjs / go)
```

Expert users who named a stack in their request: skip the question. Learning-Java-for-jobs signals ("스프링 배우고 싶어요", "취업 준비") → java-spring.

## 2. Scaffold (APP = kebab-case project name derived from the request; confirm if ambiguous)

**java-spring**
```bash
curl -s https://start.spring.io/starter.tgz \
  -d type=gradle-project -d language=java -d javaVersion=21 -d packaging=jar \
  -d groupId=com.example -d artifactId=${APP} -d name=${APP} \
  -d dependencies=web,data-jpa,security,validation,flyway,postgresql,h2,lombok,actuator \
  -o starter.tgz && tar -xzf starter.tgz && rm starter.tgz
```

**python (FastAPI)**
```bash
uv init ${APP} --python 3.12 && cd ${APP}
uv add "fastapi[standard]" sqlmodel alembic "passlib[bcrypt]" pyjwt pydantic-settings
uv add --dev pytest httpx ruff mypy
```
Then write a minimal `app/main.py` with a `/health` endpoint.

**node-nextjs**
```bash
npx --yes create-next-app@latest ${APP} --ts --eslint --app --src-dir --no-tailwind --use-npm --yes
cd ${APP} && npm i prisma @prisma/client zod bcrypt jose
npx prisma init --datasource-provider sqlite    # beginners start with a file DB — no install needed
```

**go**
```bash
mkdir ${APP} && cd ${APP} && go mod init github.com/example/${APP}
go get github.com/labstack/echo/v4 github.com/golang-jwt/jwt/v5
```
Then write a minimal `cmd/server/main.go` with `/health` and graceful shutdown.

If scaffolding lands in a subdirectory, move the koong payload (`CLAUDE.md`, `.claude/`, `docs/koong/`) into the project directory (or tell the user to reopen Claude Code there).

## 3. Git bootstrap (fixed sequence)

1. `git init -b main` (if not already a repo)
2. Append the stack gitignore from `docs/koong/` install payload (`templates/gitignore/<stack>.txt` content was installed — if absent, write a standard one). Ensure `.env*` and `.claude/koong/state/` are covered.
3. `bash .claude/koong/scripts/mark.sh bootstrap` — one-time gate pass for the scaffold commit (marker-based, not message-based)
4. `git add -A && git commit` with message `chore: 프로젝트 스캐폴딩 (<stack>)`
5. GitHub (ask ONCE, plain Korean): "코드를 깃허브(온라인 코드 보관소)에도 올려둘까요? 무료이고, 비공개라 남들은 못 봐요. (추천: 네)" → yes: `gh repo create ${APP} --private --source=. --push`. Never `--public`.

## 4. Hand-off

1. Run `/koong-init` (it will set `mode: beginner` unless the user clearly isn't one — someone who picked ③ and named a stack is likely `expert`; still confirm with the init question).
2. Invoke `/koong` with the user's **original request sentence** — the interview continues there and must not re-ask the stack (already answered).
