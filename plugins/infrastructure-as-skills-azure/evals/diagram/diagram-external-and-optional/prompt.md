---
description: An API that calls an external service and signs users in through Entra ID, with one optional component. Tests that outside parties become external actors in wiring.access and that "optional" is recorded as such.
expected_outcome: infra/infra-spec.yaml with wiring.access lines to external:<graph> and external:<entra> actors, the cache listed under wiring.optional, no Terraform written.
tags: [terraform, development, diagram, wiring, external, optional]
plugins: ["../../.."]
runs: 3
max_turns: 80
timeout_seconds: 1200
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit]
---

Wir brauchen für die interne Termin-API in Terraform einen App Service. Die API ruft die
Microsoft Graph API (Microsoft 365) auf, und die Benutzer melden sich über Entra ID an. Dazu
ein Redis Cache für die Sitzungen - der ist optional, den wollen wir erst später. Zugriff nur
aus dem Firmennetz, Entwicklung, Region Germany West Central. Subscription und Resource Group
liefert die Pipeline.

Zum Ablauf: Es ist niemand da, der Rückfragen beantwortet. Was oben nicht steht, nimmst du
nicht an — Pflichtwerte ohne Antwort kommen als offene Punkte in die Spec, für alles andere
gelten die Defaults. Kein Diagramm und noch keinen IaC-Code — nur die Spec.
