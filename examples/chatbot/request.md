# The request

Written for this example: a RAG chatbot for employees, the "complex case" of the plugin - twelve
resource kinds, two of them twice, wired together. Its shape is that of a real internal assistant
(web front end, tool servers, document connector, sandboxed code execution, retrieval, models);
every name and number in it is a placeholder and nothing here has been applied. Run headless:
nobody answers follow-up questions, unstated required values become `open:` entries, everything
else takes its default.

> Wir bauen einen internen Chatbot für die Mitarbeitenden, in Terraform. Workload heißt
> "chatbot", nur Produktion (kein Stack aus Dev und Test), West Europe. Subscription
> 11111111-2222-3333-4444-555555555555, Resource Group rg-chatbot-prod-we.
>
> Architektur: eine Web-App (Frontend und Backend in einem, Python 3.12) auf einem App Service
> Plan, ein MCP-Server als eigene Web-App (Node 22-lts), eine Function App (Python 3.12) als
> Connector zu unserer Dokumentenablage, eine Container App, die den Code-Interpreter ausführt
> (Image code-runner:1.0.0 aus unserer Registry, Port 8080), die Modelle in Azure AI Foundry
> (Chat-Modell gpt-4.1, Version 2025-04-14, und Embeddings text-embedding-3-large, Version 1;
> ein Foundry-Projekt "chatbot"), die Suche über Azure AI Search, der Gesprächsverlauf in
> Cosmos DB (Datenbank "chatbot", Container "conversations", Partitionsschlüssel /userId),
> hochgeladene Dateien in einem Storage Account, die Function App legt ihren eigenen Zustand in
> einem zweiten Storage Account ab, Geheimnisse in einem Key Vault, die Images in einer Container
> Registry. Dazu Application Insights und ein eigener Log Analytics Workspace.
>
> Identitäten: Die Web-App und der MCP-Server teilen sich eine verwaltete Identität, der
> Connector und der Code-Interpreter haben je eine eigene. Zugriffe: Die Web-App-Identität ruft
> die Modelle auf, liest den Suchindex, liest und schreibt Gesprächsverlauf in Cosmos DB und die
> Uploads im Storage Account und liest Geheimnisse. Die Connector-Identität schreibt in den
> Suchindex, ruft die Embedding-Modelle auf, liest Geheimnisse und verwaltet den Zustand im
> eigenen Storage Account. Die Identität des Code-Interpreters zieht Images aus der Registry. Der
> Suchdienst liest die Uploads und ruft die Embedding-Modelle mit seiner eigenen Identität auf.
> Das Client-Secret der Entra-App-Registrierung soll als leerer Platzhalter im Key Vault liegen.
>
> Alles nur aus dem Firmennetz: wir sind in der internen Landing Zone (corp), das Netz ist ein
> Spoke, den Hub und die privaten DNS-Zonen betreibt die Plattform (Policy schreibt die Records).
> Eigenes VNet 10.20.0.0/16 mit diesen Subnetzen: snet-endpoints 10.20.0.0/27 (Private
> Endpoints), snet-web 10.20.0.64/26 und snet-mcp 10.20.0.128/26 (App-Service-Integration),
> snet-func 10.20.0.192/26 (Function App), snet-aca 10.20.1.0/27 (Container Apps). Eigener
> Workspace, 30 Tage Aufbewahrung.
>
> Die Daten dürfen nur in der EU verarbeitet werden. Die Anmeldung läuft über Entra ID; die App
> Registration legt das Identity-Team an, die kennen wir noch nicht.
>
> Zum Ablauf: Es ist niemand da, der Rückfragen beantwortet. Was oben nicht steht, nimmst du
> nicht an - Pflichtwerte ohne Antwort kommen als offene Punkte in die Spec, für alles andere
> gelten die Defaults. Kein Diagramm; Code in Terraform.
