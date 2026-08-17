# CueFlow 1.0 — Release Readiness

This file separates work the repository can verify from work that requires a physical device, native speakers, an Apple account, or real learners.

## App Store positioning

**Name:** CueFlow  
**Subtitle:** Russisch & Arabisch sprechen  
**Primary category:** Education  
**Secondary category:** Productivity  

**Promotional text**

Lerne nützliche Ausdrücke so, wie du sie im Gespräch brauchst: vom deutschen Gedanken zur gesprochenen russischen oder arabischen Antwort.

**Short description**

CueFlow ist ein privater Sprachtrainer für deutsche Muttersprachler:innen. Statt nur Übersetzungen wiederzuerkennen, rufst du russische und arabische Ausdrücke selbst ab, sprichst sie laut und setzt sie in kurzen Alltagssituationen ein.

**Full description draft**

CueFlow trainiert die Richtung, die beim Sprechen zählt: Du siehst, was du auf Deutsch ausdrücken möchtest, erinnerst dich an die russische oder arabische Formulierung und sagst sie selbst.

Kurze, adaptive Einheiten kombinieren Auswahlaufgaben, Wortbausteine, Tippen und Sprechen. Mit zunehmender Sicherheit verschwinden die Hilfen. Schwierige Ausdrücke kehren gezielt zurück, während der FSRS-Lernplan deine Wiederholungen sinnvoll verteilt.

Für mehr Sprechpraxis gibt es einen 60-Sekunden-Sprint und kurze Rollenspiele mit deinen aktuellen Ausdrücken. Praktische Missionen wie Begrüßung, Café oder Unterwegs helfen dir, Sätze zu lernen, die du sofort verwenden kannst.

CueFlow enthält Starter-Inhalte für Russisch und Arabisch. Eigene Phrasen, Tutor-Unterlagen und Themen kannst du ergänzen und in einer Qualitätsprüfung verwalten.

Dein Fortschritt zeigt echte Lernsignale: erfolgreiche Abrufe, gesprochene Wörter, flüssigere Antworten und Ausdrücke, die nach Fehlern wieder sicher werden. Es gibt keine Herzen, Energiegrenzen, Ranglisten oder Streak-Drohungen.

Deine Lerndaten bleiben bei dir. Spracherkennung, Bewertung und optionale KI-Unterstützung laufen auf dem Gerät. CueFlow verwendet kein Werbe-Tracking und keine serverseitige Verhaltensanalyse. iCloud-Synchronisierung ist optional; vollständige Sicherungen lassen sich exportieren und wiederherstellen.

## Keywords

`Russisch lernen, Arabisch lernen, sprechen, Vokabeltrainer, Aussprache, Karteikarten, FSRS, Sprachtrainer, offline`

## Screenshot story

Capture from the exact release candidate with realistic but non-personal sample data. Keep text readable without compositing claims the screen does not substantiate.

1. **Heute:** “Heute wirklich sprechen” — recommended session and productive goals.
2. **Speaking prompt:** “Vom deutschen Gedanken zur eigenen Antwort.”
3. **Useful correction:** “Sofort verstehen, was noch fehlt.”
4. **Real-world missions:** “Ausdrücke für Café, Reise und Alltag.”
5. **Sprint:** “60 Sekunden Sprechfluss.”
6. **Conversation:** “Kurze Rollenspiele mit deinem Wortschatz.”
7. **Progress:** “Sieh, was du selbst abrufen kannst.”
8. **Arabic:** “Arabische Schrift, RTL und Lautschrift.”
9. **Privacy/backup:** “Auf dem Gerät. Sicherbar. Ohne Tracking.”

Required captures should follow the currently requested App Store Connect device classes rather than relying on hard-coded historical dimensions. At minimum, capture the largest required iPhone class and iPad class; let App Store Connect scale only where Apple permits it.

## Privacy policy draft

Publish this text at a stable HTTPS URL and replace the bracketed contact address before submission.

### Datenschutz bei CueFlow

CueFlow erhebt keine personenbezogenen Daten für Werbung, Tracking oder serverseitige Analyse. Es gibt kein CueFlow-Konto und keinen CueFlow-Server.

Lerninhalte, Lernfortschritt und Einstellungen werden mit SwiftData auf dem Gerät gespeichert. Wenn iCloud verfügbar und für CueFlow aktiviert ist, kann Apple CloudKit diese Daten über die private iCloud-Datenbank des verwendeten Apple-Accounts zwischen Geräten synchronisieren. Für die Verarbeitung durch Apple gelten die Datenschutzbestimmungen und iCloud-Einstellungen von Apple.

Spracherkennung wird nur nach ausdrücklicher Freigabe verwendet. CueFlow verlangt die Verarbeitung auf dem Gerät; ist das benötigte lokale Sprachmodell nicht verfügbar, wird nicht automatisch auf einen CueFlow- oder Drittanbieter-Server ausgewichen. Die optionale Apple-Intelligence-Unterstützung ist nur auf kompatiblen Geräten verfügbar und verwendet Apples System-Framework.

CueFlow verwendet MetricKit, um von iOS bereitgestellte technische Diagnoseberichte lokal zu empfangen. Ein Problembericht wird nur durch eine bewusste Freigabeaktion des Nutzers geteilt und enthält keine Phrasen, Antworten oder Lerninhalte.

Benachrichtigungen sind optional und werden lokal geplant. Vollständige Sicherungen werden nur auf ausdrückliche Aktion exportiert. CueFlow enthält keine Werbung, keine Drittanbieter-Analytics und kein Cross-App-Tracking.

Fragen zum Datenschutz: [SUPPORT-EMAIL]

## Automated gates

- [x] project generation succeeds from `project.yml`;
- [x] app and widget compile on the iOS 26.5 simulator SDK;
- [x] unit tests cover core domain and persistence behavior;
- [x] UI smoke tests cover the primary session, tabs, large accessibility text, Arabic configuration, guided role-play entry, and landscape reachability;
- [x] clean iPad Pro 13-inch startup and adaptive sidebar layout are visually checked with native multitasking/orientation declarations;
- [x] clean startup and additive model migration are smoke-tested over existing simulator data;
- [x] privacy manifest, microphone and speech usage descriptions, URL scheme, App Group, iCloud, and widget entitlements exist;
- [x] complete versioned backup and merge restore exist;
- [x] startup falls back safely when iCloud or persistent storage is unavailable.

## Physical-device matrix

Run every row on the release archive, recording device, OS, result, and issue link.

| Area | Required checks |
|---|---|
| Russian speech | permission allow/deny, offline model present/missing, partial result, silence, retry, background interruption |
| Arabic speech | same lifecycle, canonical Arabic output, RTL, transliteration, dialect limitations communicated |
| Audio | silent switch, speaker, wired/Bluetooth route, incoming call, TTS after recording, completion chime toggle |
| Persistence | force quit during practice, low storage, offline launch, iCloud sign-out, second-device merge, backup round trip |
| Accessibility | VoiceOver order/actions, XXL text, Bold Text, Increase Contrast, Reduce Motion, Switch Control, landscape/iPad keyboard |
| Widgets | small/medium/Lock Screen, stale timeline, language switch, deep link, zero-due state |
| Performance | cold launch, seeded-library scrolling, memory during long session, MetricKit delivery after crash/hang simulation |

## Content and beta gates

- [ ] native Russian review of every bundled A1 item, example sentence, register, stress/transliteration, and TTS pronunciation;
- [ ] native Arabic review of every bundled A1 item, script, transliteration, register, dialect labeling, accepted alternatives, and TTS pronunciation;
- [ ] 5–15 external beta learners complete onboarding and at least three sessions;
- [ ] observe permission-fallback comprehension, session completion, voluntary repeat, difficult-item recovery, and conversation usefulness;
- [ ] resolve every crash, data-loss, inaccessible-primary-action, or misleading-feedback issue;
- [ ] support email monitored and privacy-policy URL published;
- [ ] App Store privacy nutrition labels answered consistently with the binary and policy;
- [ ] final screenshots, age rating, content rights, export compliance, review notes, and demo instructions completed in App Store Connect.

## Review notes draft

CueFlow does not require an account. On first launch, select Russian or Arabic and complete or skip the guided speaking step. Microphone and speech permissions are requested only when a speaking action begins; all other practice remains usable if permission is denied. Apple Intelligence grading and conversation require a compatible device and degrade gracefully when unavailable. The app contains no purchases or gated practice.
