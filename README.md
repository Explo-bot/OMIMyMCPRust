# OMIMyMCP-rs: script per Claude Code

Questa cartella contiene **tutto ciò che serve a Claude Code** per realizzare da zero, in Rust, un sistema che:

1. carica in un database SQLite le quotazioni immobiliari OMI scaricate dal sito dell'Agenzia delle Entrate
   (programma da riga di comando **`omi-import`**);
2. espone quel database come **server MCP** interrogabile da Claude e da qualunque client MCP (programma
   monolitico **`omi-mcp`**, basato su Axum, avviabile da console o installabile come servizio Windows, con Caddy
   come reverse proxy HTTPS facoltativo);
3. è documentato da un **manuale tecnico** che spiega come compilare, installare, eseguire e disinstallare il tutto.

I file sono autonomi: non serve alcun altro repository né codice preesistente. La specifica funzionale completa
(schema del database, formati dei file, algoritmi, SQL, testi e risposte degli strumenti MCP) è nella cartella
`specifica/`. Claude Code la segue fase per fase.

## Contenuto

```
README.md                    ← questo file: come lanciare gli script
CLAUDE.md                    ← regole permanenti del progetto (Claude Code lo legge da solo)
specifica/
  01_database.md             ← schema SQLite, convenzioni, riepilogo, semestri
  02_forniture_e_importazione.md ← ZIP/CSV/KML dell'Agenzia e algoritmo di import
  03_geometria_e_testo.md    ← codifica dei perimetri, calcoli geometrici, normalizzazione dei nomi
  04_server_e_strumenti_mcp.md   ← server MCP, 9 strumenti, formati JSON, errori, log
  05_contesto_e_uso.md       ← client MCP, avvertenze, licenze
prompt/
  01_workspace_e_core.md     ← fase 1: progetto Cargo e libreria comune
  02_importatore.md          ← fase 2: omi-import
  03_server_mcp.md           ← fase 3: omi-mcp
  04_servizio_windows.md     ← fase 4: servizio Windows e script PowerShell
  05_caddy_https.md          ← fase 5: Caddy e HTTPS
  06_collaudo.md             ← fase 6: collaudo
  07_manuale_tecnico.md      ← fase 7: manuale tecnico e pacchetto di rilascio
scripts/
  esegui-fasi.ps1            ← esegue le fasi in sequenza (PowerShell)
  esegui-fasi.sh             ← esegue le fasi in sequenza (bash)
```

Al termine, nella stessa cartella ci saranno anche il workspace Rust (`Cargo.toml`, `crates/`), gli script di
installazione (`deploy/`) e la documentazione (`docs/MANUALE_TECNICO.md`, `docs/DECISIONI.md`, `docs/COLLAUDO.md`).

---

## 1. Prerequisiti

### 1.1 Account
Claude Code richiede un abbonamento Claude **Pro, Max, Team o Enterprise**, oppure un account della Claude Console
(API). Il piano gratuito non include Claude Code. Per un progetto di queste dimensioni è consigliato un piano con
limiti d'uso ampi: le fasi 02 e 03 sono le più lunghe.

### 1.2 Software sulla macchina Windows

Aprire **PowerShell** (non serve come amministratore, salvo dove indicato) ed eseguire:

| Componente | Installazione | Verifica |
|---|---|---|
| Claude Code | `irm https://claude.ai/install.ps1 \| iex` (in alternativa `winget install Anthropic.ClaudeCode`) | `claude --version`, poi `claude doctor` |
| Git for Windows (consigliato: fornisce Git Bash a Claude Code) | `winget install Git.Git` | `git --version` |
| Visual Studio Build Tools 2022 con il C++ (linker MSVC e compilatore C per SQLite) | `winget install Microsoft.VisualStudio.2022.BuildTools --override "--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"` | `where link.exe` da un "Developer PowerShell for VS 2022" |
| Rust (rustup, toolchain stabile MSVC) | `winget install Rustlang.Rustup`, poi in un nuovo terminale `rustup default stable-x86_64-pc-windows-msvc` | `rustc --version`, `cargo --version` |
| Node.js (facoltativo: MCP Inspector e `mcp-remote`) | `winget install OpenJS.NodeJS.LTS` | `node --version` |
| Caddy (facoltativo, solo per la fase 05) | download da <https://caddyserver.com/download> | `caddy version` |

Dopo le installazioni **chiudere e riaprire il terminale**, così il `PATH` si aggiorna.

### 1.3 Primo accesso a Claude Code

```powershell
claude
```
Al primo avvio Claude Code apre il browser per l'accesso. Completato l'accesso, uscire con `/exit`.

### 1.4 Dati di prova (facoltativi ma consigliati)

Creare la cartella `dati-test\` dentro questa cartella e copiarci uno o due ZIP OMI reali, per esempio un `QIP`
di una provincia piccola (2° semestre 2010 o successivo) e un `QI` precedente al 2010. Le istruzioni per scaricarli
sono in `specifica/02_forniture_e_importazione.md` §1. Claude Code li usa per allineare i test al formato reale e
per misurare le prestazioni. La cartella è esclusa da git perché i nomi dei file contengono il codice fiscale.

---

## 2. Come lanciare gli script

### 2.1 Regole generali

- **Lanciare sempre `claude` da questa cartella**: solo così Claude Code carica `CLAUDE.md` e trova `specifica/` e `prompt/`.
- **Una fase per sessione**, nell'ordine da 01 a 07. Ogni fase riparte dallo stato salvato nei file e dalla lista
  di avanzamento in `CLAUDE.md`, quindi una sessione nuova non perde nulla.
- **Partire in modalità piano** (`--permission-mode plan`): Claude Code legge la specifica e il prompt, propone un
  piano e non modifica nulla finché non lo approvate. Dopo l'approvazione lavora e chiede conferma per i comandi
  che non avete autorizzato in anticipo.
- Le fasi **04, 05 e 06** contengono prove che richiedono i privilegi di amministratore (servizi Windows, firewall,
  porte 80/443): per quelle fasi aprire il terminale con **"Esegui come amministratore"**. Se non lo fate, Claude
  Code esegue tutto il resto e lascia le prove come passi manuali, elencati nelle note della fase.

### 2.2 Script per eseguire le fasi in sequenza

In `scripts/` ci sono due script equivalenti che lanciano le fasi una dopo l'altra:

| Script | Dove si usa |
|---|---|
| `scripts\esegui-fasi.ps1` | Windows PowerShell 5.1 o PowerShell 7 |
| `scripts/esegui-fasi.sh` | Git Bash per Windows, WSL, Linux, macOS |

Per ogni fase lo script avvia Claude Code con il prompt giusto e un nome di sessione (`omi-fase-01`, …). Alla
chiusura della sessione controlla in `CLAUDE.md` che la fase sia stata spuntata. Le fasi già spuntate vengono
saltate, quindi si può rilanciare lo script in qualunque momento e riparte dalla prima fase non completata.

**Modalità interattiva** (predefinita): ogni fase si apre in modalità piano. Approvate il piano, seguite il lavoro
e chiudete la sessione con `/exit`. Se la fase non risulta completata, lo script propone di **riprendere** la stessa
sessione, aprirne una **nuova** che riparta dallo stato dei file, **saltare** la fase o **fermarsi**.

```powershell
cd C:\Users\altie\Desktop\OMIMyMCP
powershell -ExecutionPolicy Bypass -File scripts\esegui-fasi.ps1                     # tutte le fasi
powershell -ExecutionPolicy Bypass -File scripts\esegui-fasi.ps1 -Da 3 -A 5          # solo le fasi 03-05
powershell -ExecutionPolicy Bypass -File scripts\esegui-fasi.ps1 -Profilo massimo -Push  # Fable per 02, 03, 06 e git push dopo ogni fase
```

```bash
cd ~/OMIMyMCP            # oppure /c/Users/altie/Desktop/OMIMyMCP in Git Bash
bash scripts/esegui-fasi.sh
bash scripts/esegui-fasi.sh --da 3 --a 5
bash scripts/esegui-fasi.sh --profilo massimo --push
```

**Modalità automatica** (`-Automatica` / `--automatica`): ogni fase gira senza interfaccia (`claude -p`) e senza
domande. Le decisioni vanno in `docs/DECISIONI.md` e l'output in `logs\fase-NN.log`; lo script si ferma alla prima
fase non completata. Lo script concede in anticipo i permessi per leggere e scrivere file e per i comandi `cargo`,
`rustc`, `rustup` e `git` (escluso `push`, che fa lo script stesso con `-Push`). Su Windows la modalità automatica
richiede Git for Windows, perché i permessi riguardano lo strumento Bash di Claude Code.

```powershell
powershell -ExecutionPolicy Bypass -File scripts\esegui-fasi.ps1 -Automatica -Da 1 -A 3
```
```bash
bash scripts/esegui-fasi.sh --automatica --da 1 --a 3
```

| Parametro PowerShell | Parametro bash | Significato |
|---|---|---|
| `-Da N` / `-A N` | `--da N` / `--a N` | prima e ultima fase da eseguire (1-7) |
| `-Automatica` | `--automatica` | esecuzione non interattiva con log in `logs/` |
| `-Profilo NOME` | `--profilo NOME` | modelli per fase: `consigliato` (default), `massimo`, `economico` (§2.7) |
| `-Modello NOME` | `--modello NOME` | stesso modello per tutte le fasi, ignorando il profilo (es. `opus`) |
| `-Effort LIVELLO` | `--effort LIVELLO` | stesso livello di ragionamento per tutte le fasi |
| `-MostraModelli` | `--mostra-modelli` | mostra la tabella fase → modello ed esce |
| `-MaxTurni N` | `--max-turni N` | limite di turni per fase in modalità automatica (default 300) |
| `-Forza` | `--forza` | riesegue anche le fasi già spuntate |
| `-Push` | `--push` | `git push` dopo ogni fase completata |
| `-SenzaConferma` | `--senza-conferma` | passa alla fase successiva senza chiedere |

Consigli:
- Per le fasi 04-06 lanciate lo script da un terminale aperto **come amministratore**; altrimenti le prove di
  sistema restano passi manuali, elencati nelle note della fase.
- La modalità automatica conviene per le fasi 01-03, quando avete fiducia nella specifica. Per le fasi 04-07 è
  meglio quella interattiva, che permette di vedere il piano prima di toccare servizi, firewall e documentazione.
- Se PowerShell blocca lo script con un errore di criteri di esecuzione, usate la forma
  `powershell -ExecutionPolicy Bypass -File …` mostrata sopra, che vale solo per quell'esecuzione.

### 2.3 Lancio manuale di una fase (sessione interattiva con prompt iniziale)

Per ogni fase, da PowerShell:

```powershell
cd C:\Users\altie\Desktop\OMIMyMCP
claude --permission-mode plan -n "omi-fase-01" "Leggi prompt/01_workspace_e_core.md ed eseguilo. Prima presentami il piano."
```

Cosa succede:
1. Claude Code legge `CLAUDE.md`, la specifica e il prompt della fase, poi mostra un piano.
2. Leggete il piano e approvatelo (o chiedete modifiche scrivendo nella sessione).
3. Claude Code lavora: crea file, compila, esegue i test, corregge gli errori. Quando chiede l'autorizzazione per
   un comando (per esempio `cargo test`), potete consentirlo una volta o per tutta la sessione.
4. A fine fase Claude Code esegue `cargo fmt`, `cargo clippy` e `cargo test`, fa il commit e spunta la fase in `CLAUDE.md`.
5. Uscite con `/exit` e passate alla fase successiva.

Comandi per tutte le fasi, con il modello e il livello di ragionamento del profilo consigliato (§2.7):

```powershell
claude --permission-mode plan -n "omi-fase-01" --model opus   --effort high  "Leggi prompt/01_workspace_e_core.md ed eseguilo. Prima presentami il piano."
claude --permission-mode plan -n "omi-fase-02" --model opus   --effort xhigh "Leggi prompt/02_importatore.md ed eseguilo. Prima presentami il piano."
claude --permission-mode plan -n "omi-fase-03" --model opus   --effort xhigh "Leggi prompt/03_server_mcp.md ed eseguilo. Prima presentami il piano."
claude --permission-mode plan -n "omi-fase-04" --model opus   --effort high  "Leggi prompt/04_servizio_windows.md ed eseguilo. Prima presentami il piano."
claude --permission-mode plan -n "omi-fase-05" --model sonnet --effort high  "Leggi prompt/05_caddy_https.md ed eseguilo. Prima presentami il piano."
claude --permission-mode plan -n "omi-fase-06" --model opus   --effort xhigh "Leggi prompt/06_collaudo.md ed eseguilo. Prima presentami il piano."
claude --permission-mode plan -n "omi-fase-07" --model sonnet --effort high  "Leggi prompt/07_manuale_tecnico.md ed eseguilo. Prima presentami il piano."
```

In alternativa si può avviare `claude` senza argomenti e scrivere la richiesta nella sessione. Con `Shift+Tab` si
passa da una modalità di permessi all'altra (normale, accettazione automatica delle modifiche, piano).

### 2.4 Ridurre le richieste di autorizzazione (facoltativo)

Per non dover confermare ogni compilazione, prima della fase 01 create `.claude\settings.json` in questa cartella:

```json
{
  "permissions": {
    "allow": [
      "Bash(cargo *)",
      "Bash(rustc *)",
      "Bash(rustup *)",
      "Bash(git status *)",
      "Bash(git diff *)",
      "Bash(git add *)",
      "Bash(git commit *)",
      "Bash(git log *)"
    ]
  }
}
```

La sintassi delle regole può cambiare tra versioni di Claude Code: in caso di dubbio consultate
<https://code.claude.com/docs/en/settings> oppure usate il comando `/permissions` nella sessione. Le operazioni
delicate (installazione di servizi, firewall, `git push`) restano soggette a conferma: è voluto.

In alternativa, una volta approvato il piano, la modalità `acceptEdits` accetta senza chiedere le modifiche ai
file: `claude --permission-mode acceptEdits -n "omi-fase-02" --model opus --effort xhigh "…"`. Sconsigliato invece
`--dangerously-skip-permissions`, perché le fasi 04 e 05 toccano servizi e firewall di sistema.

### 2.5 Riprendere una fase interrotta

Se la sessione si chiude, finiscono i limiti d'uso o il lavoro si interrompe:

```powershell
claude -c                         # riprende l'ultima conversazione in questa cartella
claude -r "omi-fase-03"           # riprende la sessione con quel nome
claude -r                         # mostra l'elenco delle sessioni da riprendere
```

Oppure in una sessione nuova:

```powershell
claude "Riprendi la fase 03 (prompt/03_server_mcp.md) da dove era rimasta: controlla lo stato del codice e dei test, poi continua."
```

Se in una sessione lunga il contesto si riempie, Claude Code lo compatta da solo; potete anche usare `/compact`. Tra
una fase e l'altra è meglio una sessione nuova (o `/clear`) che una conversazione unica: lo stato è nei file.

### 2.6 Esecuzione non interattiva di una singola fase (per utenti esperti)

Con `-p` Claude Code esegue una richiesta senza interfaccia e termina. Non può fare domande, quindi conviene solo
per le fasi senza decisioni da prendere e dopo aver configurato i permessi del §2.4. Esempio in PowerShell, con
log su file:

```powershell
claude -p "Leggi prompt/02_importatore.md ed eseguilo fino in fondo senza fare domande: dove la specifica è ambigua decidi e annota in docs/DECISIONI.md." `
  --permission-mode acceptEdits --model opus --effort xhigh --max-turns 200 --output-format text | Tee-Object -FilePath fase-02.log
```

Il metodo interattivo (§2.2 e §2.3) resta consigliato: vedere il piano e poterlo correggere evita molto lavoro buttato.

### 2.7 Scelta del modello per fase

Gli script scelgono per ogni fase un **modello** e un **livello di ragionamento** (`--effort`: `low`, `medium`,
`high`, `xhigh`, `max`) in base al lavoro della fase. Ci sono tre profili, scelti con `-Profilo` / `--profilo`:

| Fase | Lavoro | consigliato (default) | massimo | economico |
|---|---|---|---|---|
| 01 Workspace e `omi-core` | codifica binaria e geometria da riprodurre al bit, test con vettori noti | `opus` · high | `opus` · xhigh | `opusplan` · high |
| 02 Importatore | la fase più delicata: macchina a stati KML, recupero dei file malformati, transazioni, deduplicazione, 14 casi di test | `opus` · xhigh | `best` · xhigh | `opus` · high |
| 03 Server MCP | API di rmcp che cambia spesso, 9 strumenti con JSON identico alla specifica, concorrenza | `opus` · xhigh | `best` · xhigh | `opus` · high |
| 04 Servizio Windows | API del Service Control Manager, permessi, script PowerShell idempotenti | `opus` · high | `opus` · xhigh | `opusplan` · high |
| 05 Caddy e HTTPS | configurazione e script, poco codice | `sonnet` · high | `opus` · high | `sonnet` · medium |
| 06 Collaudo | revisione critica requisito per requisito e risultati attesi scritti a mano: serve il ragionamento più attento | `opus` · xhigh | `best` · xhigh | `opusplan` · high |
| 07 Manuale e rilascio | scrittura lunga e verifica dei comandi contro l'help reale | `sonnet` · high | `opus` · high | `sonnet` · medium |

Perché queste scelte:
- **Opus** (`opus`, Opus 5.5) è il modello predefinito di Claude Code e il più adatto al codice difficile da
  correggere dopo: formati binari, parser, protocollo MCP, servizio Windows. Il livello `xhigh` è riservato alle
  fasi 02, 03 e 06, dove un errore sottile si paga nelle fasi successive.
- **Sonnet** (`sonnet`, Sonnet 5.5) basta per le fasi 05 e 07, fatte soprattutto di configurazione e di testo, ed è
  più veloce e meno costoso in termini di limiti d'uso.
- **`best`** sceglie Fable 5.1 dove è disponibile (altrimenti Opus): è il modello più capace, ma **consuma i
  crediti d'uso** e alla prima sessione chiede un consenso. Il profilo `massimo` lo usa solo dove rende di più. Fare
  il collaudo (06) con un modello diverso da quello che ha scritto il codice dà anche una revisione più indipendente.
- **`opusplan`** usa Opus mentre la sessione è in modalità piano e Sonnet quando esegue: nel profilo `economico` il
  piano resta di qualità alta e l'esecuzione costa meno. In modalità automatica non c'è la fase di piano, quindi
  lavora interamente con Sonnet.
- **Haiku** non è usato: per un progetto di questa complessità il risparmio non compensa le correzioni.
- Per ogni fase gli script impostano anche un **modello di riserva** (`--fallback-model`), usato solo se quello
  scelto è sovraccarico o non disponibile: Opus per Fable e Sonnet, Sonnet per Opus.

Quale profilo scegliere:
- **consigliato**: piani Max, Team o Enterprise e uso normale;
- **massimo**: quando la qualità conta più di tempi e costi e avete crediti d'uso disponibili;
- **economico**: piano Pro o limiti d'uso stretti; aumenta la probabilità di dover correggere qualcosa nelle fasi 02-03.

Comandi utili:
```powershell
powershell -ExecutionPolicy Bypass -File scripts\esegui-fasi.ps1 -Profilo massimo -MostraModelli   # mostra la tabella ed esce
powershell -ExecutionPolicy Bypass -File scripts\esegui-fasi.ps1 -Profilo economico
powershell -ExecutionPolicy Bypass -File scripts\esegui-fasi.ps1 -Modello opus -Effort high       # stesso modello per tutte le fasi
```
```bash
bash scripts/esegui-fasi.sh --profilo massimo --mostra-modelli
bash scripts/esegui-fasi.sh --profilo economico
```

Gli script controllano che la versione di Claude Code supporti `--effort` e `--fallback-model` e, se non li
supporta, li omettono (aggiornare con `claude update`). Dentro una sessione `/model` e `/effort` mostrano e
cambiano modello e livello. I modelli disponibili dipendono dal piano: se un alias non è disponibile, Claude Code
lo segnala all'avvio della sessione.

---

## 3. Cosa controllare a ogni fase

| Fase | Risultato atteso | Controllo rapido (da PowerShell, in questa cartella) |
|---|---|---|
| 01 | `Cargo.toml`, `crates/omi-core`, `LICENSE`, `NOTICE`, test verdi | `cargo test -p omi-core` |
| 02 | `omi-import.exe` funzionante | `cargo run --release -p omi-import -- --help`; con dati reali: `target\release\omi-import.exe dati-test\QIP*.zip prova.db` |
| 03 | `omi-mcp.exe` con i 9 strumenti | `target\release\omi-mcp.exe prova.db 8765 /l` e, da un altro terminale, `claude mcp add --transport http omi-test http://localhost:8765/mcp` |
| 04 | servizio Windows e script in `deploy\windows\` | come amministratore: `deploy\windows\test-servizio.ps1` |
| 05 | Caddyfile di esempio e `install-caddy.ps1` | `caddy validate --config deploy\caddy\Caddyfile.lan.example --adapter caddyfile` |
| 06 | `docs\COLLAUDO.md` con la matrice di conformità e le misure | lettura del documento; `cargo test --workspace` |
| 07 | `docs\MANUALE_TECNICO.md` (con il capitolo sull'uso del server MCP da Claude), `dist\…zip` | lettura del manuale; prova di una domanda del percorso guidato con Claude; `deploy\windows\build-release.ps1` |

A ogni fine fase `CLAUDE.md` mostra la casella spuntata e una riga di note; `git log --oneline` mostra il commit della fase.
Le scelte prese da Claude Code dove la specifica lasciava margine sono in `docs/DECISIONI.md`: conviene leggerle.

## 4. Dopo la fase 07

Il manuale `docs/MANUALE_TECNICO.md` contiene le istruzioni per l'utente finale: compilazione, caricamento dei dati,
avvio da console, installazione come servizio, HTTPS con Caddy, disinstallazione completa e risoluzione dei problemi.
Un capitolo apposito spiega come **usare il server MCP da Claude**: collegamento e verifica in claude.ai, Cowork,
Claude Desktop e Claude Code, gestione dei permessi dei tool, come formulare le domande, un percorso guidato di
domande d'esempio e l'uso combinato con MCP Cruscotto Italia. Il pacchetto pronto da distribuire è in `dist\`.

Avvio rapido, una volta compilato:

```powershell
target\release\omi-import.exe C:\DatiOMI\QI*.zip C:\DatiOMI\omi.db
target\release\omi-mcp.exe C:\DatiOMI\omi.db 8765
claude mcp add --transport http omi http://localhost:8765/mcp
```

## 5. Problemi frequenti durante lo sviluppo

| Problema | Soluzione |
|---|---|
| `claude` non viene riconosciuto | Riaprire il terminale; se persiste, `claude doctor` e la guida <https://code.claude.com/docs/en/troubleshoot-install> |
| `link.exe not found` o errori del compilatore C durante `cargo build` | Mancano i Build Tools con il carico di lavoro C++ (§1.2); in alternativa compilare da "Developer PowerShell for VS 2022" |
| Claude Code non trova `CLAUDE.md` o la specifica | `claude` è stato lanciato da un'altra cartella: fare `cd` in questa cartella |
| La fase si ferma per i limiti d'uso | Attendere il ripristino e riprendere con `claude -r "omi-fase-NN"` o rilanciando lo script (§2.2, §2.5) |
| Errori ricorrenti sull'API di rmcp | Chiedere: "Rileggi la documentazione di rmcp della versione in Cargo.lock e correggi". Il prompt 03 lo prevede già, ma a volte va ricordato |
| Le prove dei servizi falliscono con "accesso negato" | Rilanciare la fase con il terminale aperto come amministratore |
| `/l` non funziona in Git Bash | In Git Bash usare `-l` (gli argomenti che iniziano con `/` vengono convertiti in percorsi) |

## 6. Licenza e dati

Il codice prodotto è distribuito con licenza **Apache-2.0** (vedi `specifica/05_contesto_e_uso.md` §5). I dati OMI
**non** sono inclusi e restano soggetti alle condizioni d'uso dell'Agenzia delle Entrate: il database prodotto è a
uso di chi ha scaricato i dati e non va condiviso né pubblicato. Ogni risultato basato sui dati va accompagnato dalla
fonte **"Agenzia delle Entrate - OMI"**.
