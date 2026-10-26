import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../data/account_repo.dart';
import '../logic/progress.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Set this before publishing. Shown in the Privacy Policy and Terms.
const contactEmail = 'YOUR-CONTACT-EMAIL@example.com';

// DRAFT legal text describing how this build actually behaves. Have it reviewed before public release.
const privacyPolicy = '''
_Draft · version $policyVersion · needs legal review before public release_

## Who we are
IronPulse is a fitness tracking app. Contact: $contactEmail

## What is stored, and where
**On your phone only** (in the app's private storage):
- Profile: display name, optional weight and height, experience, goal, weekly target
- Workouts: splits, exercises, sets, weights, reps, notes, XP, achievements
- Nutrition: foods and amounts you log, checklist items, targets
- Body: weigh-ins and goals
- Gym schedule and reminder settings
- IronPulse AI chat history
- Daily summaries imported from Health Connect (if you connect it)
- A record of the privacy choices below

**Accounts and cloud backup are optional.** Without an account, nothing is stored anywhere but your phone. If you sign in (email or Google) and back up, a copy of the data listed above (not access tokens) is stored in your private record in our database provider (Supabase), protected so only your account can read it. You can delete the backup and your login at any time (Account & backup → Delete my cloud account).

## Optional features and what leaves your phone
| Feature | Off by default? | What is sent | To whom |
|---|---|---|---|
| IronPulse AI | You choose to use it | The messages you type | Your IronPulse AI server, which forwards them to the configured AI provider (e.g. Groq, or Ollama on your own PC) |
| AI training summary | Yes | Goal, experience, split, weekly target, last 3 workouts (exercise, weight, reps) | Same as above, attached to each message |
| AI nutrition summary | Yes | 7-day average calories/protein, protein target | Same as above |
| Health Connect | Yes | Nothing leaves the phone - IronPulse only reads | - |
| Reminders | Yes | Nothing - scheduled locally by Android | - |
| Account & cloud backup | Yes | Email (or Google name/email), and your backup | Supabase (database/auth host); Google if you choose Google Sign-In |

Never sent: your name, weight history, checklist, food log details, health data, or chat history (the server keeps no history and does not log message content).

## Why we process it (legal basis)
- **To provide the app** (contract / your request): workout, nutrition and progress features.
- **Your consent**: AI data sharing, Health Connect, reminders. You can turn each off any time in the app; we keep a record of when you changed it (shown below).
Health information (weight, heart rate, sleep) is sensitive. It is only processed for features you turn on.

## How long we keep it
Data stays on your phone until you delete it. Cloud backups are kept until you delete your cloud account; we plan to delete backups of accounts inactive for 3 years. AI requests are not stored by the IronPulse server. AI providers handle requests under their own terms (for example, Groq's retention policy).

## Your rights
You can **see** all data in the app, **correct** it, **export** it (Settings → Export my data, JSON and CSV), **withdraw consent** for any optional feature, and **erase** everything (Settings → Delete all my data). Depending on where you live (for example India's Digital Personal Data Protection Act, 2023 or the EU GDPR) you may have further rights, including to complain to a data protection authority.

## Security
Data is kept in the app's private storage. Access tokens are stored in Android Keystore / iOS Keychain. Network traffic to the AI server uses HTTPS (except over your own USB cable). No system is perfectly secure.

## Children
IronPulse is not intended for anyone under 18.

## Changes
If this policy changes we will update the version above and show it in the app.
''';

const termsOfUse = '''
_Draft · version $policyVersion · needs legal review before public release_

## Using IronPulse
IronPulse helps you log workouts, nutrition and progress. By using it you agree to these terms.

## Not medical advice
IronPulse and IronPulse AI give **general fitness information only**. They are not a doctor, physiotherapist or dietitian and do not diagnose or treat anything. Check with a qualified professional before starting a new programme, diet or supplement, and **stop training and seek help if you feel pain, dizziness or chest discomfort**. Train with proper form and use spotters or safety equipment for heavy lifts.

## AI answers can be wrong
AI responses may be inaccurate or incomplete. Use your own judgement. Do not rely on them for medical, injury or safety decisions.

## Your responsibilities
Keep your phone and access tokens secure. Enter accurate information if you want accurate results. Do not misuse the AI service (for example automated or abusive requests); limits apply.

## Your content
Your workout and nutrition data belong to you. You can export or delete it at any time.

## Third-party services
Optional features rely on third parties (Android Health Connect, the AI provider you configure, the hosting service for the AI server). Their terms and availability apply, and they may change or stop.

## Availability
IronPulse is provided "as is", without warranties, and may change or be discontinued. To the extent permitted by law, the developer is not liable for indirect losses or for injuries resulting from training decisions. Nothing in these terms limits rights you have under consumer law.

## Contact
$contactEmail
''';

class LegalScreen extends StatelessWidget {
  final String title, body;
  const LegalScreen({super.key, required this.title, required this.body});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Markdown(
          data: body,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
            p: const TextStyle(height: 1.4, fontSize: 14),
            h2: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: IP.text),
            em: const TextStyle(color: IP.warning, fontStyle: FontStyle.italic),
            tableBorder: TableBorder.all(color: IP.border),
            tableBody: const TextStyle(fontSize: 12.5),
            tableHead: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
          ),
        ),
      );
}

class ConsentHistoryScreen extends StatelessWidget {
  const ConsentHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Your privacy choices')),
        body: Reloading<List<ConsentRecord>>(
          load: AccountRepo.consentHistory,
          builder: (context, list) => list.isEmpty
              ? const EmptyState(
                  icon: Icons.verified_user_outlined,
                  title: 'No optional features turned on',
                  body: 'When you switch on AI sharing, Health Connect or reminders, it is recorded here.')
              : ListView(padding: const EdgeInsets.all(16), children: [
                  const Muted('Every time you turn an optional feature on or off, IronPulse keeps a record here.'),
                  const SizedBox(height: 12),
                  for (final c in list)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(c.granted ? Icons.check_circle : Icons.cancel_outlined,
                          color: c.granted ? IP.success : IP.muted),
                      title: Text(consentLabels[c.purpose] ?? c.purpose),
                      subtitle: Text('${c.granted ? 'Turned on' : 'Turned off'} · ${fmtDate(c.at)} '
                          '${c.at.hour.toString().padLeft(2, '0')}:${c.at.minute.toString().padLeft(2, '0')} · policy ${c.version}'),
                    ),
                ]),
        ),
      );
}
