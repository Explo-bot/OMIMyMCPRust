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

### 2.2 Metodo consigliato: sessione interattiva con prompt iniziale

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

Comandi per tutte le fasi (cambiano solo il numero e il nome del file):

```powershell
claude --permission-mode plan -n "omi-fase-01" "Leggi prompt/01_workspace_e_core.md ed eseguilo. Prima presentami il piano."
claude --permission-mode plan -n "omi-fase-02" "Leggi prompt/02_importatore.md ed eseguilo. Prima presentami il piano."
claude --permission-mode plan -n "omi-fase-03" "Leggi prompt/03_server_mcp.md ed eseguilo. Prima presentami il piano."
claude --permission-mode plan -n "omi-fase-04" "Leggi prompt/04_servizio_windows.md ed eseguilo. Prima presentami il piano."
claude --permission-mode plan -n "omi-fase-05" "Leggi prompt/05_caddy_https.md ed eseguilo. Prima presentami il piano."
claude --permission-mode plan -n "omi-fase-06" "Leggi prompt/06_collaudo.md ed eseguilo. Prima presentami il piano."
claude --permission-mode plan -n "omi-fase-07" "Leggi prompt/07_manuale_tecnico.md ed eseguilo. Prima presentami il piano."
```

In alternativa si può avviare `claude` senza argomenti e scrivere la richiesta nella sessione. Con `Shift+Tab` si
passa da una modalità di permessi all'altra (normale, accettazione automatica delle modifiche, piano).

### 2.3 Ridurre le richieste di autorizzazione (facoltativo)

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
file: `claude --permission-mode acceptEdits -n "omi-fase-02" "…"`. Sconsigliato invece
`--dangerously-skip-permissions`, perché le fasi 04 e 05 toccano servizi e firewall di sistema.

### 2.4 Riprendere una fase interrotta

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

### 2.5 Esecuzione non interattiva (facoltativa, per utenti esperti)

Con `-p` Claude Code esegue una richiesta senza interfaccia e termina. Non può fare domande, quindi conviene solo
per le fasi senza decisioni da prendere e dopo aver configurato i permessi del §2.3. Esempio in PowerShell, con
log su file:

```powershell
claude -p "Leggi prompt/02_importatore.md ed eseguilo fino in fondo senza fare domande: dove la specifica è ambigua decidi e annota in docs/DECISIONI.md." `
  --permission-mode acceptEdits --max-turns 200 --output-format text | Tee-Object -FilePath fase-02.log
```

Il metodo interattivo del §2.2 resta consigliato: vedere il piano e poterlo correggere evita molto lavoro buttato.

### 2.6 Scelta del modello

Per questo progetto è consigliato il modello più capace disponibile nel vostro piano, per esempio
`claude --model opus …`. Dentro una sessione il comando `/model` mostra e cambia il modello.

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
| 07 | `docs\MANUALE_TECNICO.md`, `dist\…zip` | lettura del manuale; `deploy\windows\build-release.ps1` |

A ogni fine fase `CLAUDE.md` mostra la casella spuntata e una riga di note; `git log --oneline` mostra il commit della fase.
Le scelte prese da Claude Code dove la specifica lasciava margine sono in `docs/DECISIONI.md`: conviene leggerle.

## 4. Dopo la fase 07

Il manuale `docs/MANUALE_TECNICO.md` contiene le istruzioni per l'utente finale: compilazione, caricamento dei dati,
avvio da console, installazione come servizio, HTTPS con Caddy, collegamento a claude.ai, Claude Desktop e Claude
Code, disinstallazione completa e risoluzione dei problemi. Il pacchetto pronto da distribuire è in `dist\`.

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
| La fase si ferma per i limiti d'uso | Attendere il ripristino e riprendere con `claude -r "omi-fase-NN"` (§2.4) |
| Errori ricorrenti sull'API di rmcp | Chiedere: "Rileggi la documentazione di rmcp della versione in Cargo.lock e correggi". Il prompt 03 lo prevede già, ma a volte va ricordato |
| Le prove dei servizi falliscono con "accesso negato" | Rilanciare la fase con il terminale aperto come amministratore |
| `/l` non funziona in Git Bash | In Git Bash usare `-l` (gli argomenti che iniziano con `/` vengono convertiti in percorsi) |

## 6. Licenza e dati

Il codice prodotto è distribuito con licenza **Apache-2.0** (vedi `specifica/05_contesto_e_uso.md` §5). I dati OMI
**non** sono inclusi e restano soggetti alle condizioni d'uso dell'Agenzia delle Entrate: il database prodotto è a
uso di chi ha scaricato i dati e non va condiviso né pubblicato. Ogni risultato basato sui dati va accompagnato dalla
fonte **"Agenzia delle Entrate - OMI"**.
