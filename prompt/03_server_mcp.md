# Fase 03: server MCP `omi-mcp` (Axum + rmcp)

Rileggi `CLAUDE.md` e `specifica/04_server_e_strumenti_mcp.md` (insieme alla 03 per la ricerca spaziale).
Prima di scrivere codice apri su docs.rs la documentazione di **rmcp** nella versione risolta in
`Cargo.lock` e annota in testa a `crates/omi-mcp/src/mcp.rs` le API usate: macro `#[tool_router]`, `#[tool]` e
`#[tool_handler]`, `Parameters<T>`, `ServerHandler::get_info`, `StreamableHttpService`,
`StreamableHttpServerConfig` (modalità senza stato), `CallToolResult::error`, annotazioni dei tool. Feature
tipiche: `server`, `macros`, `transport-streamable-http-server`; `client` e il trasporto client HTTP nelle
`dev-dependencies` per i test.

## 1. Organizzazione

- `omi-core::service`: un metodo per strumento, con parametri tipizzati e risultato
  `Result<String /* JSON */, OmiError>`. Nessuna dipendenza da MCP, così si testa direttamente.
- `omi-core::json`: serializzatore conforme alla specifica 04 §5 (ordine delle chiavi, omissione dei `null`,
  formato dei numeri).
- `crates/omi-mcp/src/`: `main.rs` (riga di comando), `server.rs` (Axum, avvio, arresto), `mcp.rs` (tool rmcp
  → service), `log.rs` (specifica 04 §9), `auth.rs` (token), `service_windows.rs` (fase 04).
- `server::run(config, shutdown: impl Future<Output = ()>) -> Result<()>` è l'unico punto d'ingresso, usato
  sia dalla console sia dal servizio Windows. Deve poter notificare a chi lo chiama l'avvenuto bind della porta
  (canale `oneshot`), che serve al servizio Windows.

## 2. Riga di comando

```
omi-mcp [database.db] [porta] [/l] [--bind INDIRIZZO] [--trust-proxy] [--token SEGRETO | --token-file FILE] [--allowed-host HOST ...]
omi-mcp service <install|uninstall|start|stop|status> [...]        (fase 04)
omi-mcp --help | --version
```

| Parametro | Default | Comportamento |
|---|---|---|
| `*.db` | `omi.db` | Il database **deve esistere**, altrimenti `Database non trovato: {percorso}. Crearlo con omi-import.` e codice 1. Si apre solo in lettura. |
| porta `0..65535` (riconosciuta dal tipo) | `8765` | Con `0` la porta la sceglie il sistema e viene stampata. |
| `/l`, `/L`, `-l`, `-L`, `--log` | spento | Log come da specifica 04 §9. In Git Bash funziona solo `-l` (gli argomenti con `/` vengono convertiti in percorsi). |
| `--bind` | tutte le interfacce, IPv4 e IPv6 | Default: socket IPv6 `[::]` con `IPV6_V6ONLY = false` (crate `socket2`); se l'IPv6 non è disponibile, `0.0.0.0`. Dietro Caddy: `--bind 127.0.0.1`. |
| `--trust-proxy` | spento | Nel log l'IP del client è il primo valore di `X-Forwarded-For`, seguito da `(via {peer})`. Ha senso solo con `--bind 127.0.0.1`. |
| `--token`, `--token-file`, variabile `OMI_MCP_TOKEN` | spento | Se impostato, `/mcp` richiede `Authorization: Bearer <token>` (confronto a tempo costante), altrimenti `401` con `WWW-Authenticate: Bearer`. `/` e `/health` restano liberi. Da `--token-file` si legge la prima riga, ripulita. |
| `--allowed-host` | nessuna restrizione aggiuntiva | Se rmcp convalida `Host`/`Origin` (protezione dal DNS rebinding), il controllo non deve bloccare le richieste inoltrate da Caddy con l'host pubblico: la lista va configurabile. Se rmcp non fa il controllo, implementalo come layer facoltativo, attivo solo con questa opzione. |

Avvio a console:
```
{attribuzione}
Fonte dei dati: Agenzia Entrate - OMI
Database: {percorso assoluto}
<print_summary>
Server MCP in ascolto su http://localhost:{porta}/mcp        (con l'indirizzo reale se --bind è specifico)
Log attivo, file: {percorso}                                  (solo con /l)
Ctrl+C per terminare.
```

## 3. Rotte e middleware

- `/mcp`: `StreamableHttpService` montato con `nest_service`, **senza stato**. L'handler condivide il pool di connessioni.
- `GET /` e `GET /health` come da specifica 04 §2.
- Layer: limite del corpo a 1 MiB, timeout di 60 s per le richieste non in streaming, middleware di log (§5),
  autenticazione (§2).
- Arresto pulito con `with_graceful_shutdown`, alimentato da `tokio::signal::ctrl_c()` a console o dal Service
  Control Manager in modalità servizio.

## 4. Strumenti, database, errori

- I 9 strumenti con nomi, descrizioni, parametri, default, annotazioni e risultati della specifica 04 §4–§8.
  Parametri facoltativi come `Option<T>` con `#[serde(default)]`; lo schema JSON generato da `schemars` deve
  avere esattamente i campi `required` della specifica e le descrizioni dei parametri come `description`.
- Accetta numeri e booleani passati come stringa (deserializzatore personalizzato).
- `rusqlite` è sincrono: ogni tool gira in `tokio::task::spawn_blocking`. Pool di connessioni in sola lettura
  (`r2d2` + `r2d2_sqlite`, o un pool scritto a mano) con `query_only=1` e `busy_timeout`, dimensionato sul numero
  di CPU (minimo 4).
- Errori come da specifica 04 §6. Un panic o un `JoinError` in un tool diventano un errore interno: il server
  non deve cadere.

## 5. Log

Specifica 04 §9. Scritture serializzate (mutex o task dedicato con canale). L'IP del peer si ricava da
`ConnectInfo<SocketAddr>`; un IPv4 mappato su IPv6 (`::ffff:1.2.3.4`) si mostra come IPv4 semplice. In modalità
servizio la console non esiste: le righe vanno solo su file. Anche senza `/l`, gli errori interni vanno su stderr
(a console) o nel log di servizio.

## 6. Test

Usa il generatore di fixture della fase 02 per creare un database di prova con almeno: due comuni con lo stesso
nome in province diverse, un semestre con perimetri e uno senza, una zona il cui codice non esiste nel semestre
dei perimetri, una zona con più tipologie e stati, un comune con un nome storico diverso.

1. **`omi-core::service`** (senza HTTP), per ogni tool: struttura completa del JSON, ordine delle chiavi e
   valori attesi; tutti i messaggi d'errore della specifica (semestre non valido, semestre assente, database
   vuoto, comune inesistente, comune ambiguo, zona inesistente, nessun perimetro, punto lontano oltre 2 km);
   `zona_da_coordinate` con punto interno, punto vicino (approssimato) e semestre senza perimetri;
   `zone_vicine` con raggio oltre il massimo; `storico_zona` con stato in minuscolo.
2. **JSON:** `1500.0` → `1500`, `12.5`, `0.1`, `-0.0`, `1e21`; omissione dei `null`; eccezione di `elenco_tipologie`; accenti non sottoposti a escape.
3. **Integrazione HTTP:** server su porta 0, client rmcp: `initialize` (serverInfo, instructions),
   `tools/list` (9 tool, `required`, descrizioni, annotazioni), una `tools/call` per tool; `GET /`, `GET /health`.
4. **Token:** 401 senza intestazione e con token errato, 200 con il token corretto; `/` e `/health` liberi.
5. **Log:** formato delle righe `HTTP` e `TOOL` (con regex) su file temporaneo, conteggio in unità UTF-16.
6. **Concorrenza:** 50 chiamate parallele a `zona_da_coordinate` e, nello stesso momento, un import in corso sullo stesso database.
7. **Prova manuale**, se gli strumenti sono disponibili: `npx @modelcontextprotocol/inspector` e
   `claude mcp add --transport http omi-test http://localhost:8765/mcp`. Riporta l'esito nelle note della fase.

Esegui `fmt`, `clippy` e `test`, fai un commit `fase 03: omi-mcp` e spunta la fase.
