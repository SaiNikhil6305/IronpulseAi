# IronPulse - Security review & incident response

No system is completely secure. This documents the controls that exist, known gaps, and what to do if something goes wrong.

## 1. Architecture & trust boundaries
```
[Phone: Flutter app] --HTTPS + bearer token--> [Render: ai_server (FastAPI)] --HTTPS + API key--> [Groq]
      |  SQLite (app-private), Keystore tokens
      |--(read-only, Android permission)--> [Health Connect]
      |--(local alarms)--> [Android notification system]
```
Trust boundaries: phone ↔ AI server (token), AI server ↔ Groq (API key), app ↔ Health Connect (OS permission).

## 2. Controls in place (verified by tests where noted)
**App**
- Data in app-private storage (other apps cannot read it on a non-rooted phone).
- AI token stored with flutter_secure_storage (Android Keystore / iOS Keychain); excluded from exports (test).
- Network: HTTPS everywhere; plain HTTP allowed **only** to 127.0.0.1/localhost (network_security_config) for USB dev.
- XP ledger uses deterministic ids → no reward farming (tests).
- CSV export neutralises spreadsheet formulas (`=`, `+`, `-`, `@`) (test).
- Delete-all wipes DB, tokens, temp exports, reminders, Health Connect grant (test for DB + tokens).
- AI only receives opt-in summaries; never name, weights history, photos (test).
- Health data: read-only permissions; only daily summaries stored.

**AI server**
- Fails to start without a ≥24-char token; constant-time comparison (`hmac.compare_digest`) (tests).
- Validation: ≤20 messages, ≤4,000 chars each, last message must be user, context ≤4,000 (tests).
- 64 KB body limit → 413 (test). Rate limits 10/min, 200/day per token → 429 (test).
- Model timeout 90 s; provider errors mapped to safe messages (no stack traces) (tests).
- No request bodies, tokens or keys in logs (manual check + log format).
- Docker image runs as non-root; `.env` excluded from image and git (`.dockerignore`, `.gitignore`).
- Secrets only in Render environment variables; repo is private.

## 3. Known gaps / accepted risks
| Gap | Risk | Plan |
|---|---|---|
| One shared token, no per-user accounts | Anyone with the token can use your AI quota | Phase 9: Supabase Auth JWT per user |
| Rate limiter is in-memory | Resets on restart / doesn't span instances | Fine for 1 free instance; Redis if scaled |
| SQLite not encrypted at rest | Readable on a rooted/forensically imaged phone | Consider SQLCipher in Phase 9 |
| Prompt injection via user text | Model could ignore safety prompt | Low impact (single user, no tools); keep safety prompt, no tool access |
| Free Render plan | Cold starts, no SLA | Accept for personal use |
| No automated dependency audit yet | Vulnerable package goes unnoticed | Phase 9 CI: `flutter pub outdated`, `pip-audit`, Dependabot |
| Token history | An old token was briefly in a private repo commit (since force-pushed away) and in chat | Rotated - old token no longer valid |

## 4. Secrets handling rules
- Never commit `.env`; check `git status` before every push.
- Never paste keys/tokens into chats, issues or screenshots.
- Rotate immediately if exposed: **Groq key** (console.groq.com → API Keys), **IronPulse token**
  (generate new → Render → Environment → IRONPULSE_AI_TOKEN → app AI settings).

## 5. Incident response / breach procedure
1. **Detect** - unusual Groq usage, Render errors/traffic spikes, leaked secret found, lost phone with exports.
2. **Contain (first hour)** - rotate the Groq key and IronPulse token; suspend the Render service if abuse continues;
   make the repo private / remove leaked files and force-push.
3. **Preserve evidence** - screenshot Groq usage and Render logs, note times (IST), keep a timeline.
4. **Investigate** - what leaked, since when, whose data. Today the server stores no personal data,
   so a server compromise exposes at most in-flight AI messages.
5. **Assess impact** - which users and data categories; health data = high sensitivity.
6. **Notify** - once others use the app and DPDP Rules apply (from 13 May 2027): inform the Data Protection
   Board of India without delay, a detailed report within 72 hours, and affected users promptly.
   GDPR (if EU users): supervisory authority within 72 hours.
7. **Recover** - redeploy from a clean commit with new secrets; confirm health check and app connection.
8. **Review** - write down cause and fixes; update this document.

## 6. Security checklist before public release
- [ ] Per-user auth on the AI server (Phase 9)
- [ ] CI with tests + dependency audit on every push
- [ ] Release signing key generated, backed up offline, never committed
- [ ] Error tracking with PII scrubbing (e.g. self-hosted GlitchTip)
- [ ] Re-run this review after Phase 9
