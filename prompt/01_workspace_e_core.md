# Fase 01: workspace Cargo e libreria `omi-core`

Rileggi `CLAUDE.md` e leggi **per intero** tutti i file di `specifica/`. Poi esegui i passi seguenti e, al
termine, spunta la fase 01 in `CLAUDE.md`.

## 1. Repository e file di progetto

- `git init` se la cartella non è ancora un repository. `.gitignore` come da `CLAUDE.md`.
- `LICENSE`: testo integrale della Apache License 2.0. Scaricalo da
  <https://www.apache.org/licenses/LICENSE-2.0.txt>; se la rete non lo consente, scrivi il testo standard
  completo, senza riassumerlo né modificarlo.
- `NOTICE`: come in `specifica/05_contesto_e_uso.md` §5 (l'elenco delle crate si completa nella fase 07).
- `docs/DECISIONI.md`: intestazione e tabella vuota (Area | Decisione | Motivo).

## 2. Workspace

`Cargo.toml` alla radice:
- `[workspace]` con `resolver = "3"` e membri `crates/omi-core`, `crates/omi-import`, `crates/omi-mcp`.
- `[workspace.package]`: `version = "1.0.0"`, `edition = "2024"`, `license = "Apache-2.0"`,
  `authors = ["Explobot"]`, `rust-version` pari alla toolchain installata.
- `[workspace.dependencies]` centralizzate. Almeno: `rusqlite` (feature `bundled`), `thiserror`, `anyhow`,
  `regex`, `serde`, `serde_json` (feature `preserve_order`), `sha2`, `chrono`, `zip`, `quick-xml`, `glob`;
  per il server `tokio`, `axum`, `rmcp`, `schemars`, `tower-http`, `socket2`; `windows-service` solo su Windows.
- `[profile.release]`: `lto = "thin"`, `codegen-units = 1`, `strip = "symbols"`, `panic` lasciato su
  `unwind` (il servizio deve poter registrare un panic prima di terminare).

`.cargo/config.toml`, per eseguibili che non richiedono il runtime di Visual C++:
```toml
[target.x86_64-pc-windows-msvc]
rustflags = ["-C", "target-feature=+crt-static"]
```

Crea anche `crates/omi-import` e `crates/omi-mcp` con un `main.rs` minimo (stampa l'attribuzione), così il
workspace compila fin da subito.

## 3. Crate `omi-core`

| Modulo | Contenuto | Specifica |
|---|---|---|
| `about.rs` | costanti `NOME`, `VERSIONE`, `AUTORE`, `URL_PROGETTO` (da `option_env!("OMI_URL_PROGETTO")`), `FONTE_DATI`, funzione `attribuzione()` | 04 §1 |
| `db.rs` | `open(path, read_only)`, `ensure_schema`, `sem_label`, `sem_index`, `parse_semestre`, `print_summary(conn, &mut impl Write)` | 01 |
| `geometry.rs` | `Geometry`, `encode`/`decode`, `bbox`, `centroid_and_area`, `contains`, `distance_meters`, `to_geojson`, `round_half_even(x, decimali)` | 03 |
| `text.rs` | `norm`, `parse_decimal`, `parse_int`, `field`, `safe_file_name` | 02 §2, §8; 03 §6 |
| `error.rs` | `OmiError` con almeno `Validazione(String)` (messaggio da mostrare al client MCP), `DatiNonValidi(String)`, `Sqlite`, `Io`, `Zip`, `Xml` | 04 §6 |

I moduli `import` (fase 02) e `service` (fase 03) si aggiungono dopo.

## 4. Test unitari

- **Codifica:** vettore noto `01 01 03 02 04 04 06 05 09` (specifica 03 §3); andata e ritorno su un
  multipoligono con buchi, coordinate realistiche (es. 12 496 400, 41 902 800), delta negativi e varint su più
  byte; `decode` di un blob troncato → errore, non panic.
- **`contains`:** punto interno, esterno, dentro un buco, nel secondo poligono.
- **`distance_meters`:** segmento orizzontale con valore atteso calcolato a mano.
- **`centroid_and_area`:** quadrato di 0,01° a latitudine 45 con area attesa (tolleranza 1e-9); quadrato con buco.
- **Arrotondamento:** `round_half_even(0.5, 0) = 0`, `(1.5, 0) = 2`, `(2.5, 0) = 2`, `(-0.5, 0) = -0`.
- **`norm`:** i 4 casi di specifica 03 §6.
- **`parse_semestre`:** `2025/1` → 20251, `2025-2` → 20252, `20252`, `2025 S1` → 20251, `2025/3` → errore con
  il messaggio esatto, `""` e `"  "` → nessun semestre.
- **`safe_file_name`:** esempio di specifica 02 §8, varianti in minuscolo, nome senza codice fiscale invariato.
- **`field` / `parse_decimal`:** `" 'Centro' "` → `Centro`; `"''"` → NULL; `"1.234,5"` → NULL (non è un formato
  dei file OMI: documenta il comportamento); `"1234,5"` → 1234.5.
- **Schema:** `ensure_schema` su database in memoria, eseguito due volte, poi un `INSERT` in `geometria_rt`;
  verifica che l'SQLite incluso abbia il modulo R\*Tree (se manca, attivalo e annotalo in `DECISIONI.md`).
- **`print_summary`:** database vuoto → `Il database non contiene ancora dati OMI.`

Esegui `fmt`, `clippy` e `test`, fai un commit `fase 01: workspace e omi-core` e spunta la fase.
