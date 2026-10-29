# TP-RMS Recovery Control (RE web dashboard)

Desktop web dashboard for the **Recovery Executive** role. It runs against the same Express API as the mobile apps (`../server`), so it uses the same logins and the same live data.

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
- **Web logins are a separate session channel.** The login sends `client: "web"` (server migration `040_web_session_channel.sql`). Signing in on the web does not sign the RE out of the mobile app, and signing in on the phone does not sign them out of the web dashboard.
- **Figures match the mobile app.** `src/lib/selectors.ts` ports the RE getters from `lib/v2/stores/app_store.dart` and the task builder from `re_tasks_screen.dart`. Change both together.
- **Every write sends an `X-Idempotency-Key`.** Commands show their outcome as a toast and refresh the data. Other open clients update through SSE.

## Deploy (Vercel)

1. Deploy the server first and run `npm run migrate` in `../server` so migration 040 is applied. Until then, a web login bumps the mobile session and signs the user out of their phone.
2. Put the API behind HTTPS, for example nginx with Let's Encrypt on the API host. SSE needs `proxy_buffering off`.
3. Create a Vercel project with **Root Directory = `re-web`** and set `RMS_API_URL` to the HTTPS API URL.
4. Uploads go through the proxy, so a single attachment must stay under Vercel's 4.5 MB request-body limit.
