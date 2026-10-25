# Fase 06: collaudo

Rileggi `CLAUDE.md` e tutta la `specifica/`. Obiettivo: verificare con prove ripetibili che i due programmi
rispettino la specifica, anche su dati reali se disponibili, e documentare l'esito in `docs/COLLAUDO.md`.

## 1. Revisione di conformità

Ripercorri la specifica **sezione per sezione** e, per ogni requisito, individua il codice che lo
implementa e il test che lo verifica. Produci in `docs/COLLAUDO.md` una matrice
`requisito (file e §) → codice → test → esito`. Ogni requisito senza test va coperto da un nuovo test o
motivato. Controlla con cura in particolare:
- testi di messaggi, descrizioni dei tool e note confrontati con la specifica carattere per carattere (un test
  che legge le stringhe dalla specifica in Markdown e le confronta con quelle del codice è accettabile e utile);
- SQL identico a quello della specifica, a meno dei segnaposto;
- arrotondamenti all'intero pari in tutti i punti indicati;
- ordine delle chiavi JSON di ogni strumento.

## 2. Risultati di riferimento ("golden")

Crea `crates/omi-core/tests/golden/`: per il database sintetico della fase 03, il JSON atteso di una batteria di
chiamate, scritto **a mano a partire dalla specifica** (non generato dal codice da verificare) e riletto con
attenzione. Batteria minima:
- `elenco_semestri {}`, `elenco_tipologie {}`
- `cerca_comuni`: per nome esatto, per prefisso, per parte del nome, per codice catastale, per ISTAT (anche con il
  prefisso regionale), nome ambiguo senza provincia e con provincia, nome con accenti
- `zone_comune`: semplice; con `includi_valori` e `includi_perimetri`; semestre `"2025/3"`; semestre assente
- `dettaglio_zona`: per codice zona; per LinkZona; comune ambiguo; zona inesistente; con `includi_geometria`
- `zona_da_coordinate`: punto interno; punto fuori ma entro 2 km; punto lontano; semestre senza perimetri
- `zone_vicine`: raggio normale; raggio oltre 20 000
- `storico_zona`: tutte le serie; filtrato per tipologia; stato in minuscolo; zona inesistente
- `statistiche_comune`: semestre di default e semestre esplicito

Il test confronta il **testo** del JSON prodotto con il file atteso. Se differiscono, si corregge il codice; si
cambia il file atteso solo se rileggendo la specifica risulta sbagliato il file, e lo si annota in `DECISIONI.md`.

## 3. Prove con dati reali (se in `dati-test/` ci sono ZIP)

I nomi reali non vanno mai stampati nei report: usa alias (`reale-1.zip`, …).
1. Import in release in un database temporaneo; tempi per file; nessun errore inatteso; conteggi coerenti tra
   `semestre`, `zona`, `valore` e `zona_geo`.
2. Controlli d'integrità:
   - `PRAGMA integrity_check` = `ok`;
   - nessun `zona_geo` senza geometria e nessuna geometria senza `zona_geo`;
   - nessuna riga di `geometria_rt` senza `geometria`;
   - per un campione di 200 geometrie, `decode → encode` restituisce lo stesso blob e lo stesso hash;
   - per un campione di 200 zone, il centro della geometria cade dentro il perimetro (tolleranza per i poligoni
     concavi: segnala i casi senza considerarli errori);
   - nessun codice fiscale in tutto il database (`SELECT` sulle colonne di testo con la regex del codice fiscale).
3. Reimport dello stesso file: tutte le tabelle identiche a prima, a parte le date di caricamento.
4. Server sul database reale: una chiamata per strumento su comuni presenti nei dati (Roma `H501`, Milano `F205`
   o quelli disponibili) e verifica a campione dei valori con una query SQL diretta.
5. Se il database contiene un semestre del 2011/1 con `C302.kml`, verifica che venga segnalato e che gli altri
   placemark del file siano caricati.

## 4. Prestazioni

Misura e riporta: tempo d'import per file (release); latenza media e p95 di 200 chiamate a
`zona_da_coordinate` e `zone_comune` (con valori) sul database più grande disponibile; memoria massima del
server durante il test. Valori indicativi da raggiungere: `QIP` nazionale < 15 s; `zona_da_coordinate` p95 < 50 ms.

## 5. Prova di installazione su Windows

Se la sessione è su Windows con privilegi di amministratore, esegui `deploy\windows\test-servizio.ps1` (fase 04)
e la sequenza completa `install.ps1` → verifica → `uninstall.ps1`, controllando che dopo la disinstallazione non
rimangano servizi, regole firewall o cartelle (salvo i dati, se mantenuti). Altrimenti elenca i passi manuali da
far eseguire all'utente.

## 6. Esito

`docs/COLLAUDO.md`: ambiente (sistema operativo, versione di Rust, dati usati con alias), matrice di
conformità, esito di ogni prova, misure, problemi trovati e come sono stati risolti, passi rimasti manuali.

Esegui `fmt`, `clippy` e `test`, fai un commit `fase 06: collaudo` e spunta la fase.
