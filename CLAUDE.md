# OMIMyMCP-rs: memoria di progetto per Claude Code

Claude Code legge questo file da solo a ogni sessione avviata in questa cartella. Contiene le regole
permanenti. Le istruzioni operative sono in `prompt/` (una fase per file) e la specifica funzionale completa
è in `specifica/`.

## Obiettivo

Realizzare in **Rust** un sistema che carica le quotazioni immobiliari OMI dell'Agenzia delle Entrate in un
database SQLite e le espone come server MCP. Il sistema è composto da due eseguibili che condividono una
libreria:

| Eseguibile | Ruolo |
|---|---|
| `omi-import` | Riga di comando: carica in `omi.db` i file `QI*.zip` / `QIP*.zip` scaricati dal sito dell'Agenzia delle Entrate. |
| `omi-mcp` | Server MCP monolitico (Axum + rmcp, HTTP *streamable* su `/mcp`) che legge lo stesso database ed espone 9 strumenti. Si avvia da console oppure si installa come **servizio Windows**. Per l'HTTPS si usa Caddy come reverse proxy esterno e facoltativo. |

## Fonte di verità

La cartella **`specifica/`** è normativa:

| File | Contenuto |
|---|---|
| `specifica/01_database.md` | DDL, convenzioni, riepilogo, parsing dei semestri |
| `specifica/02_forniture_e_importazione.md` | formato degli ZIP, CSV e KML; algoritmo di import con tutto l'SQL |
| `specifica/03_geometria_e_testo.md` | codifica binaria, misure geometriche, arrotondamenti, normalizzazione dei nomi |
| `specifica/04_server_e_strumenti_mcp.md` | identità, rotte, i 9 strumenti (testi, parametri, SQL, JSON), errori, log |
| `specifica/05_contesto_e_uso.md` | client MCP, Cruscotto Italia, avvertenze, licenze |

Testi, messaggi, SQL e nomi indicati nella specifica vanno riprodotti **esattamente**. Se la specifica è
ambigua o incompleta, scegli la soluzione più semplice coerente con il resto, registrala in
`docs/DECISIONI.md` e segnalala nel riepilogo di fine fase. Ogni estensione oltre la specifica va registrata
nello stesso file.

## Regole non negoziabili

1. **Schema e formati.** DDL, codifica delle geometrie, hash (SHA-256 troncato a 16 byte) e convenzioni sui
   semestri esattamente come nella specifica: il database deve poter essere letto e scritto da qualunque
   strumento che rispetti lo stesso schema.
2. **SQL della specifica usato così com'è.** Cambiano solo i segnaposto (`@x` → `?N` o `:x`).
3. **Arrotondamenti all'intero pari** (`f64::round_ties_even`), mai `round()`.
4. **Privacy.** Il nome degli ZIP contiene il codice fiscale del richiedente. Nel database va solo il nome
   ripulito; il nome originale non deve mai finire nel log del server, nei test, nei fixture o in git.
   `.gitignore`: `target/`, `*.zip`, `*.db`, `*.db-shm`, `*.db-wal`, `*.log`, `dati-test/`, `dist/`, `logs/`.
5. **Licenza Apache-2.0.** File `LICENSE` (testo integrale) e `NOTICE` come in `specifica/05_contesto_e_uso.md`.
   Ogni file `.rs` inizia con:
   ```rust
   // OMIMyMCP-rs - Copyright 2026 Explobot
   // SPDX-License-Identifier: Apache-2.0
   ```
6. **Lingua.** Messaggi, log, descrizioni dei tool, errori e documentazione in italiano; identificatori del
   codice in inglese; nomi di tabelle, colonne e parametri MCP in italiano come nella specifica.
7. **Robustezza.** Niente `unwrap()`/`expect()` fuori dai test, salvo invarianti dimostrabili e commentate.
   `thiserror` in `omi-core`, `anyhow` nei binari. Un file ZIP danneggiato non deve mai interrompere il caricamento degli altri.
8. **Qualità a fine fase.** `cargo fmt --all`, `cargo clippy --workspace --all-targets -- -D warnings` e
   `cargo test --workspace` senza errori prima di dichiarare conclusa una fase.
9. **Dipendenze.** Versioni stabili recenti aggiunte con `cargo add`. L'API di **rmcp** cambia spesso: prima di
   scrivere il server leggere la documentazione su docs.rs **della versione risolta in `Cargo.lock`** (o i
   sorgenti in `~/.cargo/registry`). Non inventare API.
10. **Piattaforme.** Target principale `x86_64-pc-windows-msvc`. Tutto deve compilare e passare i test anche su
    Linux: il codice del servizio Windows sta dietro `#[cfg(windows)]`.
11. **Autonomia.** Il progetto non dipende da altri repository o programmi esterni: tutto ciò che serve è in
    questa cartella e su crates.io.

## Struttura attesa

```
./
├─ README.md                ← come usare questi script con Claude Code
├─ CLAUDE.md                ← questo file
├─ specifica/               ← specifica funzionale (normativa)
├─ prompt/                  ← fasi 01…07
├─ scripts/                 ← esegui-fasi.ps1 / esegui-fasi.sh: lanciano le fasi in sequenza (non modificarli senza motivo)
├─ logs/                    ← log delle esecuzioni automatiche (non versionato)
├─ dati-test/               ← eventuali ZIP OMI reali per i test (non versionato)
├─ Cargo.toml, Cargo.lock, .cargo/config.toml
├─ crates/
│  ├─ omi-core/             ← libreria: db, geometria, testo, import, service (logica dei tool)
│  ├─ omi-import/           ← binario omi-import
│  └─ omi-mcp/              ← binario omi-mcp (server + servizio Windows)
├─ deploy/
│  ├─ windows/              ← install.ps1, uninstall.ps1, aggiorna-dati.ps1, install-caddy.ps1, build-release.ps1, test-servizio.ps1
│  ├─ caddy/                ← Caddyfile di esempio
│  └─ linux/                ← unità systemd
└─ docs/
   ├─ MANUALE_TECNICO.md
   ├─ DECISIONI.md
   └─ COLLAUDO.md
```

## Avanzamento delle fasi

Aggiornare al termine di ogni fase: `[x]` e una riga di note (esito dei test, misure, passi rimasti manuali).

- [ ] 01 Workspace e libreria `omi-core`
- [ ] 02 Importatore `omi-import`
- [ ] 03 Server MCP `omi-mcp`
- [ ] 04 Servizio Windows
- [ ] 05 Caddy e HTTPS
- [ ] 06 Collaudo
- [ ] 07 Manuale tecnico e pacchetto di rilascio

## Comandi utili

```
cargo build --workspace --release
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
target\release\omi-import.exe --help
target\release\omi-mcp.exe --help
```
