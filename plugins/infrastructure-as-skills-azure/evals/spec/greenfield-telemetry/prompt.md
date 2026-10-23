---
description: A self-contained staging deployment in Bicep - own vnet, own workspace, private storage. Tests that every resource routes, that given ranges are carried exactly, and that a stated retention overrides the default.
expected_outcome: infra/infra-spec.yaml targeting bicep with three resources (virtual-network, log-analytics-workspace, storage-account), the stated ranges and 90-day retention; no Bicep written.
tags: [bicep, staging, private, create, multi-resource]
plugins: ["../../.."]
runs: 3
max_turns: 100
timeout_seconds: 1500
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit]
---

Neues Projekt "telemetry", bitte in Bicep. Staging-Umgebung in Germany West Central,
Subscription aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee, Resource Group rg-telemetry-stg-gwc.

Wir bauen alles selbst, es gibt noch nichts: ein eigenes VNet mit 10.20.0.0/16, darin das
Subnet für Private Endpoints mit 10.20.1.0/27 und ein App-Subnet snet-app mit
10.20.2.0/24. Dazu ein eigener Log Analytics Workspace, Logs 90 Tage aufbewahren. Und ein
Storage Account für die Rohdaten, nur privat erreichbar.

Zum Ablauf: Es ist niemand da, der Rückfragen beantwortet. Was oben nicht steht, nimmst du
nicht an — Pflichtwerte ohne Antwort kommen als offene Punkte in die Spec, für alles andere
gelten die Defaults. Kein Diagramm und noch keinen IaC-Code — nur die Spec.
