# MagSlide — Google Slides MCP Server

A Model Context Protocol (MCP) server that exposes the Google Slides API to an
MCP client (e.g. Claude Code). Forked from
[`matteoantoci/google-slides-mcp`](https://github.com/matteoantoci/google-slides-mcp)
and rebranded **MagSlide**.

**What it's for:** fast, design-preserving slide creation. Duplicate an existing
slide (font, size, position, colors all preserved) and replace **only** the text
inside its shapes — the AI reads your example slides and decides what text goes
where, no placeholders or template tokens.

**Run model:** the server holds Google OAuth credentials and pulls ~330 npm
dependencies, so it runs **inside Docker** as a non-root user with no access to
your host filesystem — never directly on the host. Transport is **stdio**.

## Prerequisites

* **Docker** (the only runtime requirement — no Node.js/npm on the host).
* A **Google Cloud project** with the **Google Slides API** enabled.
* **OAuth 2.0 credentials** (Client ID + Secret) and a **refresh token** (minted below).

## 1. Build the image

```bash
docker build -t magslide:latest .
```

Dependencies are installed with `npm ci --ignore-scripts` inside the build stage
(no package lifecycle scripts run), and the final image runs as the `node` user.

## 2. Get Google OAuth credentials

1. [Google Cloud Console](https://console.cloud.google.com/) → create/select a project.
2. **APIs & Services → Library** → search **Google Slides API** → **Enable**.
3. **APIs & Services → OAuth consent screen** → User type **External** → fill in app
   name + your email. Add your Google account under **Test users**.
   * ⚠️ A refresh token from an app in **Testing** status expires after **7 days**.
     To get a long-lived token, **Publish** the app to **Production**.
4. **APIs & Services → Credentials → Create credentials → OAuth client ID**:
   * Application type: **Web application**.
   * Authorized redirect URI: `http://localhost:3000/oauth2callback` — you only
     paste it into this field; it is **not** a page you open. Google redirects
     here automatically during step 4, where a server briefly listens on port 3000.
   * Create, then copy the **Client ID** and **Client Secret**.

The only OAuth scope requested is `https://www.googleapis.com/auth/presentations`.
No Drive access is requested — MagSlide never touches Drive.

## 3. Store secrets in a local env file

Secrets live in a `.env` at the repo root, which Docker reads via `--env-file`.
`.env` is gitignored (only `.env.example` is committed), so it is never shared.
Copy the template and fill it in:

```bash
cp .env.example .env
```

```
GOOGLE_CLIENT_ID=your-client-id
GOOGLE_CLIENT_SECRET=your-client-secret
GOOGLE_REFRESH_TOKEN=
```

Paste raw values — no quotes, no spaces around `=`. Leave `GOOGLE_REFRESH_TOKEN`
empty for now; you fill it in the next step.

## 4. Mint a refresh token

Run the one-off token helper inside the container, feeding it the same file (only
the client id/secret are needed yet). It prints a URL; the OAuth callback returns
to `localhost:3000`, published from the container:

Run it from the repo root (so `--env-file .env` resolves):

```bash
docker run --rm -p 3000:3000 \
  --env-file .env \
  --entrypoint node magslide:latest build/getRefreshToken.js
```

Open the printed URL, authorize, copy the **refresh token** from the terminal,
and paste it as `GOOGLE_REFRESH_TOKEN=` in `.env`.

> A refresh token from an OAuth app in **Testing** status expires after **7 days**.
> Publish the app to **Production** for a long-lived token (see step 2).

## 5. Register the server with your MCP client

This repo ships an `.mcp.json` that runs the server via Docker and reads `.env`
directly — no secrets in the config, no shell exports required:

```json
{
  "mcpServers": {
    "magslide": {
      "command": "docker",
      "args": [
        "run", "-i", "--rm",
        "--env-file", ".env",
        "magslide:latest"
      ]
    }
  }
}
```

The `.env` path is relative, so launch your MCP client from the repo root.
Restart the client and the `magslide` tools become available — and stay
available across sessions. Nothing here is machine-specific, so the repo works
as-is on Linux, macOS, and Windows (anywhere Docker runs).

## Security notes

* Runs in Docker as non-root with only the three OAuth env vars — no host FS access.
* OAuth scope limited to `presentations`; `drive.readonly` was deliberately removed.
* Dependencies installed with `--ignore-scripts`; review `package-lock.json` before adding any.

## Available tools

* **`create_presentation`** — create a new presentation. Input: `title`.
* **`get_presentation`** — fetch presentation details. Input: `presentationId`, optional `fields` mask.
* **`batch_update_presentation`** — the workhorse. Applies raw Slides API
  [`batchUpdate`](https://developers.google.com/slides/api/reference/rest/v1/presentations/batchUpdate#requestbody)
  requests. Input: `presentationId`, `requests` (array), optional `writeControl`.
* **`get_page`** — fetch one slide. Input: `presentationId`, `pageObjectId`.
* **`summarize_presentation`** — extract all text per slide. Input: `presentationId`, optional `include_notes`.

## Design-preserving workflow

1. Read the first slides with `get_presentation` / `get_page` to learn the deck's structure.
2. Send a `batch_update_presentation` with a `duplicateObject` request to clone a template slide.
3. Replace the text in the new slide via `replaceAllText` or `insertText` + `deleteText`,
   scoped to the new slide's object IDs. Formatting is inherited from the original — never overwritten.
