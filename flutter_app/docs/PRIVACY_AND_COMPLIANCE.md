# IronPulse - Privacy & compliance assessment

Status: **engineering assessment, not legal advice.** Have a lawyer review before public release.
Policy version in the app: `2026-10-26` (`lib/data/account_repo.dart → policyVersion`).

## 1. Current situation (what the law sees today)
| Fact | Today |
|---|---|
| Who uses it | The developer (personal use), installed by USB / APK. Not on any store. |
| Where data lives | Only on the phone (SQLite in app-private storage, tokens in Android Keystore). |
| Accounts / cloud sync | None yet (Phase 9). The developer cannot access any user's data. |
| Data leaving the phone | Only IronPulse AI messages (+ optional summaries) → developer's Render server → Groq. |
| Sensitive categories | Health-related: weight, heart rate, sleep, nutrition. Treated as sensitive. |

Most obligations below start to bite when **other people** use the app (Play Store release, sharing the APK).
Building them now means the release is not blocked later.

## 2. Which laws apply
| Law | Applies? | Why |
|---|---|---|
| India - Digital Personal Data Protection Act 2023 + DPDP Rules 2025 | **Yes, once others use it.** Developer and likely users are in India. | Rules notified 13 Nov 2025. Board provisions in force now; consent-manager rules from 13 Nov 2026; notice/consent, security, breach, retention, rights, children from **13 May 2027**. |
| EU/UK GDPR | Only if offered to people in the EU/UK. | Health data = special category (Art. 9) → explicit consent. Not targeted today. |
| Google Play policies (Health Connect, User Data, Health apps declaration) | **Yes, at Play Store release.** | Health Connect permissions need a declaration + privacy policy URL; Data Safety form. |
| Cookie rules | No. | No web pages or tracking. Native app has no cookies; no banner added (by design). |
| Payments / subscriptions | No. | App is free; no payment screens exist. |

## 3. Purposes and lawful basis (DPDP: consent or "legitimate uses"; GDPR mapping in brackets)
| Purpose | Data | Basis | Can be refused? |
|---|---|---|---|
| Core logging (workouts, nutrition, weight, goals) | Data the user enters | Provided at user request, stored only on device [GDPR: contract; Art 9(2)(a) explicit consent for health] | Yes - don't log it |
| AI chat | Typed messages | Consent by using the feature | Yes - feature is optional |
| AI training / nutrition summary | Summary listed in the app | **Separate, explicit opt-in**, each switch separate, off by default | Yes |
| Health Connect import | Steps, HR, resting HR, sleep | **Explicit opt-in** via Android permission screen | Yes; Disconnect deletes imports |
| Reminders | Schedule (local) | Opt-in + Android notification permission | Yes |
| Marketing | - | **Not done.** No email list, no ads, no analytics SDK. | n/a |

No purposes are bundled: each optional feature has its own switch (DPDP Rule 3 / GDPR Art 7).

## 4. Consent records
`consent_records` table: purpose, on/off, policy version, timestamp; append-only; visible in
**Settings → Your privacy choices**; included in the export. Withdrawal is one tap (same place it was given).

## 5. User rights - how each is met
| Right | Implementation |
|---|---|
| Notice | In-app Privacy Policy (Settings), plain language, table of what is sent where |
| Access / portability | **Export my data**: full JSON + CSV (workouts, food, weight) via Android share sheet |
| Correction | Every record is editable in the app |
| Erasure | **Delete all my data** (type DELETE): drops database, secure-storage tokens, export temp files, cancels reminders, revokes Health Connect. Disconnecting Health Connect deletes imported health rows. AI chats deletable individually or all. |
| Withdraw consent | Each switch, any time; recorded |
| Grievance | Contact email in policy - **set `contactEmail` in `lib/screens/legal.dart` before release** |

## 6. Retention
| Data | Retention today | Note for Phase 9 (cloud) |
|---|---|---|
| All on-device data | Until the user deletes it / uninstalls | Server copies: delete on account deletion; DPDP 3-year inactivity cap only for very large platforms - still adopt "delete after 3 years inactive" |
| AI requests | Not stored by IronPulse server; access log has path/status/latency only | Groq: check current retention terms; prefer zero-retention settings if offered |
| Security logs (server) | Render platform log retention | DPDP Rules require keeping certain logs ≥ 1 year once in force - configure log export then |
| Exports | Temp folder, overwritten each export, removed on delete-all | - |
| Progress photos | Not implemented (no photo storage exists) | If added: private bucket, deleted with account |
| Payment records | None | - |

## 7. Children
App targets adults (stated in policy and terms). No age gate yet. Before public release under DPDP
(from 13 May 2027), add an 18+ declaration at onboarding; verifiable parental consent would be needed to serve minors.

## 8. Before public release - checklist
- [ ] Set `contactEmail` (and a grievance contact) in `lib/screens/legal.dart`
- [ ] Host the privacy policy at a public URL (required by Play + Health Connect declaration)
- [ ] Legal review of the Privacy Policy and Terms drafts
- [ ] Play Console: Data Safety form, Health apps declaration, Health Connect permissions declaration
- [ ] Add 18+ confirmation to onboarding
- [ ] Check name "IronPulse" for trademark conflicts in India (IP India search) and on Play
- [ ] Sign/accept DPAs: Groq, Render (see THIRD_PARTY_SERVICES.md)
- [ ] Re-run this assessment when Phase 9 adds accounts + cloud storage (developer then holds user data)

Sources: DPDP Rules 2025 commencement and breach/retention summary - Hogan Lovells (Nov 2025);
EY / KPMG DPDP Rules guidance (Nov 2025).
