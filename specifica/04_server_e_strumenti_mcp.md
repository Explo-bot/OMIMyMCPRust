# Specifica 04: server MCP e strumenti

## 1. Identità del programma

| Costante | Valore |
|---|---|
| `NOME` | `OMIMyMCP` |
| `VERSIONE` | `1.0.0` (da `CARGO_PKG_VERSION`) |
| `AUTORE` | `Explobot` |
| `URL_PROGETTO` | facoltativo: impostato a compilazione con la variabile d'ambiente `OMI_URL_PROGETTO` (`option_env!`); di default assente |
| `FONTE_DATI` | `Agenzia Entrate - OMI` |
| `attribuzione()` | `"{NOME} {VERSIONE} di {AUTORE}"` + (se c'è l'URL) `" - {URL_PROGETTO}"` + `" (licenza Apache-2.0)"` |

## 2. Trasporto e rotte HTTP

- MCP su HTTP *streamable* all'indirizzo `/mcp` (POST, GET, DELETE), **senza stato** tra le richieste
  (nessuna sessione da mantenere).
- `GET /` → `text/plain; charset=utf-8`:
  `"{attribuzione}\nServer MCP - endpoint: /mcp\nFonte dei dati: {FONTE_DATI}\n"`
- `GET /health` → `200 ok` se il database risponde a `SELECT 1`, altrimenti `503`.
- Il server apre il database **solo in lettura** e non lo crea mai.

## 3. `initialize`

- `serverInfo`: `name = "OMIMyMCP"`, `title = "OMIMyMCP - Quotazioni immobiliari OMI"`, `version = "1.0.0"`;
  se il campo esiste nell'SDK, `description = attribuzione()`; `websiteUrl = URL_PROGETTO` solo se definito.
- Capacità: solo `tools`.
- `instructions`:
  > Server MCP sulle quotazioni immobiliari OMI (Agenzia delle Entrate): zone OMI per comune, ricerca per coordinate, quotazioni di compravendita e locazione per semestre, serie storiche. Quando presenti risultati basati su questi dati cita la fonte "Agenzia Entrate - OMI". Software: {attribuzione}.

## 4. Elenco degli strumenti

Tutti hanno le annotazioni `readOnlyHint: true` e `idempotentHint: true`. Descrizioni da copiare **esattamente**.
Ogni risultato è **un solo blocco di testo** con un JSON compatto.

| Tool | Descrizione |
|---|---|
| `elenco_semestri` | Elenca i semestri OMI caricati nel database con numero di zone, quotazioni e perimetri disponibili. |
| `elenco_tipologie` | Elenca le tipologie edilizie OMI (codice e descrizione), es. 20 = Abitazioni civili, 13 = Box. |
| `cerca_comuni` | Cerca comuni per nome (anche parziale, senza accenti), codice catastale (es. H501) o codice ISTAT. Restituisce codici, provincia, regione e semestri disponibili. |
| `zone_comune` | Elenca le zone OMI di un comune in un semestre: codice zona, LinkZona, fascia, descrizione, microzona, tipologia e stato prevalenti. Facoltativamente include quotazioni e dati del perimetro (centro, bbox, area). |
| `dettaglio_zona` | Tutti i dati di una zona OMI in un semestre: anagrafica zona e comune, quotazioni di compravendita (€/m²) e locazione (€/m² mese) per tipologia e stato conservativo, dati del perimetro e, se richiesto, la geometria GeoJSON. |
| `zona_da_coordinate` | Individua la zona OMI che contiene un punto (latitudine/longitudine WGS84) e restituisce comune, zona, quotazioni e perimetro. Se il punto non ricade in alcuna zona restituisce la più vicina entro 2 km. |
| `zone_vicine` | Elenca le zone OMI entro un raggio (metri) da un punto, ordinate per distanza, con le quotazioni delle abitazioni civili. |
| `storico_zona` | Serie storica delle quotazioni di una zona OMI su tutti i semestri caricati, per tipologia e stato conservativo. |
| `statistiche_comune` | Riepilogo delle quotazioni di un comune in un semestre: minimo, massimo e medio per tipologia e medie delle abitazioni civili per fascia (centrale, semicentrale, periferica, ...). |

### Parametri

`*` = obbligatorio. I tipi sono quelli dello schema JSON di input.

| Tool | Parametro | Tipo | Default | Descrizione |
|---|---|---|---|---|
| `cerca_comuni` | `testo`* | string | | Nome del comune, codice catastale o codice ISTAT |
| | `provincia` | string | null | Sigla della provincia per filtrare (es. RM), facoltativa |
| `zone_comune` | `comune`* | string | | Nome del comune, codice catastale o codice ISTAT |
| | `provincia` | string | null | Sigla provincia, utile se il nome è ambiguo |
| | `semestre` | string | null | Semestre nel formato AAAA/S (es. 2025/1); se omesso l'ultimo disponibile |
| | `includi_valori` | boolean | false | Includere le quotazioni di tutte le tipologie per ogni zona |
| | `includi_perimetri` | boolean | false | Includere centro, bbox e area del perimetro di ogni zona |
| `dettaglio_zona` | `comune`* | string | | Nome del comune, codice catastale o codice ISTAT |
| | `zona`* | string | | Codice zona OMI (es. B1, C2, R1) oppure LinkZona (es. RM00000123) |
| | `provincia` | string | null | Sigla provincia, utile se il nome è ambiguo |
| | `semestre` | string | null | Semestre AAAA/S; se omesso l'ultimo disponibile |
| | `includi_geometria` | boolean | false | Includere le coordinate del perimetro in formato GeoJSON MultiPolygon |
| `zona_da_coordinate` | `latitudine`* | number | | Latitudine in gradi decimali WGS84 (es. 41.9028) |
| | `longitudine`* | number | | Longitudine in gradi decimali WGS84 (es. 12.4964) |
| | `semestre` | string | null | Semestre AAAA/S; se omesso l'ultimo disponibile |
| | `includi_geometria` | boolean | false | Includere la geometria GeoJSON della zona |
| `zone_vicine` | `latitudine`* | number | | Latitudine WGS84 |
| | `longitudine`* | number | | Longitudine WGS84 |
| | `raggio_m` | number | 1000 | Raggio in metri (max 20000) |
| | `semestre` | string | null | Semestre AAAA/S; se omesso l'ultimo disponibile |
| `storico_zona` | `comune`* | string | | Nome del comune, codice catastale o codice ISTAT |
| | `zona`* | string | | Codice zona OMI (es. B1) o LinkZona |
| | `provincia` | string | null | Sigla provincia, utile se il nome è ambiguo |
| | `cod_tipologia` | integer | null | Codice tipologia (es. 20 abitazioni civili); se omesso tutte |
| | `stato` | string | null | Stato conservativo: OTTIMO, NORMALE o SCADENTE; se omesso tutti |
| `statistiche_comune` | `comune`* | string | | Nome del comune, codice catastale o codice ISTAT |
| | `provincia` | string | null | Sigla provincia, utile se il nome è ambiguo |
| | `semestre` | string | null | Semestre AAAA/S; se omesso l'ultimo disponibile |

`elenco_semestri` ed `elenco_tipologie` non hanno parametri. Numeri e booleani passati come stringa
(`"20"`, `"true"`) vanno accettati.

## 5. Regole di serializzazione JSON

1. Le chiavi escono **nell'ordine in cui sono elencate** negli schemi del §8.
2. Una proprietà con valore `null` **si omette** (a tutti i livelli). Unica eccezione: le righe di
   `elenco_tipologie`, che mantengono `"descrizione": null`.
3. I numeri reali con parte decimale nulla e valore assoluto < 2^53 si scrivono **senza** `.0` (`1500`, non
   `1500.0`); gli altri con la rappresentazione più breve che si rilegge identica (quella di `ryu`). I valori
   INTEGER del database restano interi.
4. Nessun escape dei caratteri non ASCII; escape solo di `"`, `\` e dei caratteri di controllo. Nessuna indentazione.
5. Le etichette di semestre sono stringhe `AAAA/S`.

## 6. Errori

- **Errori di validazione** (testi del §7 e §8): risultato del tool con `isError: true` e il messaggio come testo.
- **Altri errori** (database, decodifica, panic): `isError: true` con
  `Errore interno durante l'esecuzione di '{tool}'.`; i dettagli vanno solo nel log.

## 7. Funzioni comuni

### Tabelle di decodifica
- Fasce: `B` Centrale, `C` Semicentrale, `D` Periferica, `E` Suburbana, `R` Extraurbana/rurale.
- Stati: `N` NORMALE, `O` OTTIMO, `S` SCADENTE (qualunque altro valore resta com'è).
- Superficie: `L` → `lorda`, `N` → `netta`, altro → invariato.

### `resolve_semestre(semestre)`
- Se `parse_semestre` (vedi `01_database.md`) restituisce un valore: deve esistere
  `SELECT 1 FROM semestre WHERE semestre=? AND n_zone>0`, altrimenti
  `Semestre {AAAA/S} non presente nel database. Usare elenco_semestri.`
- Altrimenti `SELECT max(semestre) FROM semestre WHERE n_zone>0`; se NULL: `Il database non contiene dati OMI.`

### `geo_semestre(sem)`: semestre con perimetri più vicino
```sql
SELECT semestre FROM semestre WHERE n_geometrie>0 ORDER BY abs((semestre/10)*2+semestre%10-@i), semestre DESC LIMIT 1
```
con `@i = indice(sem)`. Se non c'è: `Nel database non sono presenti perimetri di zona (file KML).`

### `find_comuni(testo, provincia)`
`t = trim(testo)`; `T = maiuscolo(t)`; `P = maiuscolo(trim(provincia))` oppure nessuna provincia se vuota.
1. Se `T` corrisponde a `^[A-Z]\d{3}$`: `SELECT c.* FROM comune c WHERE c.comune_amm=?` con `T`.
2. Altrimenti, se `T` è composto solo da cifre (anche vuoto):
   `SELECT c.* FROM comune c WHERE c.comune_istat=?1 OR substr(c.comune_istat,-6)=substr('000000'||?1,-6)`.
3. Altrimenti, con `n = norm(t)`, il primo dei tre tentativi che restituisce righe:
   - `SELECT c.* FROM comune c WHERE c.comune_amm IN (SELECT comune_amm FROM comune_nome WHERE nome_norm=?)` con `n`;
   - `… WHERE nome_norm LIKE ?) ORDER BY c.descrizione LIMIT 200` con `n%`;
   - stessa query con `%n%`.
4. Se c'è `P`, si tengono le righe con `prov` uguale a `P` senza distinzione di maiuscole **oppure** con
   `norm(prov) == norm(P)`.

### `comune_info(r)`
```json
{"codice_catastale": comune_amm, "codice_istat": comune_istat, "nome": descrizione, "provincia": prov,
 "regione": regione, "area_territoriale": area_territoriale,
 "primo_semestre": "AAAA/S", "ultimo_semestre": "AAAA/S"}
```

### `resolve_comune(comune, provincia)`
- 1 risultato → quello.
- 0 risultati → `Nessun comune trovato per '{comune}'` + (se la provincia è stata passata) ` in provincia {provincia}` + `.`
- Più risultati: se uno solo ha `norm(descrizione) == norm(comune)`, quello; altrimenti
  `'{comune}' è ambiguo, specificare la provincia o il codice catastale. Candidati: ` seguito dai primi 20
  nella forma `{descrizione} ({prov}) [{comune_amm}]`, separati da `, `.
- Esempio: `'samone' è ambiguo, specificare la provincia o il codice catastale. Candidati: SAMONE (TO) [H753], SAMONE (TN) [H754]`

### `zona_info(z)` (da una riga di `zona`)
```json
{"zona": zona, "link_zona": link_zona, "fascia": fascia, "fascia_descr": <decodifica fascia>,
 "descrizione": zona_descr, "microzona": microzona,
 "tipologia_prevalente": {"codice": cod_tip_prev, "descrizione": descr_tip_prev},   // assente se cod_tip_prev è NULL
 "stato_prevalente": <decodifica stato_prev>, "comune_catastale": comune_cat, "sezione": sez}
```

### `valori(sem, link_zona)`
```sql
SELECT v.*, t.descrizione AS tip_descr FROM valore v LEFT JOIN tipologia t ON t.cod_tip=v.cod_tip
WHERE v.semestre=? AND v.link_zona=? ORDER BY v.cod_tip, v.stato
```
Per ogni riga:
```json
{"cod_tipologia": cod_tip, "tipologia": tip_descr, "stato": stato (assente se vuoto),
 "stato_prevalente": true (solo se stato_prev = 'P', altrimenti assente),
 "compravendita_eur_mq": {"min": compr_min, "max": compr_max, "superficie": <decodifica sup_nl_compr>},   // assente se min e max sono entrambi NULL
 "locazione_eur_mq_mese": {"min": loc_min, "max": loc_max, "superficie": <decodifica sup_nl_loc>}}      // idem
```

### `geo_info(comune_amm, zona, link_zona, sem, includi_geometria)`
```sql
SELECT zg.semestre, zg.link_zona, zg.colore, g.id, g.min_lon, g.min_lat, g.max_lon, g.max_lat, g.centro_lon, g.centro_lat,
       g.area_km2, g.n_poligoni, g.n_punti, g.dati
FROM zona_geo zg JOIN geometria g ON g.id=zg.geometria_id
WHERE zg.comune_amm=? AND zg.zona=?
ORDER BY abs((zg.semestre/10)*2+zg.semestre%10-@i), zg.semestre DESC
```
Nessuna riga → `null` (quindi la proprietà si omette). Altrimenti `gs` = semestre della prima riga; si tengono
le righe con quel semestre; se sono più di una e `link_zona` è noto, si preferiscono quelle con lo stesso
`link_zona` (se ce ne sono); si usa la prima:
```json
{"semestre_perimetro": "AAAA/S", "centro": {"lat": centro_lat, "lon": centro_lon},
 "bbox": {"min_lat": …, "min_lon": …, "max_lat": …, "max_lon": …},
 "area_km2": …, "n_poligoni": …, "n_punti": …, "colore_kml": colore,
 "geometria": <GeoJSON, solo se includi_geometria>}
```

### `zona_completa(z, sem, includi_geometria)`
`{"info": zona_info(z), "valori": [valori(sem, z.link_zona)], "perimetro": geo_info(z.comune_amm, z.zona, z.link_zona, sem, includi_geometria)}`

## 8. Comportamento dei singoli strumenti

### `elenco_semestri`
`SELECT * FROM semestre ORDER BY semestre DESC` →
```json
{"semestri": [{"semestre": "AAAA/S", "n_zone": …, "n_valori": …, "n_perimetri": n_geometrie,
               "elaborazione": elaborazione_valori ?? elaborazione_zone, "file_csv": …, "file_kml": …}],
 "nota": "I perimetri (KML) sono disponibili solo per alcuni semestri; per gli altri la ricerca per coordinate usa i perimetri del semestre più vicino.",
 "fonte_dati": "Agenzia Entrate - OMI", "software": attribuzione()}
```

### `elenco_tipologie`
`SELECT cod_tip AS codice, descrizione FROM tipologia ORDER BY cod_tip` → array di `{"codice": …, "descrizione": …}`
(con `null` mantenuto).

### `cerca_comuni`
`{"trovati": <numero totale>, "comuni": [comune_info dei primi 50]}`

### `zone_comune`
Ordine: prima `resolve_comune`, poi `resolve_semestre` (determina quale errore esce per primo).
`SELECT * FROM zona WHERE comune_amm=? AND semestre=? ORDER BY fascia, zona` →
```json
{"comune": comune_info, "semestre": "AAAA/S", "n_zone": …,
 "zone": [{"info": zona_info, "perimetro": geo_info(senza geometria; solo se includi_perimetri),
           "valori": [ … ] (solo se includi_valori)}],
 "nota": "Nessuna zona per il comune nel semestre indicato."   // solo se n_zone = 0
}
```

### `dettaglio_zona`
1. `sem = resolve_semestre(semestre)`; `Z = maiuscolo(trim(zona))`.
2. Prima prova `Z` come LinkZona: `SELECT * FROM zona WHERE link_zona=? AND semestre=?`.
3. Se non trova nulla: `resolve_comune(comune, provincia)`, poi `SELECT * FROM zona WHERE comune_amm=? AND zona=? AND semestre=?`.
4. Se ancora nulla: `Zona '{zona}' non trovata per il comune indicato nel semestre {AAAA/S}. Usare zone_comune per l'elenco.`
5. Se il comune non è stato risolto al punto 3: `SELECT * FROM comune WHERE comune_amm=?` con il comune della prima zona (può mancare).
6. Risultato: `{"comune": comune_info (se c'è), "semestre": "AAAA/S", "zone": [zona_completa …]}`.

### `zona_da_coordinate`
1. `sem = resolve_semestre`; `gs = geo_semestre(sem)`.
2. Candidati con margine 0 (`03_geometria_e_testo.md` §5); `interni` = quelli con distanza 0.
3. Se non ce ne sono: candidati con margine `0.02`, tenendo quelli con distanza ≤ 2000, ordinati per distanza
   (ordinamento stabile). Se vuoto:
   `{"trovato": false, "lat": …, "lon": …, "semestre": "AAAA/S", "messaggio": "Nessuna zona OMI contiene il punto né si trova entro 2 km."}`.
   Altrimenti `interni` = [il primo] e `approssimato = true`.
4. Per ogni elemento di `interni` (`dati_zona_per_hit`):
   - `SELECT * FROM zona WHERE comune_amm=? AND zona=? AND semestre=?` (sem richiesto); se più righe e il
     candidato ha `link_zona`, si preferiscono quelle con lo stesso `link_zona`;
   - `SELECT * FROM comune WHERE comune_amm=?`;
   - `{"comune": comune_info oppure {"codice_catastale": …}, "zona": …, "distanza_m": round_half_even(distanza) (solo se > 0),
      "dati": [zona_completa …], "nota": "La zona {zona} individuata dal perimetro non esiste nei dati del semestre {AAAA/S} (codici zona cambiati tra le revisioni)." (solo se nessuna riga)}`
5. Risultato:
```json
{"trovato": true, "lat": …, "lon": …, "semestre": "AAAA/S", "semestre_perimetri": "AAAA/S",
 "approssimato": true (solo se approssimato),
 "nota": "Il punto non ricade in alcun perimetro OMI: restituita la zona più vicina."            // se approssimato
       | "Perimetri non disponibili per il semestre richiesto: usati quelli del semestre più vicino, collegati per codice zona."   // altrimenti, se gs ≠ sem
 "risultati": [ … ]}
```

### `zone_vicine`
1. `sem = resolve_semestre`; `gs = geo_semestre(sem)`; `r = clamp(raggio_m, 0, 20000)`.
2. `margine = r / 111000.0 / max(0.2, cos(lat·π/180))`.
3. Candidati con quel margine e distanza ≤ `r`; per ogni coppia (comune_amm, zona) si tiene quello a distanza
   minima; ordinamento stabile per distanza; massimo 100.
4. Per ciascuno: riga di `zona` (prima di `SELECT * FROM zona WHERE comune_amm=? AND zona=? AND semestre=?`),
   `SELECT descrizione, prov FROM comune WHERE comune_amm=?` e, se la zona esiste,
   ```sql
   SELECT compr_min, compr_max, loc_min, loc_max, stato FROM valore WHERE semestre=? AND link_zona=? AND cod_tip=20
   ORDER BY (stato_prev='P') DESC LIMIT 1
   ```
   ```json
   {"comune": "{descrizione} ({prov})" oppure il codice catastale, "codice_catastale": …, "zona": …,
    "link_zona": …, "fascia": …, "descrizione": zona_descr, "distanza_m": round_half_even(d),
    "abitazioni_civili": {"stato": …, "compr_min": …, "compr_max": …, "loc_min": …, "loc_max": …}}
   ```
5. Risultato: `{"lat", "lon", "raggio_m": r, "semestre", "semestre_perimetri", "n", "zone": [ … ]}`.

### `storico_zona`
1. `resolve_comune`; `Z = maiuscolo(trim(zona))`; `ST = maiuscolo(trim(stato))` se presente.
2. Query:
```sql
SELECT z.semestre, z.link_zona, z.zona_descr, z.fascia, v.cod_tip, t.descrizione AS tip_descr, v.stato, v.stato_prev,
       v.compr_min, v.compr_max, v.loc_min, v.loc_max
FROM zona z JOIN valore v ON v.semestre=z.semestre AND v.link_zona=z.link_zona
LEFT JOIN tipologia t ON t.cod_tip=v.cod_tip
WHERE z.comune_amm=@c AND (z.zona=@z OR z.link_zona=@z)
  AND (@t IS NULL OR v.cod_tip=@t) AND (@st IS NULL OR v.stato=@st)
ORDER BY v.cod_tip, v.stato, z.semestre
```
3. `serie`: righe raggruppate per `(cod_tip, tip_descr, stato)` **nell'ordine di prima comparsa**:
   `{"cod_tipologia", "tipologia", "stato" (assente se vuoto), "valori": [{"semestre", "compr_min", "compr_max", "loc_min", "loc_max", "prevalente": true (solo se stato_prev='P')}]}`.
4. `descrizioni_zona`: righe raggruppate per `zona_descr` nell'ordine di prima comparsa:
   `{"descrizione", "dal": min semestre, "al": max semestre}`.
5. Risultato: `{"comune", "zona": Z, "descrizioni_zona", "n_serie", "serie", "nota"}` con nota
   `Nessun dato: verificare codice zona (zone_comune) o filtri.` se non ci sono serie, altrimenti
   `I codici zona OMI possono essere stati ridefiniti nelle revisioni della zonizzazione: confrontare le descrizioni.`

### `statistiche_comune`
Prima `resolve_comune`, poi `resolve_semestre`.
```sql
-- per tipologia
SELECT v.cod_tip, t.descrizione AS tip_descr, count(DISTINCT v.link_zona) AS n_zone,
       min(v.compr_min) AS compr_min, max(v.compr_max) AS compr_max, round(avg((v.compr_min+v.compr_max)/2.0),1) AS compr_medio,
       min(v.loc_min) AS loc_min, max(v.loc_max) AS loc_max, round(avg((v.loc_min+v.loc_max)/2.0),2) AS loc_medio
FROM zona z JOIN valore v ON v.semestre=z.semestre AND v.link_zona=z.link_zona
LEFT JOIN tipologia t ON t.cod_tip=v.cod_tip
WHERE z.comune_amm=@c AND z.semestre=@s AND (v.stato_prev='P' OR NOT EXISTS (
    SELECT 1 FROM valore v2 WHERE v2.semestre=v.semestre AND v2.link_zona=v.link_zona AND v2.cod_tip=v.cod_tip AND v2.stato_prev='P'))
GROUP BY v.cod_tip ORDER BY v.cod_tip

-- per fascia
SELECT z.fascia, count(*) AS n_zone,
       round(avg((v.compr_min+v.compr_max)/2.0),1) AS abitazioni_civili_compr_medio,
       round(avg((v.loc_min+v.loc_max)/2.0),2) AS abitazioni_civili_loc_medio
FROM zona z LEFT JOIN valore v ON v.semestre=z.semestre AND v.link_zona=z.link_zona AND v.cod_tip=20 AND v.stato_prev='P'
WHERE z.comune_amm=@c AND z.semestre=@s GROUP BY z.fascia ORDER BY z.fascia
```
```json
{"comune", "semestre",
 "nota": "Valori €/m² (locazione €/m² mese) calcolati sullo stato conservativo prevalente di ciascuna zona.",
 "per_tipologia": [{"cod_tipologia", "tipologia", "n_zone",
                    "compravendita": {"min", "max", "medio"}, "locazione": {"min", "max", "medio"}}],
 "per_fascia": [{"fascia", "fascia_descr", "n_zone", "abitazioni_civili_compr_medio", "abitazioni_civili_loc_medio"}]}
```

## 9. Log del server (opzione `/l`)

- File: stesso percorso del database con estensione `.log` (`omi.db` → `omi.log`), in **append**, mai svuotato.
  Un errore di scrittura non deve mai bloccare il server.
- Ogni riga: `{yyyy-MM-dd HH:mm:ss.fff, ora locale} {messaggio}`, su console (se c'è) e su file.
- All'avvio: `Log attivo, file: {percorso}`.
- Per ogni richiesta HTTP: `HTTP {ip client} {metodo} {percorso} -> {status} ({ms} ms)`.
- Per ogni chiamata a un tool:
  `TOOL {nome} {argomenti in JSON compatto, oppure {} se assenti} -> ok, {n} caratteri ({ms} ms)` oppure
  `TOOL {nome} {argomenti} -> ERRORE: {messaggio} ({ms} ms)`, dove `{n}` è la lunghezza del testo della
  risposta in **unità UTF-16** (`encode_utf16().count()`).
- Esempi:
  ```
  2026-09-27 09:20:53.747 TOOL cerca_comuni {"testo":"Asti"} -> ok, 215 caratteri (39 ms)
  2026-09-27 09:20:53.766 HTTP ::1 POST /mcp -> 200 (185 ms)
  2026-09-27 09:20:53.822 TOOL dettaglio_zona {"zona":"R1","comune":"samone"} -> ERRORE: 'samone' è ambiguo, specificare la provincia o il codice catastale. Candidati: SAMONE (TO) [H753], SAMONE (TN) [H754] (4 ms)
  ```
- Il log contiene IP e testi delle richieste: va trattato come dato personale.
