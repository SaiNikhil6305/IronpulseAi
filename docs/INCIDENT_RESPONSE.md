# Security incident response procedure (draft)

Owner: [security contact — to be named]. Keep this list current.

1. **Detect & record.** Open an incident log (time, reporter, what was observed). Preserve logs; do not delete
   evidence.
2. **Contain.** Depending on the issue: rotate the Supabase service-role key, JWT signing keys and AI key;
   revoke sessions (Supabase → Auth → sign out users); disable the affected endpoint or put the API in
   maintenance; block abusive accounts/IPs.
3. **Assess.** Which data, how many users, which time window, still ongoing? Use `security_audit_events`,
   API logs (request ids) and Supabase logs.
4. **Notify (personal-data breach).**
   * **India (DPDP Act 2023 & DPDP Rules 2025):** inform the Data Protection Board without delay and send a
     detailed report within 72 hours (extensions on request); inform affected users promptly in plain language
     (what happened, likely impact, what they should do, contact). These Rules apply from 13 May 2027 — follow
     them now as good practice and confirm current requirements with counsel.
   * Other jurisdictions where you have users (e.g. GDPR: supervisory authority within 72 hours).
   * Google Play / Apple if their policies require it (e.g. health data incidents).
5. **Eradicate & recover.** Fix the root cause, deploy, restore from backups if needed, verify.
6. **Review.** Post-incident review within 2 weeks: timeline, root cause, actions, owners.

Contacts to fill in: hosting provider, Supabase support, AI provider, legal counsel, grievance officer.
