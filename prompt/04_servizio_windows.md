# Fase 04: `omi-mcp` come servizio Windows

Rileggi `CLAUDE.md`. Implementa la gestione del servizio in `crates/omi-mcp/src/service_windows.rs` con la
crate `windows-service` (tutto sotto `#[cfg(windows)]`). Su Linux i sottocomandi `service` rispondono
`Disponibile solo su Windows: usare l'unità systemd in deploy/linux.` e il programma esce con 1.

## 1. Sottocomandi

```
omi-mcp service install   [--name OMIMyMCP] [--display-name "OMIMyMCP - Server MCP quotazioni OMI"]
                          --db C:\ProgramData\OMIMyMCP\omi.db [--port 8765] [--bind 127.0.0.1] [--log]
                          [--trust-proxy] [--token-file C:\ProgramData\OMIMyMCP\token.txt]
                          [--start auto|delayed|manual] [--account localservice|networkservice|localsystem]
                          [--firewall] [--no-acl] [--now]
omi-mcp service uninstall [--name OMIMyMCP] [--keep-firewall]
omi-mcp service start|stop|status [--name OMIMyMCP]
omi-mcp service run --name OMIMyMCP ...      (interno: lo usa il Service Control Manager, nascosto dall'help)
```

### `install`
1. Controlla che il processo abbia i privilegi di amministratore. Se non li ha:
   `Servono i privilegi di amministratore: aprire il Prompt dei comandi o PowerShell con "Esegui come amministratore".`
   e codice 1. Gestisci anche `ERROR_ACCESS_DENIED` restituito dal Service Control Manager.
2. Calcola percorsi **assoluti**: eseguibile (`current_exe`, preferibilmente in `C:\Program Files\OMIMyMCP\`;
   se è in una cartella utente, avvisa che il servizio non deve dipendere dal Desktop) e database (deve esistere).
3. Crea il servizio (`ServiceManager::local_computer` + `create_service`):
   - `executable_path` = eseguibile, `launch_arguments` = `service run --name … --db … --port … [--bind …] [--log] [--trust-proxy] [--token-file …]`;
   - tipo `OWN_PROCESS`, avvio `AutoStart` (con `delayed` imposta anche l'avvio ritardato), `ErrorControl::Normal`;
   - account: di default `NT AUTHORITY\LocalService` (minimo privilegio);
   - descrizione: `Server MCP sulle quotazioni immobiliari OMI. Fonte dei dati: Agenzia Entrate - OMI. {attribuzione}`;
   - azioni in caso di errore: riavvio dopo 5 s, 30 s e 60 s, contatore azzerato dopo 1 giorno
     (`update_failure_actions`), anche quando il servizio si ferma con codice d'uscita diverso da 0.
4. **Permessi sul database** (salvo `--no-acl`). In WAL anche chi legge deve poter creare e scrivere
   `omi.db-shm`, quindi l'account del servizio ha bisogno della modifica sulla **cartella** del database:
   `icacls "<cartella>" /grant "*S-1-5-19:(OI)(CI)M"` (SID di LocalService; S-1-5-20 per NetworkService;
   nulla per LocalSystem). Stampa il comando eseguito e il suo esito.
5. Con `--firewall` aggiunge la regola
   `netsh advfirewall firewall add rule name="OMIMyMCP" dir=in action=allow protocol=TCP localport=<porta> program="<exe>"`.
   Senza `--firewall`, se `--bind` non è `127.0.0.1`, avvisa che il firewall di Windows può bloccare le
   connessioni dalla rete.
6. Con `--now` avvia il servizio e attende lo stato `Running` (timeout 30 s), poi verifica
   `GET http://127.0.0.1:<porta>/health`.
7. Riepilogo finale: nome del servizio, account, URL MCP, file di log, comandi per fermarlo e disinstallarlo.

### `uninstall`
Se il servizio è in esecuzione lo ferma e attende `Stopped` (timeout 30 s), poi lo elimina
(`delete`) e attende che sparisca dal Service Control Manager. Rimuove la regola firewall `OMIMyMCP` (salvo
`--keep-firewall`). **Non** cancella database, log e token: lo dice esplicitamente e indica i percorsi.
Se il servizio non esiste: `Il servizio {nome} non è installato.` e codice 0.

### `start`, `stop`, `status`
`status` stampa stato, tipo di avvio, account, percorso e argomenti (leggendo la configurazione del
servizio), PID se in esecuzione, e infine l'esito di `/health`.

### `run` (punto d'ingresso del Service Control Manager)
- `define_windows_service!` + `service_dispatcher::start`. Se `run` viene lanciato a mano da console, il
  dispatcher fallisce con `ERROR_FAILED_SERVICE_CONTROLLER_CONNECT`: stampa
  `Questo comando è riservato al Service Control Manager. Per la console usare: omi-mcp <db> <porta>.`
- Nel `service_main`: registra il gestore dei controlli (`Stop`, `Shutdown`) che invia un segnale
  (`tokio_util::sync::CancellationToken` o `oneshot`); segnala `StartPending`, crea il runtime Tokio, chiama
  `server::run(config, shutdown)` e segnala `Running` solo **dopo** il bind riuscito della porta; all'arresto
  segnala `StopPending` e poi `Stopped` con codice d'uscita 0, oppure con un codice specifico in caso di
  errore (porta occupata, database mancante).
- La cartella di lavoro di un servizio è `C:\Windows\System32`: tutti i percorsi arrivano già assoluti dagli argomenti.
- **Log del ciclo di vita sempre attivo**, anche senza `--log`: avvio, configurazione (con il token
  mascherato), bind, arresto, errori e panic (`std::panic::set_hook`) vanno nel file `<database>.log`. Con
  `--log` si aggiungono le righe `HTTP` e `TOOL` della fase 03. Facoltativo: scrivere gli errori gravi anche
  nel Registro eventi di Windows (crate `eventlog` o `windows`), annotandolo nel manuale.
- Token: letto da `--token-file` (prima riga, ripulita) per non lasciarlo visibile negli argomenti del
  servizio. Il file deve essere leggibile dall'account del servizio.

## 2. Script PowerShell in `deploy/windows/`

Gli script devono controllare i privilegi di amministratore, fermarsi al primo errore
(`$ErrorActionPreference = 'Stop'`), essere idempotenti e stampare ciò che fanno. Supportano `-WhatIf`
dove ha senso.

- **`install.ps1`** `-SourceDir <cartella dei binari> [-InstallDir "C:\Program Files\OMIMyMCP"] [-DataDir "C:\ProgramData\OMIMyMCP"] [-Port 8765] [-Bind 127.0.0.1] [-Log] [-Firewall] [-WithToken]`
  1. copia `omi-mcp.exe`, `omi-import.exe`, `LICENSE`, `NOTICE` e `MANUALE_TECNICO.md` in `InstallDir`;
  2. crea `DataDir` e, con `-WithToken`, genera un token casuale (32 byte, base64url) in `DataDir\token.txt`
     con ACL limitata ad Administrators e all'account del servizio;
  3. se `DataDir\omi.db` non esiste, avvisa che va prima caricato con `omi-import` e si ferma prima di
     installare il servizio;
  4. esegue `omi-mcp service install … --now`;
  5. facoltativo: aggiunge `InstallDir` al `PATH` di sistema (`-AddToPath`).
- **`uninstall.ps1`** `[-InstallDir …] [-DataDir …] [-RemoveData] [-RemoveCaddy]`
  1. `omi-mcp service uninstall`;
  2. con `-RemoveCaddy`, ferma ed elimina il servizio `caddy` (fase 05);
  3. rimuove `InstallDir` e la voce del `PATH`;
  4. con `-RemoveData` elimina `DataDir` (database, log, token) dopo una conferma esplicita, saltata solo
     con `-Force`.
- **`aggiorna-dati.ps1`** `-ZipDir <cartella> [-DataDir …]`: ferma il servizio, esegue `omi-import` sugli
  ZIP indicati, riavvia il servizio e mostra il riepilogo. Il server può leggere durante l'import, ma
  fermarlo evita blocchi su caricamenti nazionali di grandi dimensioni.

## 3. Linux (facoltativo, per completezza del manuale)

`deploy/linux/omi-mcp.service` (unità systemd): utente dedicato `omi`, `ExecStart=/opt/omimymcp/omi-mcp /var/lib/omimymcp/omi.db 8765 --bind 127.0.0.1`,
`Restart=on-failure`, `ProtectSystem=strict`, `ReadWritePaths=/var/lib/omimymcp`, `NoNewPrivileges=true`.

## 4. Verifica

I test automatici del servizio non girano in CI. Scrivi `deploy/windows/test-servizio.ps1`, da lanciare a
mano come amministratore: installa con un nome di prova (`OMIMyMCP-Test`, porta 18765), verifica `Running` e
`/health`, chiama `tools/list` con `Invoke-RestMethod` (POST JSON-RPC con
`Accept: application/json, text/event-stream`), ferma, riavvia, disinstalla e verifica che il servizio non
esista più e che la regola firewall sia stata rimossa. Se la sessione corrente è su Windows con privilegi
di amministratore, eseguilo e riporta l'esito; altrimenti segnalalo come passo manuale nelle note della fase.

Esegui `fmt`, `clippy` e `test` (anche con `cargo check --target x86_64-pc-windows-msvc` se sei su Linux e il
target è installato), poi spunta la fase.
