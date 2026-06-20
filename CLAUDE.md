# MagSlide — AI agent context

MCP server (TypeScript / Node 24) exposing the Google Slides API to an MCP
client. Forked from `matteoantoci/google-slides-mcp`, rebranded MagSlide.
You don't develop this as an app — you run the server and drive it from
Claude Code chat: read a deck's first slides, then duplicate + refill them.

## What it's for

Fast slide creation that keeps the design intact: duplicate an existing
slide (font, size, position, colors all preserved) and replace ONLY the
text inside its shapes. The AI reads the example slides and decides what
text goes where — no placeholders, no template tokens.

## Run model (read before touching config)

- The server holds Google OAuth credentials and runs ~330 npm deps, so it
  ALWAYS runs inside Docker (`magslide:latest`) — never on the host.
- Transport is stdio. `.mcp.json` registers it as `docker run -i --rm`.
- Auth = 3 secrets (`GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`,
  `GOOGLE_REFRESH_TOKEN`) in a gitignored `.env` at the repo root; Docker reads
  it via `--env-file .env` (relative — launch the MCP client from the repo root).
  Only `.env.example` is committed.

## Architecture (`src/`)

- `index.ts` — entry: builds the OAuth2 + Slides client, starts the stdio server.
- `serverHandlers.ts` — registers the 5 tools, routes calls via `executeTool`.
- `tools/*.ts` — one file per tool; each only calls `slides.presentations.*`.
- `schemas.ts` — zod arg schemas. `utils/` — env check, error mapping, executor.
- `getRefreshToken.ts` — one-off OAuth flow that mints the refresh token.

## The 5 tools

`create_presentation`, `get_presentation`, `get_page`,
`summarize_presentation`, and the workhorse **`batch_update_presentation`**
(raw Slides API `batchUpdate`). To clone a slide and swap its text, send a
`duplicateObject` request, then `replaceAllText` / `insertText`+`deleteText`
scoped to the new slide — formatting is inherited, never overwritten.

## Gotchas

- OAuth scope is `presentations` ONLY. `drive.readonly` was removed on
  purpose — do NOT re-add it; no tool touches Drive.
- Supply chain: install deps ONLY with `npm ci --ignore-scripts`, and review
  `package-lock.json` before adding anything. The Dockerfile already does this.
- A refresh token from an OAuth app in "Testing" status expires after 7 days
  — publish the app to "Production" for a long-lived token.
- This is a fork: keep changes minimal and upstream-mergeable.

## Commands

- `docker build -t magslide:latest .` — build the isolated server image.
- Mint a refresh token (one-off, in the container — needs client id/secret in env):
  `docker run --rm -p 3000:3000 -e GOOGLE_CLIENT_ID -e GOOGLE_CLIENT_SECRET --entrypoint node magslide:latest build/getRefreshToken.js`
  then open the printed URL in your browser.
