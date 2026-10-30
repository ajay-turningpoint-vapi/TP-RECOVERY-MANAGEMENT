# TP-RMS Recovery Control (RE web dashboard)

Desktop web dashboard for the **Recovery Executive** role. It uses the existing TP-RMS Express API (`../server`) and database **unchanged** — same logins, same endpoints, same data as the mobile app. Nothing on the server needs deploying for it.

## Run locally

```bash
cp .env.example .env.local   # set RMS_API_URL to the TP-RMS API base URL
npm install
npm run dev                  # http://localhost:3000
npm test                     # selector unit tests (vitest)
```

## How it works

- **The browser never sees tokens.** `/api/auth/*` route handlers sign in against the API and store the access and refresh tokens in httpOnly cookies. `/api/rms/*` proxies every API call and adds `Authorization: Bearer`. The live SSE stream (`/api/events`) goes through the same proxy. Because the server calls the API, no CORS change is needed.
- **Only `RECOVERY_EXECUTIVE` can sign in.** The login route enforces this on the server side.
- **One device at a time, as in the app.** The server's existing single-device rule covers the web too: signing in on the web signs the RE out of the mobile app, and vice versa. Like the app, the browser compares the `sessionVersion` in a `session-revoked` push with its own token's so it never signs itself out on its own login's echo.
- **Figures match the mobile app.** `src/lib/selectors.ts` ports the RE getters from `lib/v2/stores/app_store.dart` and the task builder from `re_tasks_screen.dart`. Change both together.
- **Every write sends an `X-Idempotency-Key`.** Commands show their outcome as a toast and refresh the data. Other open clients update through SSE.

## Deploy (Vercel)

1. Put the API behind HTTPS, for example nginx with Let's Encrypt on the API host. SSE needs `proxy_buffering off`.
2. Create a Vercel project with **Root Directory = `re-web`** and set `RMS_API_URL` to the HTTPS API URL.
3. Uploads go through the proxy, so a single attachment must stay under Vercel's 4.5 MB request-body limit.
