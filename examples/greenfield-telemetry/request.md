# The request

Verbatim the eval prompt `evals/spec/greenfield-telemetry`, run headless: nobody answers
follow-up questions, unstated required values become `open:` entries, everything else
takes its default.

> Neues Projekt "telemetry", bitte in Bicep. Staging-Umgebung in Germany West Central,
> Subscription aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee, Resource Group rg-telemetry-stg-gwc.
>
> Wir bauen alles selbst, es gibt noch nichts: ein eigenes VNet mit 10.20.0.0/16, darin das
> Subnet für Private Endpoints mit 10.20.1.0/27 und ein App-Subnet snet-app mit
> 10.20.2.0/24. Dazu ein eigener Log Analytics Workspace, Logs 90 Tage aufbewahren. Und ein
> Storage Account für die Rohdaten, nur privat erreichbar.
>
> Zum Ablauf: Es ist niemand da, der Rückfragen beantwortet. Was oben nicht steht, nimmst du
> nicht an — Pflichtwerte ohne Antwort kommen als offene Punkte in die Spec, für alles andere
> gelten die Defaults. Kein Diagramm und noch keinen IaC-Code — nur die Spec.

The subscription id and every name in it are placeholders from the eval; nothing here has
been applied. "Es gibt noch nichts" describes the workload; nothing in the request names a
landing zone platform, so `landing_zone` takes its default, `standalone`, and the
deployment owns its network, its private DNS zone and its workspace.
