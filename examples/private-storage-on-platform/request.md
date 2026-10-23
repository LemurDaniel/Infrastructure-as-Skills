# The request

Verbatim the eval prompt `evals/spec/private-storage-on-platform`, run headless: nobody answers
follow-up questions, unstated required values become `open:` entries, everything else
takes its default.

> Wir brauchen für die Rechnungsablage der Buchhaltung einen Storage Account, in Terraform.
> Workload heißt "invoicing", Produktion, West Europe. Subscription
> 11111111-2222-3333-4444-555555555555, Resource Group rg-invoicing-prod-we.
>
> Zugriff nur aus dem Firmennetz: Es gibt ein bestehendes Hub-VNet vnet-hub-prod-we in der
> Resource Group rg-network-prod-we, die Private Endpoints kommen dort ins vorhandene Subnet
> snet-privatelink. Die Logs gehen in unseren zentralen Workspace log-platform-prod-we in
> rg-observability-prod-we. Wir unterliegen BSI C5.
>
> Zum Ablauf: Es ist niemand da, der Rückfragen beantwortet. Was oben nicht steht, nimmst du
> nicht an — Pflichtwerte ohne Antwort kommen als offene Punkte in die Spec, für alles andere
> gelten die Defaults. Kein Diagramm und noch keinen IaC-Code — nur die Spec.

The subscription id and every name in it are placeholders from the eval; nothing here has
been applied.
