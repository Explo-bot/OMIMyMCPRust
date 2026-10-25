# Fase 02: importatore `omi-import`

Rileggi `CLAUDE.md` e `specifica/02_forniture_e_importazione.md`. La logica di import va in
`omi-core::import` (riusabile dai test e dal collaudo); nel binario `crates/omi-import` resta solo la riga di comando.

## 1. Riga di comando

```
omi-import [QI*.zip ...] [database.db]
omi-import --help | -h | /?
omi-import --version
```

- Gli argomenti si riconoscono dal tipo e possono stare in qualunque ordine.
- Argomento che termina con `.zip` (senza distinzione di maiuscole): il **nome del file** deve iniziare con
  `QI`, altrimenti `File non riconosciuto (atteso QI*.zip): {arg}`; se il file non esiste,
  `File non trovato: {arg}`. Codice d'uscita 1.
- Argomento con `*` o `?`: espanso dal programma (crate `glob`, senza distinzione di maiuscole), perché il
  Prompt dei comandi e PowerShell non espandono i caratteri jolly. Se l'espansione non trova file:
  `Nessun file corrisponde a: {arg}` e codice 1. Ai file trovati si applicano le stesse verifiche.
- Argomento che termina con `.db`: database (default `omi.db` nella cartella corrente); se non esiste viene creato.
- Qualunque altro argomento: `Parametro non valido: {arg}` seguito dalla riga d'uso; codice 1.
- **Senza argomenti** carica tutti i `QI*.zip` della cartella corrente (quindi anche i `QIP*.zip`), con
  confronto del nome senza distinzione di maiuscole e ordine alfabetico senza distinzione di maiuscole.

## 2. Flusso

1. Stampa `attribuzione()`, `Fonte dei dati: Agenzia Entrate - OMI` e `Database: {percorso assoluto}`.
2. Apre il database in lettura e scrittura ed esegue `ensure_schema`.
3. Se ci sono ZIP: `import_zip` per ciascuno (specifica 02 §4). Un errore stampa su **stderr**
   `  ERRORE su {nome file}: {messaggio}` e si passa al successivo. Dopo l'ultimo file esegue sempre
   `completa()` (specifica 02 §9) e stampa `Caricati {ok}/{totale} file.`
4. Se sono stati passati argomenti ma nessuno ZIP: `Nessun file QI*.zip indicato: nessun caricamento.`
5. Stampa `print_summary`.
6. Codice d'uscita: 0 se tutti i file sono stati caricati (o non ce n'erano), 2 se almeno uno è fallito.

I numeri decimali a video usano il punto. I messaggi a console possono mostrare il nome originale del file
(è la console dell'utente), ma il database registra solo il nome ripulito.

## 3. Implementazione

- Segui la specifica 02 punto per punto: estrazione del semestre, tabelle temporanee, `DELETE`, upsert,
  lettura dei CSV, macchina a stati dei KML, recupero dei KML malformati, deduplicazione delle geometrie,
  cache degli hash unita solo dopo il commit, `completa()`.
- Parser XML: `quick-xml` su `&str` decodificato come da specifica 02 §3, confronto sul nome locale, con i
  controlli di rigore della specifica 02 §6.2 (attiva il controllo dei tag di chiusura e verifica a mano gli
  elementi aperti a fine documento).
- Prestazioni: statement preparati una volta sola (`prepare_cached`) e un'unica transazione per file. Ogni CSV
  può essere letto in memoria una volta sola. Obiettivo: un `QIP` nazionale (≈100 MB) in meno di 15 s in release.

## 4. Fixture sintetiche

In `crates/omi-core/tests/support/` crea un **generatore di ZIP sintetici** (crate `zip` in scrittura) che
produca CSV e KML nel formato della specifica 02 §2–§3, con titoli compatibili con le regex. Non vanno mai
committati ZIP reali. Se in `dati-test/` c'è uno ZIP reale, aprilo per allineare il generatore alla struttura
vera (righe di titolo, intestazioni, struttura dei KML) **senza stamparne il nome** e annota in `DECISIONI.md`
le differenze trovate rispetto alla specifica.

## 5. Test

1. `QIP` sintetico con 2 comuni, 3 zone, valori con 2 stati, KML con multipoligono, buco, colore di stile ed
   `ExtendedData` completo → conteggi in `semestre`, geometria letta dal DB uguale all'input, `contains` vero
   per un punto interno usando il blob del DB.
2. Reimport dello stesso file → nessun duplicato, conteggi invariati.
3. Due forniture provinciali dello stesso semestre → si sommano; fornitura nazionale successiva → sostituisce.
4. `QI` senza KML su un semestre che ha già perimetri → i perimetri restano.
5. KML in Latin-1 con dichiarazione UTF-8 → nomi accentati corretti.
6. KML con un placemark malformato → gli altri vengono caricati e il messaggio d'avviso è quello previsto.
7. KML senza nessun `<Placemark` e malformato → lo ZIP fallisce, quelli successivi vengono caricati.
8. ZIP corrotto tra due validi → due caricati, codice d'uscita 2.
9. Nome con codice fiscale → in `file_caricato` c'è il nome ripulito e il codice fiscale non compare in alcuna tabella.
10. Geometria identica in due semestri → una sola riga in `geometria` e due in `zona_geo`.
11. ZIP che fallisce dopo aver inserito una geometria nuova, seguito da uno valido con la stessa geometria → nessun
    `zona_geo` orfano (`SELECT count(*) FROM zona_geo WHERE geometria_id NOT IN (SELECT id FROM geometria)` = 0).
12. Titolo con semestre diverso dal nome del file → avviso e semestre del titolo.
13. ZIP senza CSV né KML → messaggio "ignorato", nessuna riga in `file_caricato`.
14. `completa()`: `comune` con primo e ultimo semestre corretti, `comune_nome` con nomi storici distinti normalizzati.

Test del binario (`assert_cmd` + `tempfile`): parametri non validi, `--help`, `--version`, cartella senza ZIP,
caratteri jolly, codici d'uscita.

Se in `dati-test/` c'è un `QIP` reale, misura il tempo d'import in release e scrivilo nelle note della fase.

Esegui `fmt`, `clippy` e `test`, fai un commit `fase 02: omi-import` e spunta la fase.
