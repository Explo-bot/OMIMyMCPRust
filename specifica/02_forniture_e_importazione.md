# Specifica 02: forniture OMI e algoritmo di importazione

## 1. Le forniture dell'Agenzia delle Entrate

L'Agenzia delle Entrate distribuisce i dati OMI tramite il servizio **Forniture dati OMI**, riservato agli utenti
autenticati. La descrizione ufficiale del servizio è su
<https://www.agenziaentrate.gov.it/portale/it/web/guest/schede/fabbricatiterreni/omi/forniture-dati-omi>.

| Fornitura | Disponibile da | File ottenuto | Contenuto |
|---|---|---|---|
| Quotazioni immobiliari | 1° semestre 2004 | `QI<n. richiesta>_<codice fiscale>.zip` (circa 2 MB per l'Italia) | `…_AAAAS_ZONE.csv`, `…_AAAAS_VALORI.csv` |
| Perimetri delle zone OMI | 2° semestre 2010 | `QIP<n. richiesta>_<codice fiscale>.zip` (40–130 MB per l'Italia) | gli stessi due CSV **più** un file `.kml` per comune (`<codice catastale>.kml`) |

- Ogni file riguarda **un solo semestre**. L'ambito territoriale può essere nazionale, regionale, provinciale o
  comunale; forniture parziali dello stesso semestre si sommano.
- Dal 2° semestre 2010 basta la fornitura dei perimetri, che contiene anche le quotazioni; per i semestri
  dal 2004/1 al 2010/1 esistono solo le quotazioni.
- L'intera serie 2004–2025 occupa circa 3,5 GB di ZIP e produce un database di circa 2 GB.
- **Privacy:** il nome del file contiene il codice fiscale di chi ha fatto la richiesta. Gli ZIP non vanno
  condivisi e nel database si registra solo il nome ripulito (§8).

### Procedura di download (per il manuale)

1. Aprire la pagina del servizio indicata sopra e premere **Accedi al servizio** (oppure
   <https://telematici.agenziaentrate.gov.it/Main/index.jsp>).
2. Autenticarsi con SPID, CIE, CNS o credenziali Fisconline/Entratel.
3. Aprire **Forniture dati OMI** (se non compare nel menu, usare la ricerca dell'area riservata).
4. Scegliere la fornitura, l'ambito territoriale e il semestre, poi inviare la richiesta.
5. Le richieste sono elaborate in modo asincrono: il file compare nell'elenco delle forniture richieste, di
   solito dopo pochi minuti.
6. Salvare tutti gli ZIP in una stessa cartella, **senza rinominarli né estrarli**.

Per scaricare molti semestri si può delegare la procedura a Claude con un browser (per esempio Claude in
Chrome). L'autenticazione resta interattiva: le credenziali non vanno mai scritte nel prompt.

## 2. Formato dei CSV

- Codifica UTF-8 (rimuovere un eventuale BOM; sostituire i byte non validi invece di fallire).
- Righe separate da `\n`, `\r\n` o `\r`. **Riga 1:** titolo. **Riga 2:** intestazione. Dalla riga 3: dati.
  Le righe vuote si saltano.
- Separatore `;`, **senza** virgolette di quotatura: si divide la riga su ogni `;`.
- Nomi di colonna ripuliti dagli spazi, confrontati senza distinzione di maiuscole; nomi vuoti ignorati; se
  un nome compare due volte vale l'ultima colonna; campi mancanti in coda = assenti; colonne non elencate
  qui = ignorate.
- Pulizia di ogni campo (`field`): trim; se inizia **e** finisce con `'` e ha almeno 2 caratteri, si tolgono
  gli apici e si fa di nuovo trim; stringa vuota → valore assente (NULL).
- Numeri decimali (`parse_decimal`): trim, `,` → `.`, parsing di un numero in virgola mobile; se non valido →
  NULL. Interi (`parse_int`): trim e parsing di un intero con segno facoltativo; se non valido → NULL.

**Titolo.** Da esso si ricavano il semestre e la data di elaborazione con queste espressioni regolari
(senza distinzione di maiuscole):
- semestre: `Semestre\s+(\d{4})\s*/\s*(\d)` → `anno*10 + s`;
- data di elaborazione: `elaborazione del\s+(.+)$` applicata al titolo ripulito; il valore è il gruppo 1 ripulito.

Esempio **sintetico** di titolo compatibile (il testo reale può differire, ma deve rispettare le regex):
`Quotazioni OMI - Semestre 2025/2 - elaborazione del 12/03/2026`

**Colonne di `*_ZONE.csv` usate:** `Area_territoriale`, `Regione`, `Prov`, `Comune_ISTAT`, `Comune_cat`,
`Sez`, `Comune_amm`, `Comune_descrizione`, `Fascia`, `Zona`, `Zona_Descr`, `Cod_tip_prev`,
`Descr_tip_prev`, `Stato_prev`, `LinkZona`, `Microzona`.

**Colonne di `*_VALORI.csv` usate:** `LinkZona`, `Cod_Tip`, `Descr_Tipologia`, `Stato`, `Stato_prev`,
`Compr_min`, `Compr_max`, `Sup_NL_compr`, `Loc_min`, `Loc_max`, `Sup_NL_loc` (nei file reali ci sono anche
colonne anagrafiche del comune e della zona, da ignorare).

Nota: `Comune_ISTAT` nei CSV OMI può contenere un prefisso, per esempio `1006003` per l'ISTAT `006003`.

## 3. Formato dei KML

Un file per comune, con nome `<codice catastale>.kml`. Struttura tipica (esempio **sintetico**):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2"><Document>
  <Style id="s1"><PolyStyle><color>7f00ff00</color></PolyStyle></Style>
  <Placemark>
    <name>ROMA - Zona OMI B1</name>
    <description><![CDATA[<b>Semestre 2025/2</b> ...]]></description>
    <styleUrl>#s1</styleUrl>
    <ExtendedData>
      <Data name="LINKZONA"><value>RM00000001</value></Data>
      <Data name="CODCOM"><value>H501</value></Data>
      <Data name="CODZONA"><value>B1</value></Data>
    </ExtendedData>
    <MultiGeometry>
      <Polygon>
        <outerBoundaryIs><LinearRing><coordinates>12.48,41.89,0 12.49,41.89,0 12.49,41.90,0 12.48,41.89,0</coordinates></LinearRing></outerBoundaryIs>
        <innerBoundaryIs><LinearRing><coordinates>…</coordinates></LinearRing></innerBoundaryIs>
      </Polygon>
    </MultiGeometry>
  </Placemark>
</Document></kml>
```

Dettagli rilevanti:
- Alcuni KML dichiarano UTF-8 ma contengono caratteri Latin-1: si decodifica in **UTF-8 stretto** e, se
  fallisce, in **Latin-1** (ogni byte diventa il carattere U+00XX), ignorando la codifica dichiarata.
- Alcuni KML sono malformati: si recupera ciò che si può (§6.3). Caso reale noto: semestre 2011/1, file
  `C302.kml` (Castiglione Chiavarese), zona B1 senza geometria valida.
- Il semestre di un KML si trova nella `description` dei placemark con la regex `(\d{4})\s*/\s*([12])`.
- Le descrizioni HTML dei placemark **non** si conservano nel database.

## 4. Elaborazione di un file ZIP (`import_zip`)

Tutto ciò che riguarda un file avviene **in una sola transazione**: in caso di errore si fa rollback e il
database resta com'era prima di quel file.

1. Stampa `Import di {nome del file} ({dimensione in MB, 1 decimale, punto decimale} MB)...`.
2. `nome_registro = safe_file_name(nome)` (§8).
3. Voci dello ZIP, cercate per **nome della voce senza cartella** e senza distinzione di maiuscole: la prima
   che termina con `_ZONE.csv`, la prima che termina con `_VALORI.csv` e tutte quelle che terminano con `.kml`.
4. Semestre dai nomi dei CSV: regex `(\d{4})(\d)_(ZONE|VALORI)\.csv$` (senza distinzione di maiuscole) sul nome
   di ZONE e poi, se serve, di VALORI → `anno*10 + s`.
5. **Se c'è almeno un CSV:**
   1. Legge il titolo (riga 1) di ZONE, oppure di VALORI se ZONE manca, e applica la regex del semestre. Se
      trova un semestre diverso da quello del nome stampa
      `  Attenzione: semestre nel nome file ({sem_nome}) diverso da quello nel titolo ({sem_titolo}); uso {sem_titolo}`
      (semestri in forma `AAAAS`) e usa quello del titolo.
   2. Se il semestre manca: errore `Impossibile determinare il semestre dei CSV`.
   3. Riempie due tabelle temporanee (`CREATE TEMP TABLE IF NOT EXISTS {t}(v TEXT PRIMARY KEY); DELETE FROM {t};`,
      poi `INSERT OR IGNORE INTO {t}(v) VALUES (?)`):
      - `tmp_comuni`: valori distinti (senza distinzione di maiuscole) della colonna `Comune_amm` di ZONE;
      - `tmp_links`: valori distinti della colonna `LinkZona` di VALORI.
   4. Cancella i dati da sostituire (una fornitura nazionale sostituisce l'intero semestre, forniture di zone
      diverse si sommano):
      ```sql
      DELETE FROM valore WHERE semestre={sem} AND (link_zona IN (SELECT v FROM tmp_links)
          OR link_zona IN (SELECT link_zona FROM zona WHERE semestre={sem} AND comune_amm IN (SELECT v FROM tmp_comuni)));
      DELETE FROM zona WHERE semestre={sem} AND comune_amm IN (SELECT v FROM tmp_comuni);
      ```
   5. Importa ZONE (§5.1) e VALORI (§5.2); entrambi restituiscono il numero di righe e la data di elaborazione.
   6. Salva le tipologie raccolte (la mappa codice → descrizione si azzera all'inizio di ogni ZIP):
      `INSERT INTO tipologia(cod_tip, descrizione) VALUES (?,?) ON CONFLICT(cod_tip) DO UPDATE SET descrizione=excluded.descrizione`
   7. Aggiorna il semestre (§7) con:
      `elaborazione_zone=coalesce(@ez,elaborazione_zone), elaborazione_valori=coalesce(@ev,elaborazione_valori), file_csv=@f, caricato_csv=@t, n_zone=(SELECT count(*) FROM zona WHERE semestre=@s), n_valori=(SELECT count(*) FROM valore WHERE semestre=@s)`
   8. Stampa `  Semestre {AAAA/S}: {n_zone} zone, {n_valori} valori`.
6. **Se ci sono KML:**
   1. Semestre: quello dei CSV oppure, se non ci sono CSV, il primo trovato nelle `description` delle prime
      5 voci KML (§3). Se manca: errore `Impossibile determinare il semestre dei KML`.
   2. Importa i KML (§6) → `n_geo`.
   3. Aggiorna il semestre (§7) con
      `file_kml=@f, caricato_kml=@t, n_geometrie=(SELECT count(*) FROM zona_geo WHERE semestre=@s)`.
   4. Stampa `  Semestre {AAAA/S}: {n_geo} perimetri di zona da {n_kml} file KML`.
7. Se non c'è né un CSV né un KML: stampa `  Nessun CSV o KML OMI riconosciuto nel file: ignorato.` e termina
   con rollback (non è un errore).
8. Registro del file:
   ```sql
   INSERT INTO file_caricato(file, dimensione, semestre, contenuto, caricato) VALUES (@f,@d,@s,@c,@t)
   ON CONFLICT(file) DO UPDATE SET dimensione=@d, semestre=@s, contenuto=@c, caricato=@t
   ```
   con `contenuto = "zone={n_zone}; valori={n_valori}; kml={n_kml}; perimetri={n_geo}"` e `dimensione` in byte.
9. Commit e stampa `  completato in {secondi, 1 decimale} s`.

## 5. Import dei CSV

### 5.1 ZONE → `zona`
```sql
INSERT OR REPLACE INTO zona(semestre, link_zona, area_territoriale, regione, prov, comune_istat, comune_cat, sez,
    comune_amm, comune_descr, fascia, zona, zona_descr, cod_tip_prev, descr_tip_prev, stato_prev, microzona)
VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
```
Mappatura nell'ordine: semestre, `LinkZona`, `Area_territoriale`, `Regione`, `Prov`, `Comune_ISTAT`,
`Comune_cat`, `Sez`, `Comune_amm`, `Comune_descrizione`, `Fascia`, `Zona`, `Zona_Descr`,
`parse_int(Cod_tip_prev)`, `Descr_tip_prev`, `Stato_prev`, `parse_int(Microzona)`.
Le righe senza `LinkZona`, `Comune_amm` o `Zona` si saltano. Se `Cod_tip_prev` e `Descr_tip_prev` ci sono
entrambi, vanno nella mappa delle tipologie.

### 5.2 VALORI → `valore`
```sql
INSERT OR REPLACE INTO valore(semestre, link_zona, cod_tip, stato, stato_prev, compr_min, compr_max, sup_nl_compr,
    loc_min, loc_max, sup_nl_loc)
VALUES (?,?,?,?,?,?,?,?,?,?,?)
```
Mappatura: semestre, `LinkZona`, `parse_int(Cod_Tip)`, `Stato` (se assente → **stringa vuota**, perché fa
parte della chiave), `Stato_prev`, `parse_decimal(Compr_min)`, `parse_decimal(Compr_max)`, `Sup_NL_compr`,
`parse_decimal(Loc_min)`, `parse_decimal(Loc_max)`, `Sup_NL_loc`. Le righe senza `LinkZona` o senza un
`Cod_Tip` valido si saltano. Se `Descr_Tipologia` è presente va nella mappa delle tipologie (prima
dell'inserimento della riga).

## 6. Import dei KML

### 6.1 Lettura di un KML (macchina a stati)

Si analizza l'XML confrontando il **nome locale** degli elementi (senza prefisso di namespace), con entità e
CDATA decodificati e DTD ignorata. Il "testo" di un elemento è il suo contenuto testuale completo.

| Elemento | Condizione | Azione |
|---|---|---|
| apertura `Style` | sempre | `style_id = attributo id` (può mancare) |
| apertura `PolyStyle` | sempre | `in_poly_style = true` se l'elemento non è vuoto (`<PolyStyle/>`) |
| `color` | `in_poly_style` e `style_id` presente e **fuori** da un placemark | `stili[style_id] = testo ripulito` |
| apertura `Placemark` | sempre | nuovo placemark |
| `name` | dentro un placemark e nome non ancora impostato | `nome = testo ripulito` (vale solo il primo) |
| `description` | dentro un placemark | `descrizione = testo` (non ripulito) |
| `styleUrl` | dentro un placemark | `style_url = testo ripulito` |
| apertura `Data` | dentro un placemark | `data_name = attributo name in maiuscolo` |
| `value` | dentro un placemark e `data_name` impostato | testo ripulito in `LINKZONA`, `CODCOM` o `CODZONA` secondo `data_name` (altri nomi ignorati) |
| apertura `Polygon` | dentro un placemark | nuovo poligono, aggiunto subito alla geometria del placemark |
| `coordinates` | dentro un `Polygon` | `anello = parse_coords(testo)`; si aggiunge al poligono corrente solo se ha **almeno 6 interi** (3 punti) |
| chiusura `Placemark` | — | rimuove i poligoni senza anelli, emette il placemark, azzera placemark e poligono corrente |
| chiusura `Polygon` | — | nessun poligono corrente |
| chiusura `PolyStyle` | — | `in_poly_style = false` |
| chiusura `Style` | — | `style_id` assente |
| chiusura `Data` | — | `data_name` assente |

Gli anelli si aggiungono **nell'ordine del documento**: il primo è il bordo esterno, i successivi sono buchi.

`parse_coords(testo)`: token separati da spazi bianchi, nella forma `lon,lat[,alt]`. Un token senza virgola
o con lon/lat non numerici si scarta. Per i token validi si aggiungono all'anello
`round_half_even(lon * 1e6)` e `round_half_even(lat * 1e6)` come interi a 32 bit.

### 6.2 Rigore del parser

Va considerato **errore di formato**: tag di chiusura non corrispondente, entità sconosciuta, elementi
rimasti aperti a fine documento, contenuto dopo l'elemento radice, caratteri non validi in XML.

### 6.3 Recupero dei KML malformati

Se la lettura completa fallisce:
- se il testo non contiene `<Placemark`, l'errore si propaga e fa fallire l'intero ZIP;
- altrimenti `intestazione` = testo fino al primo `<Placemark`; per ogni sottostringa da `<Placemark` al
  successivo `</Placemark>` (compreso) si analizza `intestazione + sottostringa + "</Document></kml>"`; i
  pezzi che falliscono si contano come scartati. La mappa degli stili si ricostruisce da questi pezzi.
- Stampa `    Attenzione: {nome voce} malformato ({messaggio di errore}); letti {n} placemark, scartati {k}`.

### 6.4 Scrittura nel database

```sql
-- geometria nuova
INSERT INTO geometria(hash, min_lon, min_lat, max_lon, max_lat, centro_lon, centro_lat, area_km2, n_poligoni, n_punti, dati)
VALUES (?,?,?,?,?,?,?,?,?,?,?)
-- indice spaziale (ordine delle colonne dell'R*Tree!)
INSERT INTO geometria_rt(id, min_lon, max_lon, min_lat, max_lat) VALUES (?,?,?,?,?)
-- collegamento
INSERT INTO zona_geo(semestre, comune_amm, zona, link_zona, nome, colore, geometria_id) VALUES (?,?,?,?,?,?,?)
-- sostituzione dei perimetri di un comune nel semestre
DELETE FROM zona_geo WHERE semestre=? AND comune_amm=?
```

Algoritmo:
1. Cache `hash → id`, caricata una volta sola con `SELECT id, hash FROM geometria`. Gli hash inseriti durante
   un file vanno in una cache provvisoria, unita a quella principale **solo dopo il commit**, così un file
   annullato non lascia riferimenti a geometrie inesistenti.
2. Insieme `comuni_sostituiti`, inizialmente vuoto. `sostituisci(c)`: se `c` non è già nell'insieme, lo
   aggiunge ed esegue il `DELETE` di `zona_geo` per `(semestre, c)`.
3. Per ogni voce KML:
   - `codice_file` = nome della voce senza estensione, in maiuscolo; `sostituisci(codice_file)`;
   - per ogni placemark con geometria non vuota:
     - `cod_com` = `CODCOM` se presente, altrimenti `codice_file`, ripulito e in maiuscolo; `sostituisci(cod_com)`;
     - `cod_zona` = `CODZONA` ripulito; se vuoto, si cerca nel nome con la regex `Zona OMI\s+(\S+)\s*$`
       (senza distinzione di maiuscole); se non c'è, il placemark si salta;
     - `blob = encode(geometria)`, `hash = SHA-256(blob)` troncato ai **primi 16 byte**;
     - se l'hash non è in cache: inserisce in `geometria` con bbox in gradi, `centro_lon/lat` arrotondati a 6
       decimali e `area_km2` a 4 decimali (sempre arrotondamento all'intero pari, vedi `03_geometria.md`),
       `n_poligoni`, `n_punti` = somma dei punti di tutti gli anelli; recupera l'id (`last_insert_rowid`) e
       lo inserisce in `geometria_rt`;
     - `colore = stili[style_url senza i '#' iniziali]` se esiste, altrimenti NULL;
     - inserisce in `zona_geo`: semestre, `cod_com`, `cod_zona`, `LINKZONA` ripulito (o NULL se vuoto),
       nome del placemark, colore, id della geometria;
   - ogni 1000 voci elaborate stampa `    {fatte}/{totale} file KML...`.
4. Restituisce il numero di righe inserite in `zona_geo`.

## 7. Aggiornamento della tabella `semestre`

```sql
INSERT INTO semestre(semestre, anno, numero) VALUES ({sem}, {sem/10}, {sem%10}) ON CONFLICT(semestre) DO NOTHING;
UPDATE semestre SET {assegnazioni} WHERE semestre={sem};
```
`@t` = data e ora correnti (`yyyy-MM-dd HH:mm:ss`, ora locale), `@f` = nome ripulito, `@s` = semestre.

## 8. Nome ripulito (`safe_file_name`)

Si rimuove `_` + codice fiscale (16 caratteri: 6 lettere, 2 cifre, 1 lettera, 2 cifre, 1 lettera, 3 cifre,
1 lettera) **immediatamente prima** di `.zip` finale, senza distinzione di maiuscole. Con la crate `regex`,
che non supporta il lookahead: `(?i)_[A-Z]{6}\d{2}[A-Z]\d{2}[A-Z]\d{3}[A-Z](\.zip)$` sostituito con `$1`.
Esempio sintetico: `QIP1438117_RSSMRA80A01H501U.zip` → `QIP1438117.zip`.

## 9. Completamento (`completa`), da eseguire una volta dopo tutti i file

Stampa `Aggiornamento anagrafiche e indici...`, poi in una transazione:

```sql
DELETE FROM geometria_rt WHERE id NOT IN (SELECT geometria_id FROM zona_geo);
DELETE FROM geometria WHERE id NOT IN (SELECT geometria_id FROM zona_geo);

DELETE FROM comune;
INSERT INTO comune(comune_amm, comune_istat, descrizione, prov, regione, area_territoriale, primo_semestre, ultimo_semestre)
SELECT z.comune_amm, z.comune_istat, z.comune_descr, z.prov, z.regione, z.area_territoriale,
       (SELECT min(z2.semestre) FROM zona z2 WHERE z2.comune_amm = z.comune_amm), max(z.semestre)
FROM zona z GROUP BY z.comune_amm;
DELETE FROM comune_nome;
```

Poi, per ogni riga di `SELECT DISTINCT comune_amm, comune_descr, prov FROM zona WHERE comune_descr IS NOT NULL`:
`INSERT OR IGNORE INTO comune_nome(comune_amm, nome, nome_norm, prov) VALUES (?,?,?,?)` con
`nome_norm = norm(comune_descr)` (vedi `03_geometria.md`, §6) e `prov` (stringa vuota se NULL).

Nota: la query `INSERT … SELECT … GROUP BY` si affida al comportamento di SQLite per le colonne non
aggregate con `max()`: le colonne anagrafiche vengono dalla riga con il semestre massimo. Va mantenuta così.

Dopo il commit: `ANALYZE; PRAGMA wal_checkpoint(TRUNCATE);`

## 10. Regole di sostituzione (riassunto per il manuale)

- Una fornitura **nazionale** sostituisce l'intero semestre.
- Forniture di regioni, province o comuni diversi dello stesso semestre **si sommano**.
- Ricaricare lo stesso file non crea duplicati.
- I CSV sostituiscono zone e quotazioni, i KML i perimetri: un `QI` senza perimetri non cancella i perimetri
  già caricati per quel semestre.
- I comuni presenti nel database ma assenti dalla nuova fornitura non vengono cancellati. Per ripartire da
  zero si elimina `omi.db` e si ricaricano gli ZIP.

## 11. Trasformazioni applicate (per il manuale)

Importi convertiti da testo con virgola decimale a numeri; apici attorno alle descrizioni rimossi; perimetri
convertiti da KML a codifica binaria, deduplicati tra semestri, con bbox, centroide e area; decodifica
Latin-1 di ripiego per i KML; placemark malformati scartati e segnalati; codice fiscale rimosso dai nomi dei file registrati.
