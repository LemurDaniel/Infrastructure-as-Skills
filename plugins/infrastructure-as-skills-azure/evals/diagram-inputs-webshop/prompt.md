---
description: Three resources whose calls the request names (web app reads storage, fetches secrets from the vault, staff reach the app from the company network). Tests that the spec records who reaches what - the input the diagram draws - exactly as stated.
expected_outcome: infra/infra-spec.yaml with wiring.access for the three named calls, a purpose for the storage account, private exposure and no call the request did not name; no Terraform written, no diagram drawn.
tags: [terraform, development, private, diagram, wiring]
plugins: ["../.."]
runs: 3
max_turns: 80
timeout_seconds: 1200
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit]
---

Wir bauen den Webshop "shopfront" in Terraform: eine Web-App (App Service) für die
Kundenbestellungen, ein Storage Account mit den Produktbildern und einen Key Vault für die
Secrets. Die Web-App liest die Produktbilder aus dem Storage und holt ihre Secrets aus dem
Key Vault. Die Mitarbeiter greifen nur aus dem Firmennetz auf die Web-App zu. Region
Germany West Central. Subscription und Resource Group liefert die Pipeline.

Zum Ablauf: Es ist niemand da, der Rückfragen beantwortet. Was oben nicht steht, nimmst du
nicht an — Pflichtwerte ohne Antwort kommen als offene Punkte in die Spec, für alles andere
gelten die Defaults. Kein Diagramm und noch keinen IaC-Code — nur die Spec.
