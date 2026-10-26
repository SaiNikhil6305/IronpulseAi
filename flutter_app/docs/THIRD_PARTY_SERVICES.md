# IronPulse - Third-party processor register

"DPA" = data processing agreement. **None are signed yet** - accept/sign the provider's standard DPA before
other people use the app.

| Service | Role | Data it receives | When | Location | DPA status |
|---|---|---|---|---|---|
| **Groq** (api.groq.com) | AI model provider | User's AI messages; optional training/nutrition summary | Only when user sends an AI message | US (check current terms) | Not signed - review Groq terms & data retention |
| **Render** (render.com) | Hosts the IronPulse AI server | Same as above in transit; access logs (path, status, latency, IP) | Each AI request | Region chosen at deploy | Not signed - Render DPA available in dashboard/legal |
| **GitHub** | Source code hosting (private repo) | Code only - no user data, no secrets | Development | US | n/a (no personal data) |
| **Google Health Connect** | On-device health data hub | Nothing sent off-device by IronPulse; IronPulse reads from it | When user connects | On the phone | n/a (on-device, governed by Google/Android terms) |
| **Android notifications** | Local reminders | Nothing leaves the phone | - | On the phone | n/a |
| **Ollama** (optional, local) | Local AI model on the user's own PC | AI messages, never leave the PC | If user picks local mode | User's PC | n/a |

Not used: analytics SDKs, advertising SDKs, crash reporters, email services, payment providers, push-notification
servers. (Add each here, with data categories, before introducing it.)

## Planned (Phase 9)
| Service | Role | Data | DPA |
|---|---|---|---|
| Supabase | Auth + Postgres backup/sync + private storage | Account email, all synced fitness data | Sign Supabase DPA; choose Mumbai (ap-south-1) region if available |
| Google Sign-In | Authentication | Email, name, Google account id | Google API terms |
