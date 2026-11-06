/// In-app legal drafts. Mirrors docs/PRIVACY_POLICY.md and docs/TERMS.md.
/// DRAFT: not reviewed by a lawyer. Placeholders in [brackets] must be
/// completed by the operator before public release.
const legalVersion = '2026-10-draft';

const privacyPolicyText = '''
IronPulse Privacy Policy — DRAFT ($legalVersion)

This draft has not been reviewed by a lawyer. Bracketed items must be completed before public release.

1. Who we are
IronPulse is operated by [legal entity name], [registered address]. Contact: [privacy contact email]. Grievance officer (India, DPDP Act 2023): [name, contact].

2. What we collect
• Account: email address, sign-in method (email or Google), account identifiers.
• Profile you choose to give: display name, age range, height, weight, target weight, experience, goals, training days, gym time, equipment, dietary preferences, allergies, units, time zone.
• Training: workouts, exercises, sets, reps, weights, RPE, notes, workout splits and schedules.
• Nutrition & habits: meals and foods you log, nutrition targets, checklist items and completions.
• Body & goals: weight entries, fitness goals, optional progress photos.
• Health data (only if you connect Health Connect / Apple Health): daily steps, average heart rate, device-estimated active energy, workout minutes, sleep minutes.
• IronPulse AI: messages you send and the replies, plus only the data categories you enable in "What IronPulse AI can see".
• Technical: request logs (without passwords or tokens), error diagnostics, security audit events.
We do not collect precise location, contacts, or advertising identifiers, and we do not sell personal data.

3. Why we use it
To provide the app (tracking, history, analytics, reminders), to sync and back up your data across devices, to answer IronPulse AI requests you make, to keep the service secure, and to meet legal obligations. Your consent is the basis for processing optional and health data; you can withdraw it at any time in Settings.

4. Where it is stored
Data is stored on your device (private app storage) and, when you have an account, in our database and private file storage hosted by Supabase [region]. Progress photos are kept in a private storage folder that only your account can access. In device-only mode nothing leaves your phone.

5. AI processing
When you use IronPulse AI, your message and the data categories you enabled are sent from our server to [AI provider name] to generate a reply. The provider processes it under its API terms [link]. We do not send data categories you have not enabled. AI replies are general fitness information, not medical advice.

6. Health data
Health data is read only with your explicit platform permission, used only to show your activity in IronPulse, never used for advertising, never sold, and never shared with IronPulse AI unless you enable it. You can disconnect and delete imported health data at any time.

7. Third parties
Supabase (database, authentication, storage), Google (Sign-In, if used), [AI provider], [hosting provider for the API], Open Food Facts (food search queries you type are sent to their public API). See the third-party provider register.

8. Retention
We keep your data while your account is active. When you delete your account we delete your profile, training, nutrition, goals, photos, AI conversations and health data from our systems. A minimal, non-identifying deletion record (a one-way hash) is kept as proof of erasure. Backups are overwritten within [N] days.

9. Your rights
You can access and export your data (Settings › Export), correct it in the app, withdraw consent, and delete your account (Settings › Delete account). You may also contact us or our grievance officer, and lodge a complaint with the Data Protection Board of India or your local authority.

10. Children
IronPulse is not intended for anyone under 18.

11. Security
Data is encrypted in transit (HTTPS). Sessions are stored in the device keystore. Access is restricted per account on the server and by database row-level security.

12. Changes
We will notify you in the app of material changes.
''';

const termsText = '''
IronPulse Terms & Conditions — DRAFT ($legalVersion)

This draft has not been reviewed by a lawyer. Bracketed items must be completed before public release.

1. Agreement. By using IronPulse you agree to these terms. IronPulse is provided by [legal entity name].

2. Eligibility. You must be 18 or older.

3. Not medical advice. IronPulse and IronPulse AI provide general fitness information only. They do not diagnose, treat or prevent any condition and do not replace a doctor, physiotherapist or registered dietitian. Consult a qualified professional before starting a new programme, especially if you have a health condition, injury or are pregnant. Stop exercising and seek help if you feel pain, dizziness, chest pain or shortness of breath.

4. Train safely. Use appropriate weights, technique, spotters and safety equipment. You are responsible for how you train.

5. Estimates. Nutrition values, training volume, estimated one-rep maxes and device calorie figures are estimates and may be inaccurate.

6. Your content. You own the data you enter. You allow us to store and process it to provide the service, as described in the Privacy Policy.

7. Acceptable use. Do not misuse the service, attempt to access other users' data, overload the API or reverse-engineer security controls.

8. AI features. AI replies may be incomplete or wrong. Use your judgement. Usage limits apply.

9. Availability. The service is provided "as is". We may change or discontinue features. Offline data is stored on your device; keep your device secure.

10. Termination. You may delete your account at any time. We may suspend accounts that violate these terms.

11. Liability. To the extent permitted by law, [legal entity name] is not liable for indirect or consequential losses or injuries arising from training decisions.

12. Governing law. [Jurisdiction, e.g. the laws of India; courts of City].

13. Contact. [support contact email].
''';
