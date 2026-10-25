# Specifica 01: database SQLite

Questa è la specifica normativa del database `omi.db`. Il DDL e le query vanno riprodotti **esattamente**,
perché il file deve restare compatibile con altri strumenti che usano lo stesso schema.

## 1. Convenzioni

| Elemento | Convenzione |
|---|---|
| Semestre | intero `AAAAS`, per esempio `20252` = 2° semestre 2025. Etichetta: `"{s/10}/{s%10}"` → `2025/2` |
| Indice del semestre (per le distanze tra semestri) | `s/10*2 + s%10` |
| Date di caricamento | testo `yyyy-MM-dd HH:mm:ss` in ora locale |
| Importi | `REAL`: compravendita in €/m², locazione in €/m² al mese |
| Codice comune | codice catastale (Belfiore), per esempio `H501` = Roma |
| Coordinate | WGS84; nelle geometrie si memorizzano in microgradi interi (vedi `03_geometria.md`) |

## 2. Apertura delle connessioni

- **In lettura e scrittura** (importatore): modalità *read-write-create*, poi
  `PRAGMA journal_mode=WAL; PRAGMA foreign_keys=OFF;`
- **In sola lettura** (server): modalità *read-only*, poi `PRAGMA query_only=1;`
- In entrambi i casi `busy_timeout` di 5 secondi.

SQLite deve essere compilato con il modulo **R\*Tree**.

## 3. DDL (da eseguire così com'è a ogni apertura in scrittura)

```sql
CREATE TABLE IF NOT EXISTS semestre (
    semestre            INTEGER PRIMARY KEY,   -- AAAAS
    anno                INTEGER NOT NULL,
    numero              INTEGER NOT NULL,      -- 1 o 2
    elaborazione_zone   TEXT,
    elaborazione_valori TEXT,
    file_csv            TEXT,
    caricato_csv        TEXT,
    file_kml            TEXT,
    caricato_kml        TEXT,
    n_zone              INTEGER,
    n_valori            INTEGER,
    n_geometrie         INTEGER
);

CREATE TABLE IF NOT EXISTS zona (
    semestre          INTEGER NOT NULL,
    link_zona         TEXT    NOT NULL,
    area_territoriale TEXT,
    regione           TEXT,
    prov              TEXT,
    comune_istat      TEXT,
    comune_cat        TEXT,
    sez               TEXT,
    comune_amm        TEXT    NOT NULL,   -- codice catastale (Belfiore) del comune
    comune_descr      TEXT,
    fascia            TEXT,               -- B centrale, C semicentrale, D periferica, E suburbana, R rurale
    zona              TEXT    NOT NULL,
    zona_descr        TEXT,
    cod_tip_prev      INTEGER,
    descr_tip_prev    TEXT,
    stato_prev        TEXT,
    microzona         INTEGER,
    PRIMARY KEY (semestre, link_zona)
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS ix_zona_comune ON zona(comune_amm, semestre, zona);
CREATE INDEX IF NOT EXISTS ix_zona_link ON zona(link_zona, semestre);

CREATE TABLE IF NOT EXISTS valore (
    semestre     INTEGER NOT NULL,
    link_zona    TEXT    NOT NULL,
    cod_tip      INTEGER NOT NULL,
    stato        TEXT    NOT NULL,   -- OTTIMO / NORMALE / SCADENTE (può essere vuoto)
    stato_prev   TEXT,               -- 'P' = stato conservativo prevalente
    compr_min    REAL,               -- €/m² compravendita
    compr_max    REAL,
    sup_nl_compr TEXT,               -- L lorda / N netta
    loc_min      REAL,               -- €/m² x mese locazione
    loc_max      REAL,
    sup_nl_loc   TEXT,
    PRIMARY KEY (semestre, link_zona, cod_tip, stato)
) WITHOUT ROWID;

CREATE TABLE IF NOT EXISTS tipologia (
    cod_tip     INTEGER PRIMARY KEY,
    descrizione TEXT
);

CREATE TABLE IF NOT EXISTS geometria (
    id        INTEGER PRIMARY KEY,
    hash      BLOB NOT NULL UNIQUE,
    min_lon   REAL, min_lat REAL, max_lon REAL, max_lat REAL,
    centro_lon REAL, centro_lat REAL,
    area_km2  REAL,
    n_poligoni INTEGER,
    n_punti   INTEGER,
    dati      BLOB NOT NULL        -- vedi 03_geometria.md
);
CREATE VIRTUAL TABLE IF NOT EXISTS geometria_rt USING rtree(id, min_lon, max_lon, min_lat, max_lat);

CREATE TABLE IF NOT EXISTS zona_geo (
    id           INTEGER PRIMARY KEY,
    semestre     INTEGER NOT NULL,
    comune_amm   TEXT    NOT NULL,
    zona         TEXT    NOT NULL,
    link_zona    TEXT,
    nome         TEXT,
    colore       TEXT,             -- colore del poligono nel KML (AABBGGRR)
    geometria_id INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_zona_geo_zona ON zona_geo(comune_amm, zona, semestre);
CREATE INDEX IF NOT EXISTS ix_zona_geo_geom ON zona_geo(geometria_id, semestre);
CREATE INDEX IF NOT EXISTS ix_zona_geo_sem ON zona_geo(semestre);

CREATE TABLE IF NOT EXISTS comune (
    comune_amm        TEXT PRIMARY KEY,
    comune_istat      TEXT,
    descrizione       TEXT,
    prov              TEXT,
    regione           TEXT,
    area_territoriale TEXT,
    primo_semestre    INTEGER,
    ultimo_semestre   INTEGER
);
CREATE INDEX IF NOT EXISTS ix_comune_istat ON comune(comune_istat);

CREATE TABLE IF NOT EXISTS comune_nome (
    comune_amm TEXT NOT NULL,
    nome       TEXT NOT NULL,
    nome_norm  TEXT NOT NULL,
    prov       TEXT,
    PRIMARY KEY (comune_amm, nome, prov)
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS ix_comune_nome_norm ON comune_nome(nome_norm);

CREATE TABLE IF NOT EXISTS file_caricato (
    file        TEXT PRIMARY KEY,
    dimensione  INTEGER,
    semestre    INTEGER,
    contenuto   TEXT,
    caricato    TEXT
);
```

### Significato delle tabelle

| Tabella | Contenuto |
|---|---|
| `semestre` | semestri caricati, con data di elaborazione dell'Agenzia, file sorgente (nome ripulito) e conteggi |
| `zona` | una riga per zona OMI e semestre, dal file `*_ZONE.csv`; chiave `(semestre, link_zona)` |
| `valore` | quotazioni dal file `*_VALORI.csv`; chiave `(semestre, link_zona, cod_tip, stato)` |
| `tipologia` | codice e descrizione delle tipologie edilizie (es. 20 = Abitazioni civili, 13 = Box) |
| `geometria` | poligoni delle zone, deduplicati tra semestri tramite `hash` |
| `geometria_rt` | indice spaziale R\*Tree sui bbox delle geometrie |
| `zona_geo` | collegamento semestre + comune + zona → geometria (dai KML) |
| `comune` | anagrafica dei comuni (dati dell'ultimo semestre) con primo e ultimo semestre disponibile |
| `comune_nome` | nomi dei comuni, anche storici, normalizzati per la ricerca |
| `file_caricato` | registro dei file importati, **senza** il codice fiscale nel nome |

## 4. Riepilogo del contenuto (`print_summary`)

Query (con `ult` = ultimo semestre):

```sql
SELECT max(semestre) FROM semestre WHERE n_zone>0                              -- ult; se NULL vedi sotto
SELECT coalesce(elaborazione_valori, elaborazione_zone) FROM semestre WHERE semestre={ult}
SELECT max(caricato) FROM file_caricato
SELECT min(semestre) FROM semestre WHERE n_zone>0
SELECT count(*) FROM semestre WHERE n_zone>0
SELECT count(*) FROM semestre WHERE n_geometrie>0
SELECT count(DISTINCT comune_amm) FROM zona WHERE semestre={ult}
SELECT count(*) FROM comune
SELECT n_zone FROM semestre WHERE semestre={ult}
```

Se `ult` è NULL si stampa solo `Il database non contiene ancora dati OMI.` Altrimenti si stampa
(la data di `max(caricato)` convertita in `dd/MM/yyyy HH:mm`, oppure `n.d.` se manca o non è nel formato atteso):

```
Contenuto del database:
  Ultimo aggiornamento:     {data}
  Ultimo semestre caricato: {AAAA/S} (elaborazione Agenzia del {elab})
  Semestri disponibili:     {n} ({primo AAAA/S} - {ult AAAA/S}), {n_geo} con perimetri
  Comuni censiti:           {comuni_ult} nell'ultimo semestre ({zone_ult} zone), {comuni_tot} in totale nella serie storica
```

La parte ` (elaborazione Agenzia del {elab})` si omette se `elab` è NULL.

## 5. Parsing del semestre (`parse_semestre`)

- Input vuoto, assente o di soli spazi → nessun semestre (si userà l'ultimo).
- Altrimenti si tengono **solo le cifre** dell'input: il semestre è valido se le cifre sono esattamente 5 e
  l'ultima è `1` o `2`. Esempi validi: `2025/1`, `2025-1`, `20251`, `2025 1`, `2025S1`.
- Errore: `Semestre non valido: '{input}'. Usare il formato AAAA/S, es. 2025/1.`

## 6. Esempio di query diretta (per il manuale)

```sql
SELECT z.comune_descr, z.zona, z.zona_descr, v.compr_min, v.compr_max, v.loc_min, v.loc_max
FROM zona z JOIN valore v ON v.semestre = z.semestre AND v.link_zona = z.link_zona
WHERE z.semestre = 20252 AND z.comune_amm = 'F205' AND v.cod_tip = 20 AND v.stato_prev = 'P'
ORDER BY v.compr_max DESC;
```
