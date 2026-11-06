# Privacy & compliance preparation

> IronPulse is **not** claimed to be legally compliant. This document maps the technical features to likely
> requirements so a lawyer can review them. Policies in `PRIVACY_POLICY.md` / `TERMS.md` are drafts with
> placeholders and have not been professionally reviewed.

## Data inventory

| Category | Fields | Purpose | Where | Shared with |
|---|---|---|---|---|
| Account | email, auth ids, Google sign-in link | Sign-in, sync | Supabase Auth | Google (if used) |
| Profile | name, age range, height, weight, goals, equipment, diet, allergies, units, time zone | Personalisation, charts | Device, Postgres | AI provider only for scopes the user enables |
| Training | sessions, sets, notes, splits, schedule | Core features, XP | Device, Postgres | AI (opt-in scope) |
| Nutrition & checklist | meals, foods, targets, completions | Tracking | Device, Postgres | AI (opt-in); food search terms → Open Food Facts |
| Body & goals | weight, goals, progress photos | Progress | Device, Postgres, private Storage | — |
| Health (wearables) | steps, avg HR, device kcal, workout & sleep minutes (daily) | Activity view | Device, Postgres | — |
| AI chats | messages & replies | Assistant | Postgres; provider processes | AI provider |
| Technical | request logs (no tokens/bodies), audit events (hashed user id) | Security, debugging | Logs, Postgres | Hosting provider |

Not collected: precise location, contacts, advertising id, payment data. No ads, no data sale, no tracking SDKs.

## Technical privacy features (implemented)

* Consent: Terms/Privacy acceptance at sign-up recorded in `consent_records` (versioned).
* Data minimisation: optional onboarding fields can be skipped; AI context sharing **off by default**, per
  category, explained in-app; health access read-only and per-type through the OS dialog.
* Access & portability: Settings → Export (full JSON from the server + CSV of sets); device-only JSON export.
* Correction: all profile/onboarding data editable.
* Erasure: Settings → Delete account (server cascade, storage, auth user) / Erase device data; AI conversations
  individually deletable; photos deletable; wearable disconnect with optional data deletion.
* Security: see SECURITY.md. Android backups of app data disabled.
* In-app Privacy Policy and Terms screens; public page `docs/public/privacy.html`.

## India — Digital Personal Data Protection Act 2023 & DPDP Rules 2025

The Rules were notified on 13 Nov 2025. Board provisions applied immediately; consent-manager rules from
13 Nov 2026; core obligations (notice & consent, security safeguards, breach notification, retention, children,
data-principal rights, DPO contact) from **13 May 2027**. Assessment:

| Requirement | Status in IronPulse | To do |
|---|---|---|
| Itemised notice in clear language with purposes | Draft policy + in-app explanations at onboarding, AI sharing and health permissions | Lawyer review; add English + Hindi/other languages if serving those users |
| Free, specific, informed consent; withdrawal as easy as giving it | Sign-up acceptance; AI scopes & health toggles; withdrawal in Settings | Consider a dedicated consent screen listing purposes; record AI/health consents in `consent_records` |
| Reasonable security safeguards (encryption, access control, logs, backups) | TLS, keystore, RLS, per-user authz, audit log | Encryption at rest is provided by Supabase; document; keep access logs ≥ 1 year |
| Breach notification: Board without delay + detailed report within 72 h; inform users | Procedure in INCIDENT_RESPONSE.md | Name owners; rehearse |
| Retention: erase when purpose served; keep logs/traffic data ≥ 1 year | Data kept while account active; deletion on request | Define inactive-account policy; implement 1-year log retention and purge |
| Data principal rights: access, correction, erasure, grievance, nominee | Export, edit, delete in-app | Publish grievance contact & response time; nominee process |
| Children (< 18): verifiable parental consent | App limited to 18+ in Terms and onboarding age ranges | Add an explicit age gate if required |
| Contact of DPO/grievance officer | Placeholder | Fill in |
| Significant Data Fiduciary duties | Unlikely at launch scale | Re-assess on growth |
| Cross-border transfer | Supabase region / AI provider may be outside India | Choose regions; disclose; monitor government notifications |

Health and fitness data is personal data under the DPDP Act (no separate "sensitive" category), but treat it
as high-risk: Google Play and Apple impose specific health-data rules (below).

## Platform requirements

* **Google Play:** Data safety form (health & fitness, personal info, photos, app activity, messages[AI]);
  account deletion must be available in-app **and** via a web link — host a deletion request page or email
  [to be provided]. Health Connect permission declaration + privacy policy linked from the permissions screen
  (implemented via manifest activity-alias).
* **Apple:** App Privacy labels; HealthKit usage descriptions (added); HealthKit data not for ads; in-app
  account deletion (implemented); Sign in with Apple required alongside Google (not yet implemented).
* **Subscriptions:** none. If added, use Google Play Billing / StoreKit and disclose price & renewal terms.

## Other jurisdictions

If you accept EU/UK users, GDPR applies (lawful basis, explicit consent for health data, DPIA, DPA with
processors, 72-hour breach notice). US state health-privacy laws (e.g. Washington My Health My Data) may apply
to consumer health data — get advice before launching there.

## Brand & assets

Check trademark availability for "IronPulse" in your markets before commercial launch. Icon and exercise
instructions are original; no third-party exercise media or fonts are bundled.

## Retention policy (draft)

| Data | Retention |
|---|---|
| Account data | Until the user deletes the account (or [N] months of inactivity after notice — define) |
| AI conversations | Until deleted by the user or account deletion |
| Imported health data | Until disconnected-with-delete or account deletion |
| Request logs / audit events | 1 year, then purged |
| Deletion proof records | Indefinitely (hash only, no personal data) |
| Backups | Provider rotation window ([7–30] days) |

## Account deletion procedure

1. User: Settings → Delete account → type DELETE.
2. Server records an `account_deletion_requests` row (sha256 of user id).
3. Deletes progress-photo objects, all database rows (cascade) and the Supabase auth user.
4. Status `completed` or `partial` (with a note: e.g. storage call failed) — operator checks `partial` rows
   daily and completes manually.
5. App wipes local data and notifications and returns to sign-in.
6. Data in backups expires with the backup window.
