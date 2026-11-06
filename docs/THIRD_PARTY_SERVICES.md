# Third-party provider register

| Provider | Purpose | Data shared | Where configured | Status |
|---|---|---|---|---|
| Supabase | Auth, PostgreSQL, private storage | All account data, photos | `SUPABASE_URL`, keys | Integrated; needs a project |
| Google Identity (Sign-In) | Optional sign-in | Google account id, email, name | OAuth clients | Integrated; needs OAuth setup |
| AI provider (Anthropic or OpenAI-compatible) | IronPulse AI answers | User message, recent chat turns, opted-in context | `AI_PROVIDER`, `AI_API_KEY`, `AI_MODEL`, `AI_BASE_URL` | Integrated; needs a key |
| Open Food Facts | Food search (public database) | Search text typed by the user (no account data) | Hard-coded public API | Integrated |
| Android Health Connect / Apple HealthKit | Read wearable data | Read on device only; daily aggregates synced to our backend | OS permissions | Health Connect integrated; HealthKit untested |
| API hosting (your choice: Render, Fly.io, Railway, Cloud Run, VPS) | Runs FastAPI | All API traffic | Deployment | To choose |
| GitHub / GitHub Actions | Source & CI | Source code, build artefacts | `.github/workflows/ci.yml` | Ready |
| Google Play / Apple App Store | Distribution | Store analytics per their terms | Consoles | Not set up |

For each provider before launch: sign the DPA/terms, record the data region, and list it in the privacy policy.
