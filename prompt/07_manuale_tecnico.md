# Fase 07: manuale tecnico e pacchetto di rilascio

Rileggi `CLAUDE.md`, `specifica/05_contesto_e_uso.md`, `docs/DECISIONI.md`, `docs/COLLAUDO.md` e l'help
effettivo dei due binari (`omi-import --help`, `omi-mcp --help`, `omi-mcp service --help`). Il manuale descrive
**il programma che esiste**, non quello previsto: ogni comando citato va provato (o, se richiede privilegi o
servizi che qui non ci sono, controllato contro l'help e gli script) e ogni opzione deve esistere davvero.

## 1. `docs/MANUALE_TECNICO.md`

In italiano, per un tecnico che non conosce il progetto. Tono asciutto, comandi in blocchi di codice pronti
da copiare, percorsi di esempio coerenti in tutto il documento (`C:\Program Files\OMIMyMCP`,
`C:\ProgramData\OMIMyMCP\omi.db`, porta 8765). Indice iniziale con collegamenti. Struttura obbligatoria:

1. **Introduzione**: cosa fanno `omi-import` e `omi-mcp`; schema dell'architettura (diagramma testuale
   ZIP → omi-import → omi.db → omi-mcp → [Caddy] → client MCP); avvertenze di `specifica/05` §1.
2. **Requisiti**
   - per l'esecuzione: Windows 10/11 o Windows Server 2016+ a 64 bit, nessun runtime da installare (CRT
     statico); spazio su disco (circa 2 GB di database per l'intera serie storica); una porta TCP libera;
   - per la compilazione: rustup e toolchain stabile MSVC, Visual Studio Build Tools con il carico di lavoro C++,
     Git; versione minima di Rust (`rust-version`).
3. **Compilazione**
   - installazione di rustup e dei Build Tools, con i comandi di verifica;
   - `cargo build --release --workspace` e posizione degli eseguibili;
   - test (`cargo test --workspace`) e lint;
   - compilazione per Linux (`x86_64-unknown-linux-gnu`);
   - creazione del pacchetto di rilascio (§2).
4. **Ottenere i dati OMI**: da `specifica/02` §1 (forniture `QI` e `QIP`, quali semestri, procedura di
   download, privacy del codice fiscale nei nomi dei file).
5. **Caricamento con `omi-import`**: sintassi, tabella dei parametri, primo caricamento, aggiunta di un
   semestre, ricaricamento e correzione (`specifica/02` §10), caratteri jolly, codici d'uscita, verifica con
   `sqlite3` (query di `specifica/01` §6 e `SELECT semestre, n_zone, n_valori, n_geometrie FROM semestre`), tempi
   indicativi (da `COLLAUDO.md`), caricamento con il server attivo.
6. **Esecuzione di `omi-mcp` da riga di comando**: sintassi, tabella completa delle opzioni, esempi (solo locale,
   LAN, dietro Caddy, con token, con log), formato del log, arresto.
7. **Installazione come servizio Windows**
   - installazione rapida con `deploy\windows\install.ps1` (esempio completo);
   - installazione manuale con `omi-mcp service install` (tutte le opzioni spiegate);
   - account del servizio e permessi sulla cartella dei dati (perché servono con il journal WAL);
   - firewall;
   - gestione: `start`, `stop`, `status`, `services.msc`, `sc.exe query OMIMyMCP`, dove trovare i log;
   - aggiornamento dei dati con `aggiorna-dati.ps1`;
   - aggiornamento dei binari (ferma → sostituisci → avvia; quando serve reinstallare).
8. **Esposizione HTTPS con Caddy**: quando serve, prerequisiti di rete (DNS, porte 80/443, NAT),
   `install-caddy.ps1`, Caddyfile commentato, verifica, rinnovo dei certificati, alternativa con tunnel cloudflared.
9. **Uso del server MCP da Claude** (capitolo obbligatorio e dettagliato, da `specifica/05` §2–§4). Per
   ciascun client, cioè **claude.ai** (web, app desktop e mobile), **Cowork**, **Claude Desktop** con server locale
   (`mcp-remote`) e **Claude Code**, il manuale deve spiegare passo per passo:
   - prerequisiti (server avviato, URL raggiungibile, HTTPS dove serve, token se attivo);
   - come aggiungere il server, con i comandi o i file di configurazione completi, anche nella variante con token;
   - come attivarlo in una conversazione e come verificare che funzioni (domanda di prova, per esempio "Quali
     semestri OMI sono caricati?", che deve far chiamare `elenco_semestri`; in Claude Code anche il comando `/mcp`);
   - come gestire i permessi di chiamata dei tool (approvazione singola o permanente);
   - come rimuoverlo;
   - i problemi tipici di quel client (connettore che non si collega, server non elencato, errori di autenticazione).

   Il capitolo prosegue con: come formulare le domande per ottenere risposte affidabili (comune e provincia,
   semestre esplicito, coordinate invece di indirizzi, citazione della fonte), un percorso guidato con 5–6 domande
   d'esempio di difficoltà crescente (dalla singola zona alla serie storica con grafico o foglio di calcolo, con lo
   strumento che Claude userà e cosa aspettarsi nella risposta), l'uso combinato con MCP Cruscotto Italia per
   ricavare le coordinate da un indirizzo e incrociare altri dati comunali, e la prova degli strumenti senza Claude
   con MCP Inspector (`npx @modelcontextprotocol/inspector`). Prima di scrivere il capitolo verifica sulla
   documentazione Anthropic corrente (support.claude.com e code.claude.com) i nomi dei menu, i comandi e le
   opzioni di autenticazione dei connettori personalizzati, e indica la data della verifica.
10. **Strumenti MCP**: tabella dei 9 strumenti con parametri, un esempio di chiamata e di risposta abbreviata per
    ciascuno (presi dai test golden), formato del semestre, comportamento con i semestri senza perimetri, esempi
    di domande di `specifica/05` §4.
11. **Struttura del database**: tabelle, codifica delle geometrie, query di esempio.
12. **Sicurezza**: superficie esposta, sola lettura, token, `--bind`, restrizione IP in Caddy, privacy del log (IP
    dei client), condizioni d'uso dei dati OMI quando il server è esposto a terzi.
13. **Disinstallazione**, completa e verificabile:
    - con gli script: `uninstall.ps1 [-RemoveCaddy] [-RemoveData]`;
    - manuale, passo per passo: `omi-mcp service uninstall` → `sc.exe stop caddy` e `sc.exe delete caddy` →
      `netsh advfirewall firewall delete rule name=…` (OMIMyMCP, 80, 443) → rimozione delle voci del `PATH` →
      eliminazione di `C:\Program Files\OMIMyMCP`, `C:\Program Files\Caddy` e `C:\ProgramData\Caddy` → eliminazione
      facoltativa dei dati in `C:\ProgramData\OMIMyMCP` → rimozione del connettore in claude.ai e `claude mcp remove omi`;
    - controlli finali: `sc.exe query OMIMyMCP` (servizio inesistente), nessuna regola firewall rimasta, porta
      libera (`netstat -ano | findstr :8765`);
    - per lo sviluppo: `cargo clean` ed eventualmente `rustup self uninstall`.
14. **Risoluzione dei problemi**: tabella sintomo → causa → soluzione. Almeno: porta occupata; accesso negato
    durante l'installazione; il servizio parte e si ferma subito (database mancante, permessi, file `-shm`);
    `database is locked`; il connettore claude.ai non si collega (HTTPS, DNS, porta 80 bloccata, buffering del
    proxy); `/l` in Git Bash; caratteri jolly non espansi; KML malformati segnalati durante l'import; risposte vuote
    (semestre o comune sbagliati: verifica con `elenco_semestri` e `cerca_comuni`).
15. **Decisioni di progetto ed estensioni**: sintesi di `DECISIONI.md`.
16. **Licenza**: Apache-2.0, `NOTICE`, crate di terze parti con le loro licenze (generate con `cargo about` o
    `cargo license` se installabili, altrimenti da `cargo metadata`), condizioni dei dati OMI (`specifica/05` §5).

Appendici: riferimento completo della riga di comando (output di `--help`), struttura delle cartelle installate,
file prodotti (db, `-wal`, `-shm`, log).

Facoltativo: se `pandoc` è disponibile, genera anche `docs/MANUALE_TECNICO.html` (con indice), senza versionarlo.

Aggiorna l'elenco delle crate di terze parti in `NOTICE`.

## 2. Pacchetto di rilascio: `deploy/windows/build-release.ps1`

1. `cargo test --workspace`, poi `cargo build --release --workspace --target x86_64-pc-windows-msvc`.
2. Crea `dist\OMIMyMCP-rs-<versione>-win-x64\` con: `omi-import.exe`, `omi-mcp.exe`, `LICENSE`, `NOTICE`,
   `MANUALE_TECNICO.md` (e l'HTML, se c'è), `deploy\windows\*.ps1`, `deploy\caddy\*.example`.
3. Comprime in `dist\OMIMyMCP-rs-<versione>-win-x64.zip` e scrive `SHA256SUMS.txt`.
4. Facoltativo: firma degli eseguibili con `signtool`, se l'utente ha un certificato (parametro `-CertThumbprint`).

## 3. README

Non sostituire il contenuto attuale di `README.md` (la guida all'uso di questi script con Claude Code): aggiungi
**in cima** una sezione "Il programma" con descrizione breve, avvertenze (`specifica/05` §1), avvio rapido in
5 comandi e collegamenti al manuale e a `NOTICE`.

## 4. Verifica finale

- Rileggi il manuale da capo a fondo come un utente nuovo: ogni comando deve corrispondere all'help reale e agli
  script; nessun riferimento a opzioni inesistenti.
- Controlla i collegamenti interni dell'indice.
- `git ls-files` non deve contenere ZIP, database, log o codici fiscali:
  `git grep -nE "[A-Z]{6}[0-9]{2}[A-Z][0-9]{2}[A-Z][0-9]{3}[A-Z]"` deve trovare solo esempi sintetici.
- `fmt`, `clippy` e `test` senza errori; commit `fase 07: manuale e rilascio`; spunta la fase in `CLAUDE.md` e
  riassumi lo stato complessivo del progetto.
