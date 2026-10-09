# Arcade-Balancing – Bericht der Simulation

- Seed: 1
- Läufe je Kadenzverlauf und Stufe: 1000 ohne Ausrüstung, 300 mit Empfohlener Stärke; Laufbahnen je Kadenzverlauf: 100 (höchstens 120 Läufe)
- Fahrt: 45 min auf dem Insel-Rundkurs (9210 m), Standardbereich 60–120 rpm
- Befehl: `godot --headless --path games/island-ride -s res://tools/balancing_sim.gd -- --runs=1000 --gear-runs=300 --careers=100 --seed=1 --commit=1a104b5 --date=2026-10-09 --note=Laufzeit rund 6 Minuten (ein Kern); Datenstand nach der Nachjustierung --appendix=../../docs/balancing/arcade-balancing-notes.md`
- Stand (Commit): 1a104b5
- Datum: 2026-10-09
- Hinweis: Laufzeit rund 6 Minuten (ein Kern); Datenstand nach der Nachjustierung

Erzeugt von `src/balancing.gd`; Lesart und Grenzen der Simulation stehen im Kopf der Datei. Alle Zahlen sind **ohne Fähigkeiten** gerechnet (Untergrenze), Ausrüstung nur dort, wo sie genannt ist.

## Kadenzverläufe

| Verlauf | Beschreibung |
|---|---|
| Einsteiger | tritt 74 rpm, schwankt stark (±7), ist zu 70 % der Zeit bei der Sache und folgt der Zielzone träge (3,5 s), schafft höchstens 118 rpm, ermüdet schnell (−10 rpm/h) |
| Trainierter | tritt 88 rpm gleichmäßig (±4), ist zu 90 % der Zeit bei der Sache und folgt der Zielzone in 1,5 s, schafft 124 rpm, ermüdet kaum (−4 rpm/h) |
| Sprinter | tritt 92 rpm unruhig (±6), ist zu 75 % der Zeit bei der Sache und folgt der Zielzone flink (0,9 s), setzt bei Schwellen hoch an (Punkt 0,75), schafft 140 rpm, Spitzen von +22 rpm für 6 s alle ~90 s, ermüdet mäßig (−8 rpm/h) |

## Einsteiger

### Häufigkeit je Seltenheit (ohne Ausrüstung)

Funde je Stufe: absolut (Anteil an allen Funden).

| Stufe | Fahrten | Funde/h | Gewöhnlich | Magisch | Selten | Legendär |
|---|---|---|---|---|---|---|
| Stufe 1 | 1000 | 9.5 | 3379 (47 %) | 2229 (31 %) | 1169 (16 %) | 349 (5 %) |
| Stufe 2 | 1000 | 8.1 | 2505 (41 %) | 1866 (31 %) | 1251 (21 %) | 456 (8 %) |
| Stufe 3 | 1000 | 6.6 | 1751 (35 %) | 1566 (31 %) | 1132 (23 %) | 531 (11 %) |
| Stufe 4 | 1000 | 6.0 | 1379 (30 %) | 1397 (31 %) | 1126 (25 %) | 621 (14 %) |
| Stufe 5 | 1000 | 5.5 | 1024 (24 %) | 1177 (28 %) | 1241 (30 %) | 738 (18 %) |
| Stufe 6 | 1000 | 4.6 | 669 (19 %) | 944 (27 %) | 1100 (31 %) | 795 (23 %) |

### Erfolgsquote je Herausforderung und Stufe (ohne Ausrüstung)

Erfolgsquote (Zahl der beendeten Herausforderungen).

| Herausforderung | Stufe 1 | Stufe 2 | Stufe 3 | Stufe 4 | Stufe 5 | Stufe 6 |
|---|---|---|---|---|---|---|
| zone_mitte (Zone halten) | 79 % (583) | 71 % (607) | 55 % (608) | 48 % (618) | 40 % (605) | 27 % (601) |
| zone_ruhig (Zone halten) | 90 % (578) | 83 % (610) | 61 % (624) | 53 % (595) | 43 % (623) | 17 % (562) |
| zone_zuegig (Zone halten) | 69 % (581) | 63 % (573) | 56 % (632) | 52 % (609) | 38 % (534) | 28 % (618) |
| durchbruch_bruecke (Durchbruch) | 57 % (572) | 38 % (582) | 23 % (598) | 18 % (667) | 18 % (625) | 7 % (585) |
| durchbruch_spurt (Durchbruch) | 44 % (587) | 22 % (624) | 6 % (591) | 3 % (605) | 4 % (609) | 0 % (635) |
| jagd_verfolger (Jagd) | 66 % (579) | 56 % (598) | 54 % (623) | 52 % (612) | 51 % (628) | 49 % (631) |
| jagd_wild (Jagd) | 57 % (589) | 48 % (566) | 42 % (604) | 38 % (620) | 35 % (619) | 33 % (574) |
| takt_ruhig (Takt-Tore) | 86 % (643) | 79 % (601) | 75 % (632) | 63 % (599) | 68 % (608) | 60 % (611) |
| takt_flott (Takt-Tore) | 57 % (589) | 55 % (601) | 43 % (589) | 43 % (590) | 38 % (656) | 36 % (580) |
| sammeln_wiese (Sammeln) | 13 % (603) | 16 % (629) | 6 % (610) | 6 % (629) | 5 % (598) | 7 % (594) |
| sammeln_ufer (Sammeln) | 3 % (553) | 4 % (579) | 2 % (594) | 1 % (598) | 0 % (607) | 0 % (655) |
| Elite: Champions | 46 % (733) | 32 % (821) | 21 % (818) | 18 % (761) | 13 % (789) | 10 % (776) |
| Elite: Seltene | 37 % (406) | 22 % (394) | 10 % (432) | 9 % (433) | 5 % (435) | 5 % (436) |
| Boss: Tramuntana | 45 % (2000) | 32 % (2000) | 18 % (2000) | 13 % (2000) | 8 % (2000) | 3 % (2000) |
| Boss: Drac de na Coca | 14 % (2000) | 5 % (2000) | 2 % (2000) | 0 % (2000) | 0 % (2000) | 0 % (2000) |
| Boss: Dimonis | 45 % (1435) | 34 % (1585) | 17 % (1717) | 15 % (1768) | 12 % (1834) | 9 % (1803) |
| **alle zusammen** | 46 % (13031) | 36 % (13370) | 26 % (13672) | 22 % (13704) | 19 % (13770) | 14 % (13661) |
| Elite-Anteil an den Herausforderungen ohne Boss | 15 % | 16 % | 16 % | 15 % | 15 % | 15 % |

### Erfolgsquote der Boss-Phasen (ohne Ausrüstung)

Anteil der erreichten Phasen, die geschafft wurden.

| Phase | Stufe 1 | Stufe 2 | Stufe 3 | Stufe 4 | Stufe 5 | Stufe 6 |
|---|---|---|---|---|---|---|
| Tramuntana · Phase 1 Gegenwind | 80 % | 71 % | 59 % | 53 % | 43 % | 28 % |
| Tramuntana · Phase 2 Böe | 65 % | 60 % | 52 % | 50 % | 46 % | 45 % |
| Tramuntana · Phase 3 Sturmfront | 86 % | 76 % | 59 % | 48 % | 40 % | 26 % |
| Drac de na Coca · Phase 1 Feueratem | 82 % | 74 % | 63 % | 58 % | 48 % | 31 % |
| Drac de na Coca · Phase 2 Flügelschlag | 53 % | 30 % | 22 % | 18 % | 22 % | 19 % |
| Drac de na Coca · Phase 3 Schuppenpanzer | 83 % | 74 % | 63 % | 51 % | 49 % | 33 % |
| Drac de na Coca · Phase 4 Letzter Ansturm | 38 % | 31 % | 18 % | 0 % | 0 % | 0 % |
| Dimonis · Phase 1 Durch die Gassen | 67 % | 61 % | 56 % | 53 % | 50 % | 45 % |
| Dimonis · Phase 2 Über den Dorfplatz | 77 % | 67 % | 39 % | 37 % | 36 % | 32 % |
| Dimonis · Phase 3 Hinaus aus dem Dorf | 88 % | 83 % | 77 % | 73 % | 70 % | 59 % |

### Dauer je Boss (ohne Ausrüstung)

Sekunden vom Beginn des Kampfes bis zum Sieg bzw. Entkommen; Quantile nach dem Nächster-Rang-Verfahren.

| Boss | Stufe | Kämpfe | Sieg | Sieg: Median s | Sieg: 90 % s | Entkommen: Median s |
|---|---|---|---|---|---|---|
| Tramuntana | Stufe 1 | 2000 | 45 % | 37 | 44 | 26 |
| Tramuntana | Stufe 2 | 2000 | 32 % | 51 | 59 | 33 |
| Tramuntana | Stufe 3 | 2000 | 18 % | 70 | 78 | 32 |
| Tramuntana | Stufe 4 | 2000 | 13 % | 85 | 93 | 37 |
| Tramuntana | Stufe 5 | 2000 | 8 % | 100 | 112 | 43 |
| Tramuntana | Stufe 6 | 2000 | 3 % | 116 | 128 | 49 |
| Drac de na Coca | Stufe 1 | 2000 | 14 % | 56 | 63 | 32 |
| Drac de na Coca | Stufe 2 | 2000 | 5 % | 75 | 82 | 41 |
| Drac de na Coca | Stufe 3 | 2000 | 2 % | 97 | 107 | 52 |
| Drac de na Coca | Stufe 4 | 2000 | 0 % | – | – | 62 |
| Drac de na Coca | Stufe 5 | 2000 | 0 % | – | – | 51 |
| Drac de na Coca | Stufe 6 | 2000 | 0 % | – | – | 59 |
| Dimonis | Stufe 1 | 1435 | 45 % | 22 | 28 | 11 |
| Dimonis | Stufe 2 | 1585 | 34 % | 29 | 36 | 15 |
| Dimonis | Stufe 3 | 1717 | 17 % | 34 | 43 | 22 |
| Dimonis | Stufe 4 | 1768 | 15 % | 42 | 54 | 21 |
| Dimonis | Stufe 5 | 1834 | 12 % | 48 | 59 | 21 |
| Dimonis | Stufe 6 | 1803 | 9 % | 58 | 73 | 20 |

### Mit Empfohlener Stärke (300 Fahrten je Stufe)

Erfolgsquote ohne → mit Ausrüstung der Empfohlenen Stärke.

| Stufe | Empfohlene Stärke | Normal ohne | Normal mit | Elite ohne | Elite mit | Boss ohne | Boss mit |
|---|---|---|---|---|---|---|---|
| Stufe 1 | 0 (Zone +0 rpm, Fortschritt +0 %) | 57 % | 57 % | 43 % | 38 % | 33 % | 34 % |
| Stufe 2 | 10 (Zone +1 rpm, Fortschritt +6 %) | 48 % | 52 % | 29 % | 33 % | 23 % | 25 % |
| Stufe 3 | 20 (Zone +2 rpm, Fortschritt +12 %) | 39 % | 46 % | 17 % | 25 % | 12 % | 20 % |
| Stufe 4 | 35 (Zone +4 rpm, Fortschritt +19 %) | 34 % | 52 % | 15 % | 31 % | 9 % | 25 % |
| Stufe 5 | 50 (Zone +6 rpm, Fortschritt +26 %) | 31 % | 57 % | 10 % | 40 % | 7 % | 30 % |
| Stufe 6 | 70 (Zone +8 rpm, Fortschritt +38 %) | 24 % | 61 % | 8 % | 45 % | 4 % | 34 % |

## Trainierter

### Häufigkeit je Seltenheit (ohne Ausrüstung)

Funde je Stufe: absolut (Anteil an allen Funden).

| Stufe | Fahrten | Funde/h | Gewöhnlich | Magisch | Selten | Legendär |
|---|---|---|---|---|---|---|
| Stufe 1 | 1000 | 21.1 | 7353 (46 %) | 4842 (31 %) | 2679 (17 %) | 978 (6 %) |
| Stufe 2 | 1000 | 21.0 | 6126 (39 %) | 4843 (31 %) | 3367 (21 %) | 1453 (9 %) |
| Stufe 3 | 1000 | 20.3 | 5051 (33 %) | 4575 (30 %) | 3711 (24 %) | 1920 (13 %) |
| Stufe 4 | 1000 | 19.9 | 3928 (26 %) | 4423 (30 %) | 4100 (27 %) | 2532 (17 %) |
| Stufe 5 | 1000 | 19.6 | 3126 (21 %) | 3983 (27 %) | 4456 (30 %) | 3203 (22 %) |
| Stufe 6 | 1000 | 19.3 | 2203 (15 %) | 3461 (24 %) | 4711 (32 %) | 4160 (29 %) |

### Erfolgsquote je Herausforderung und Stufe (ohne Ausrüstung)

Erfolgsquote (Zahl der beendeten Herausforderungen).

| Herausforderung | Stufe 1 | Stufe 2 | Stufe 3 | Stufe 4 | Stufe 5 | Stufe 6 |
|---|---|---|---|---|---|---|
| zone_mitte (Zone halten) | 100 % (810) | 99 % (799) | 99 % (799) | 99 % (783) | 99 % (827) | 99 % (810) |
| zone_ruhig (Zone halten) | 100 % (772) | 99 % (825) | 98 % (801) | 98 % (809) | 97 % (778) | 95 % (799) |
| zone_zuegig (Zone halten) | 97 % (826) | 96 % (767) | 97 % (774) | 95 % (763) | 96 % (782) | 95 % (757) |
| durchbruch_bruecke (Durchbruch) | 94 % (808) | 93 % (809) | 91 % (803) | 92 % (765) | 93 % (784) | 92 % (779) |
| durchbruch_spurt (Durchbruch) | 94 % (828) | 93 % (829) | 89 % (802) | 89 % (797) | 86 % (788) | 84 % (754) |
| jagd_verfolger (Jagd) | 91 % (777) | 90 % (834) | 90 % (835) | 88 % (781) | 89 % (746) | 88 % (760) |
| jagd_wild (Jagd) | 88 % (821) | 88 % (805) | 86 % (840) | 86 % (802) | 83 % (776) | 85 % (820) |
| takt_ruhig (Takt-Tore) | 100 % (818) | 100 % (795) | 98 % (762) | 99 % (731) | 98 % (800) | 97 % (740) |
| takt_flott (Takt-Tore) | 94 % (810) | 88 % (834) | 83 % (805) | 85 % (817) | 82 % (777) | 84 % (774) |
| sammeln_wiese (Sammeln) | 92 % (814) | 89 % (814) | 85 % (787) | 84 % (813) | 84 % (773) | 84 % (762) |
| sammeln_ufer (Sammeln) | 70 % (801) | 68 % (820) | 58 % (792) | 44 % (830) | 39 % (805) | 33 % (739) |
| Elite: Champions | 86 % (1032) | 81 % (1029) | 75 % (967) | 72 % (1003) | 71 % (890) | 64 % (932) |
| Elite: Seltene | 80 % (531) | 71 % (525) | 66 % (531) | 58 % (516) | 54 % (554) | 44 % (527) |
| Boss: Tramuntana | 90 % (2839) | 90 % (2946) | 88 % (2984) | 88 % (2992) | 86 % (2997) | 88 % (3000) |
| Boss: Drac de na Coca | 84 % (2000) | 82 % (2000) | 78 % (2000) | 77 % (2000) | 73 % (2000) | 71 % (2000) |
| Boss: Dimonis | 86 % (2000) | 84 % (2000) | 81 % (2000) | 80 % (2000) | 79 % (2000) | 76 % (2000) |
| **alle zusammen** | 90 % (17287) | 88 % (17431) | 85 % (17282) | 83 % (17202) | 82 % (17077) | 80 % (16953) |
| Elite-Anteil an den Herausforderungen ohne Boss | 15 % | 15 % | 15 % | 15 % | 14 % | 15 % |

### Erfolgsquote der Boss-Phasen (ohne Ausrüstung)

Anteil der erreichten Phasen, die geschafft wurden.

| Phase | Stufe 1 | Stufe 2 | Stufe 3 | Stufe 4 | Stufe 5 | Stufe 6 |
|---|---|---|---|---|---|---|
| Tramuntana · Phase 1 Gegenwind | 100 % | 99 % | 98 % | 98 % | 98 % | 98 % |
| Tramuntana · Phase 2 Böe | 92 % | 93 % | 93 % | 93 % | 92 % | 94 % |
| Tramuntana · Phase 3 Sturmfront | 99 % | 98 % | 96 % | 96 % | 95 % | 95 % |
| Drac de na Coca · Phase 1 Feueratem | 100 % | 100 % | 100 % | 100 % | 99 % | 100 % |
| Drac de na Coca · Phase 2 Flügelschlag | 91 % | 92 % | 92 % | 91 % | 91 % | 91 % |
| Drac de na Coca · Phase 3 Schuppenpanzer | 99 % | 97 % | 96 % | 96 % | 96 % | 96 % |
| Drac de na Coca · Phase 4 Letzter Ansturm | 94 % | 92 % | 87 % | 88 % | 84 % | 82 % |
| Dimonis · Phase 1 Durch die Gassen | 93 % | 91 % | 89 % | 88 % | 89 % | 86 % |
| Dimonis · Phase 2 Über den Dorfplatz | 97 % | 96 % | 96 % | 96 % | 95 % | 96 % |
| Dimonis · Phase 3 Hinaus aus dem Dorf | 96 % | 96 % | 95 % | 94 % | 93 % | 91 % |

### Dauer je Boss (ohne Ausrüstung)

Sekunden vom Beginn des Kampfes bis zum Sieg bzw. Entkommen; Quantile nach dem Nächster-Rang-Verfahren.

| Boss | Stufe | Kämpfe | Sieg | Sieg: Median s | Sieg: 90 % s | Entkommen: Median s |
|---|---|---|---|---|---|---|
| Tramuntana | Stufe 1 | 2839 | 90 % | 31 | 33 | 27 |
| Tramuntana | Stufe 2 | 2946 | 90 % | 40 | 44 | 33 |
| Tramuntana | Stufe 3 | 2984 | 88 % | 50 | 58 | 41 |
| Tramuntana | Stufe 4 | 2992 | 88 % | 59 | 69 | 50 |
| Tramuntana | Stufe 5 | 2997 | 86 % | 71 | 83 | 59 |
| Tramuntana | Stufe 6 | 3000 | 88 % | 84 | 97 | 69 |
| Drac de na Coca | Stufe 1 | 2000 | 84 % | 42 | 46 | 32 |
| Drac de na Coca | Stufe 2 | 2000 | 82 % | 55 | 61 | 56 |
| Drac de na Coca | Stufe 3 | 2000 | 78 % | 70 | 79 | 75 |
| Drac de na Coca | Stufe 4 | 2000 | 77 % | 83 | 94 | 85 |
| Drac de na Coca | Stufe 5 | 2000 | 73 % | 99 | 113 | 103 |
| Drac de na Coca | Stufe 6 | 2000 | 71 % | 119 | 135 | 123 |
| Dimonis | Stufe 1 | 2000 | 86 % | 18 | 18 | 16 |
| Dimonis | Stufe 2 | 2000 | 84 % | 22 | 24 | 16 |
| Dimonis | Stufe 3 | 2000 | 81 % | 26 | 31 | 16 |
| Dimonis | Stufe 4 | 2000 | 80 % | 31 | 39 | 15 |
| Dimonis | Stufe 5 | 2000 | 79 % | 36 | 45 | 19 |
| Dimonis | Stufe 6 | 2000 | 76 % | 41 | 53 | 22 |

### Mit Empfohlener Stärke (300 Fahrten je Stufe)

Erfolgsquote ohne → mit Ausrüstung der Empfohlenen Stärke.

| Stufe | Empfohlene Stärke | Normal ohne | Normal mit | Elite ohne | Elite mit | Boss ohne | Boss mit |
|---|---|---|---|---|---|---|---|
| Stufe 1 | 0 (Zone +0 rpm, Fortschritt +0 %) | 93 % | 93 % | 84 % | 83 % | 87 % | 88 % |
| Stufe 2 | 10 (Zone +1 rpm, Fortschritt +6 %) | 91 % | 93 % | 78 % | 87 % | 86 % | 86 % |
| Stufe 3 | 20 (Zone +2 rpm, Fortschritt +12 %) | 88 % | 92 % | 72 % | 78 % | 83 % | 87 % |
| Stufe 4 | 35 (Zone +4 rpm, Fortschritt +19 %) | 87 % | 93 % | 67 % | 86 % | 82 % | 89 % |
| Stufe 5 | 50 (Zone +6 rpm, Fortschritt +26 %) | 86 % | 95 % | 65 % | 88 % | 80 % | 90 % |
| Stufe 6 | 70 (Zone +8 rpm, Fortschritt +38 %) | 85 % | 95 % | 57 % | 91 % | 79 % | 92 % |

## Sprinter

### Häufigkeit je Seltenheit (ohne Ausrüstung)

Funde je Stufe: absolut (Anteil an allen Funden).

| Stufe | Fahrten | Funde/h | Gewöhnlich | Magisch | Selten | Legendär |
|---|---|---|---|---|---|---|
| Stufe 1 | 1000 | 20.0 | 7009 (47 %) | 4574 (31 %) | 2500 (17 %) | 901 (6 %) |
| Stufe 2 | 1000 | 19.1 | 5685 (40 %) | 4310 (30 %) | 2940 (21 %) | 1400 (10 %) |
| Stufe 3 | 1000 | 18.1 | 4414 (33 %) | 4204 (31 %) | 3268 (24 %) | 1657 (12 %) |
| Stufe 4 | 1000 | 17.3 | 3562 (27 %) | 3833 (29 %) | 3461 (27 %) | 2140 (16 %) |
| Stufe 5 | 1000 | 16.6 | 2846 (23 %) | 3331 (27 %) | 3745 (30 %) | 2534 (20 %) |
| Stufe 6 | 1000 | 15.6 | 1959 (17 %) | 2879 (25 %) | 3739 (32 %) | 3135 (27 %) |

### Erfolgsquote je Herausforderung und Stufe (ohne Ausrüstung)

Erfolgsquote (Zahl der beendeten Herausforderungen).

| Herausforderung | Stufe 1 | Stufe 2 | Stufe 3 | Stufe 4 | Stufe 5 | Stufe 6 |
|---|---|---|---|---|---|---|
| zone_mitte (Zone halten) | 100 % (851) | 98 % (809) | 94 % (816) | 94 % (757) | 89 % (760) | 86 % (738) |
| zone_ruhig (Zone halten) | 93 % (802) | 90 % (781) | 81 % (776) | 75 % (806) | 70 % (793) | 58 % (779) |
| zone_zuegig (Zone halten) | 97 % (784) | 93 % (803) | 88 % (846) | 85 % (777) | 82 % (759) | 76 % (787) |
| durchbruch_bruecke (Durchbruch) | 85 % (811) | 82 % (826) | 86 % (801) | 81 % (764) | 79 % (794) | 78 % (819) |
| durchbruch_spurt (Durchbruch) | 84 % (753) | 81 % (763) | 77 % (838) | 76 % (766) | 72 % (706) | 71 % (762) |
| jagd_verfolger (Jagd) | 84 % (813) | 81 % (801) | 77 % (734) | 73 % (735) | 73 % (786) | 71 % (741) |
| jagd_wild (Jagd) | 75 % (824) | 69 % (803) | 68 % (733) | 66 % (786) | 69 % (801) | 63 % (775) |
| takt_ruhig (Takt-Tore) | 96 % (816) | 93 % (814) | 91 % (800) | 86 % (763) | 86 % (695) | 83 % (746) |
| takt_flott (Takt-Tore) | 90 % (815) | 79 % (798) | 72 % (796) | 76 % (765) | 65 % (791) | 71 % (763) |
| sammeln_wiese (Sammeln) | 94 % (780) | 89 % (796) | 89 % (743) | 90 % (808) | 90 % (774) | 90 % (725) |
| sammeln_ufer (Sammeln) | 79 % (838) | 77 % (826) | 71 % (791) | 70 % (812) | 73 % (783) | 72 % (702) |
| Elite: Champions | 83 % (1067) | 77 % (1031) | 69 % (1027) | 65 % (1011) | 57 % (985) | 52 % (975) |
| Elite: Seltene | 74 % (529) | 67 % (592) | 50 % (582) | 45 % (505) | 36 % (543) | 33 % (554) |
| Boss: Tramuntana | 81 % (3000) | 78 % (3000) | 70 % (3000) | 68 % (3000) | 62 % (3000) | 55 % (3000) |
| Boss: Drac de na Coca | 68 % (2000) | 63 % (2000) | 54 % (2000) | 51 % (2000) | 47 % (2000) | 33 % (2000) |
| Boss: Dimonis | 74 % (2000) | 69 % (2000) | 63 % (2000) | 58 % (2000) | 55 % (2000) | 51 % (2000) |
| **alle zusammen** | 82 % (17483) | 78 % (17443) | 72 % (17283) | 70 % (17055) | 66 % (16970) | 61 % (16866) |
| Elite-Anteil an den Herausforderungen ohne Boss | 15 % | 16 % | 16 % | 15 % | 15 % | 15 % |

### Erfolgsquote der Boss-Phasen (ohne Ausrüstung)

Anteil der erreichten Phasen, die geschafft wurden.

| Phase | Stufe 1 | Stufe 2 | Stufe 3 | Stufe 4 | Stufe 5 | Stufe 6 |
|---|---|---|---|---|---|---|
| Tramuntana · Phase 1 Gegenwind | 99 % | 96 % | 92 % | 90 % | 87 % | 82 % |
| Tramuntana · Phase 2 Böe | 84 % | 85 % | 85 % | 86 % | 86 % | 86 % |
| Tramuntana · Phase 3 Sturmfront | 98 % | 95 % | 91 % | 88 % | 83 % | 78 % |
| Drac de na Coca · Phase 1 Feueratem | 98 % | 96 % | 93 % | 91 % | 90 % | 83 % |
| Drac de na Coca · Phase 2 Flügelschlag | 83 % | 82 % | 83 % | 83 % | 82 % | 80 % |
| Drac de na Coca · Phase 3 Schuppenpanzer | 99 % | 96 % | 92 % | 91 % | 87 % | 80 % |
| Drac de na Coca · Phase 4 Letzter Ansturm | 84 % | 83 % | 77 % | 74 % | 73 % | 61 % |
| Dimonis · Phase 1 Durch die Gassen | 88 % | 83 % | 78 % | 75 % | 73 % | 71 % |
| Dimonis · Phase 2 Über den Dorfplatz | 91 % | 92 % | 91 % | 90 % | 90 % | 88 % |
| Dimonis · Phase 3 Hinaus aus dem Dorf | 93 % | 90 % | 88 % | 85 % | 84 % | 82 % |

### Dauer je Boss (ohne Ausrüstung)

Sekunden vom Beginn des Kampfes bis zum Sieg bzw. Entkommen; Quantile nach dem Nächster-Rang-Verfahren.

| Boss | Stufe | Kämpfe | Sieg | Sieg: Median s | Sieg: 90 % s | Entkommen: Median s |
|---|---|---|---|---|---|---|
| Tramuntana | Stufe 1 | 3000 | 81 % | 31 | 37 | 27 |
| Tramuntana | Stufe 2 | 3000 | 78 % | 40 | 49 | 34 |
| Tramuntana | Stufe 3 | 3000 | 70 % | 55 | 65 | 44 |
| Tramuntana | Stufe 4 | 3000 | 68 % | 68 | 80 | 53 |
| Tramuntana | Stufe 5 | 3000 | 62 % | 83 | 98 | 64 |
| Tramuntana | Stufe 6 | 3000 | 55 % | 100 | 114 | 73 |
| Drac de na Coca | Stufe 1 | 2000 | 68 % | 40 | 48 | 35 |
| Drac de na Coca | Stufe 2 | 2000 | 63 % | 54 | 65 | 44 |
| Drac de na Coca | Stufe 3 | 2000 | 54 % | 73 | 85 | 63 |
| Drac de na Coca | Stufe 4 | 2000 | 51 % | 89 | 104 | 81 |
| Drac de na Coca | Stufe 5 | 2000 | 47 % | 110 | 126 | 93 |
| Drac de na Coca | Stufe 6 | 2000 | 33 % | 136 | 154 | 110 |
| Dimonis | Stufe 1 | 2000 | 74 % | 18 | 24 | 20 |
| Dimonis | Stufe 2 | 2000 | 69 % | 22 | 30 | 17 |
| Dimonis | Stufe 3 | 2000 | 63 % | 26 | 38 | 16 |
| Dimonis | Stufe 4 | 2000 | 58 % | 31 | 44 | 20 |
| Dimonis | Stufe 5 | 2000 | 55 % | 36 | 51 | 18 |
| Dimonis | Stufe 6 | 2000 | 51 % | 41 | 61 | 21 |

### Mit Empfohlener Stärke (300 Fahrten je Stufe)

Erfolgsquote ohne → mit Ausrüstung der Empfohlenen Stärke.

| Stufe | Empfohlene Stärke | Normal ohne | Normal mit | Elite ohne | Elite mit | Boss ohne | Boss mit |
|---|---|---|---|---|---|---|---|
| Stufe 1 | 0 (Zone +0 rpm, Fortschritt +0 %) | 89 % | 89 % | 80 % | 80 % | 75 % | 74 % |
| Stufe 2 | 10 (Zone +1 rpm, Fortschritt +6 %) | 85 % | 87 % | 73 % | 72 % | 71 % | 73 % |
| Stufe 3 | 20 (Zone +2 rpm, Fortschritt +12 %) | 82 % | 86 % | 62 % | 76 % | 64 % | 72 % |
| Stufe 4 | 35 (Zone +4 rpm, Fortschritt +19 %) | 79 % | 89 % | 58 % | 75 % | 60 % | 75 % |
| Stufe 5 | 50 (Zone +6 rpm, Fortschritt +26 %) | 77 % | 90 % | 50 % | 79 % | 56 % | 78 % |
| Stufe 6 | 70 (Zone +8 rpm, Fortschritt +38 %) | 74 % | 92 % | 45 % | 86 % | 47 % | 82 % |

## Zielzonen und Schwellen je Stufe

Standardbereich 60–120 rpm, erste Runde, ohne Ausrüstung (rpm).

| Herausforderung | Stufe 1 | Stufe 2 | Stufe 3 | Stufe 4 | Stufe 5 | Stufe 6 |
|---|---|---|---|---|---|---|
| zone_mitte | 80–100 | 83–97 | 85–95 | 86–95 | 86–94 | 87–94 |
| zone_ruhig | 71–91 | 74–88 | 76–86 | 77–86 | 77–85 | 78–85 |
| zone_zuegig | 87–107 | 90–104 | 92–102 | 93–102 | 93–101 | 94–101 |
| durchbruch_bruecke | ab 108 | ab 111 | ab 113 | ab 114 | ab 114 | ab 115 |
| durchbruch_spurt | ab 111 | ab 114 | ab 116 | ab 117 | ab 117 | ab 118 |
| jagd_verfolger | ab 93 | ab 96 | ab 98 | ab 99 | ab 99 | ab 100 |
| jagd_wild | ab 99 | ab 102 | ab 104 | ab 105 | ab 105 | ab 106 |
| takt_ruhig | 74–94 | 77–91 | 79–89 | 80–89 | 80–88 | 81–88 |
| takt_flott | 89–109 | 92–106 | 94–104 | 95–104 | 95–103 | 96–103 |
| sammeln_wiese | ab 75 | ab 78 | ab 80 | ab 81 | ab 81 | ab 82 |
| sammeln_ufer | ab 84 | ab 87 | ab 89 | ab 90 | ab 90 | ab 91 |
| Tramuntana · Gegenwind | 80–100 | 83–97 | 85–95 | 86–95 | 86–94 | 87–94 |
| Tramuntana · Böe | ab 105 | ab 108 | ab 110 | ab 111 | ab 111 | ab 112 |
| Tramuntana · Sturmfront | 86–106 | 89–103 | 91–101 | 92–101 | 92–100 | 93–100 |
| Drac de na Coca · Feueratem | 77–97 | 80–94 | 82–92 | 83–92 | 83–91 | 84–91 |
| Drac de na Coca · Flügelschlag | ab 108 | ab 111 | ab 113 | ab 114 | ab 114 | ab 115 |
| Drac de na Coca · Schuppenpanzer | 86–106 | 89–103 | 91–101 | 92–101 | 92–100 | 93–100 |
| Drac de na Coca · Letzter Ansturm | ab 111 | ab 114 | ab 116 | ab 117 | ab 117 | ab 118 |
| Dimonis · Durch die Gassen | ab 93 | ab 96 | ab 98 | ab 99 | ab 99 | ab 100 |
| Dimonis · Über den Dorfplatz | ab 105 | ab 108 | ab 110 | ab 111 | ab 111 | ab 112 |
| Dimonis · Hinaus aus dem Dorf | ab 99 | ab 102 | ab 104 | ab 105 | ab 105 | ab 106 |

## Erreichbarkeit der Stufen

Laufbahn: neuer Spielstand (nur im Speicher), gefahren wird immer auf der höchsten freien Stufe; bessere Teile werden angelegt, der Rest verwertet, Talente und Arcade-Level wachsen mit den Punkten. Eine Stufe gilt als erreicht, wenn sie innerhalb der Läufe freigeschaltet wird (Stufen 1–3 sind von Beginn an frei). Ein Lauf = eine Fahrt von 0.75 Stunden.

| Verlauf | Ziel | Verläufe, die es schaffen | Läufe (Median) | Stunden (Median) | Läufe (90 %) | Stunden (90 %) |
|---|---|---|---|---|---|---|
| Einsteiger | Stufe 4 | 100 von 100 (100 %) | 3 | 2.3 | 5 | 3.8 |
| Einsteiger | Stufe 5 | 100 von 100 (100 %) | 5 | 3.8 | 8 | 6.0 |
| Einsteiger | Stufe 6 | 100 von 100 (100 %) | 9 | 6.8 | 11 | 8.3 |
| Einsteiger | Stufe 6 abgeschlossen | 100 von 100 (100 %) | 11 | 8.3 | 15 | 11.3 |
| Trainierter | Stufe 4 | 100 von 100 (100 %) | 1 | 0.8 | 1 | 0.8 |
| Trainierter | Stufe 5 | 100 von 100 (100 %) | 2 | 1.5 | 2 | 1.5 |
| Trainierter | Stufe 6 | 100 von 100 (100 %) | 3 | 2.3 | 3 | 2.3 |
| Trainierter | Stufe 6 abgeschlossen | 100 von 100 (100 %) | 4 | 3.0 | 4 | 3.0 |
| Sprinter | Stufe 4 | 100 von 100 (100 %) | 1 | 0.8 | 2 | 1.5 |
| Sprinter | Stufe 5 | 100 von 100 (100 %) | 2 | 1.5 | 3 | 2.3 |
| Sprinter | Stufe 6 | 100 von 100 (100 %) | 3 | 2.3 | 5 | 3.8 |
| Sprinter | Stufe 6 abgeschlossen | 100 von 100 (100 %) | 4 | 3.0 | 6 | 4.5 |

Wann die Ausrüstung (mit Talenten) die Empfohlene Stärke der Stufen 4–6 erreicht:

| Verlauf | Ziel | Verläufe, die es schaffen | Läufe (Median) | Stunden (Median) | Läufe (90 %) | Stunden (90 %) |
|---|---|---|---|---|---|---|
| Einsteiger | Stärke 35 (Empfehlung Stufe 4) | 100 von 100 (100 %) | 1 | 0.8 | 2 | 1.5 |
| Einsteiger | Stärke 50 (Empfehlung Stufe 5) | 100 von 100 (100 %) | 1 | 0.8 | 2 | 1.5 |
| Einsteiger | Stärke 70 (Empfehlung Stufe 6) | 100 von 100 (100 %) | 2 | 1.5 | 3 | 2.3 |
| Trainierter | Stärke 35 (Empfehlung Stufe 4) | 100 von 100 (100 %) | 1 | 0.8 | 1 | 0.8 |
| Trainierter | Stärke 50 (Empfehlung Stufe 5) | 100 von 100 (100 %) | 1 | 0.8 | 1 | 0.8 |
| Trainierter | Stärke 70 (Empfehlung Stufe 6) | 100 von 100 (100 %) | 1 | 0.8 | 1 | 0.8 |
| Sprinter | Stärke 35 (Empfehlung Stufe 4) | 100 von 100 (100 %) | 1 | 0.8 | 1 | 0.8 |
| Sprinter | Stärke 50 (Empfehlung Stufe 5) | 100 von 100 (100 %) | 1 | 0.8 | 1 | 0.8 |
| Sprinter | Stärke 70 (Empfehlung Stufe 6) | 100 von 100 (100 %) | 1 | 0.8 | 1 | 0.8 |

Stärke und Arcade-Level am Ende der Laufbahn (Median):

| Verlauf | Stärke | Level |
|---|---|---|
| Einsteiger | 100 | 12 |
| Trainierter | 100 | 12 |
| Sprinter | 100 | 12 |


## Lesart und Grenzen

- Die Kadenzverläufe sind **erfundene, dokumentierte Daten** (`Balancing.PROFILES`), keine Messungen. Absolute Quoten (z. B. „Einsteiger schafft Stufe 1 zu 46 %“) hängen an diesen Annahmen; belastbar sind **Verhältnisse und Brüche**: eine Herausforderung, die gegenüber ihrer Schwester oder gegenüber den Nachbarstufen abbricht, oder eine Stufe, die kein Verlauf erreicht. Kalibrieren mit echten Fahrten (JC312, #1) bleibt offen.
- Fähigkeiten (#50) und legendäre Effekte sind **nicht** simuliert (sie brauchen `cadence_raw` mit gezielten Gesten, die ein synthetischer Verlauf nur erfinden könnte). Alle Quoten sind deshalb eine Untergrenze: Fähigkeiten verstärken nur den Fortschritt mit Kadenz in der Zone.
- Fahrer „bei der Sache“ gelten für die Dauer einer Herausforderung als Zweizustandsmodell (siehe Kopf von `src/balancing.gd`); Laufbahnen legen das jeweils bessere Teil je Platz an, verwerten den Rest und geben Talentpunkte zuerst für Ausrüstungswerte aus.

## Auffälligkeiten und Nachjustierung

**Schwellen** (vorab festgelegt, gelten für diesen Lauf):

1. Eine Herausforderung, die der Trainierte auf irgendeiner Stufe zu weniger als 50 % schafft, während ihre Schwester (gleicher Baustein) dort mindestens 85 % schafft.
2. Eine Herausforderung, die der Trainierte auf Stufe 1 zu weniger als 50 % schafft.
3. Eine Seltenheit, die in einer Zelle (Verlauf × Stufe) nie fällt.
4. Eine Stufe, die weniger als die Hälfte der Laufbahnen innerhalb von 120 Läufen (90 Stunden) freischaltet.
5. Eine Schwelle (Durchbruch, Jagd, Sammeln), die auf der Obergrenze des Bereichs liegt (Tabelle „Zielzonen und Schwellen je Stufe“).

**Befunde:** (1) und (5) treffen auf *Spurt* (`durchbruch_spurt`) zu; (2), (3) und (4) auf nichts: schwächste Herausforderung des Trainierten auf Stufe 1 ist *Ufer* mit 70 %, jede Seltenheit fällt in jeder Zelle (seltenste Zelle: Einsteiger Stufe 1, 349 Legendäre in 1000 Fahrten), und alle 100 Laufbahnen jedes Verlaufs schalten Stufe 4, 5 und 6 frei (Einsteiger bis Stufe 6 in höchstens 11 Läufen).

*Spurt* lag mit `threshold_at` 0,9 bei 114 rpm und stieß ab Stufe 3 (Hub +5 rpm → 119) an die Obergrenze 120 rpm, ab Stufe 4 sitzt die Schwelle genau darauf („ab 120 rpm“ – nur das Maximum selbst genügt, dahinter der Wächter). Folge: Der Trainierte fällt von 85 % (Stufe 2) auf 49 % (Stufe 3) und 29 % (Stufe 6), die Schwester *Zugbrücke* bleibt bei 91–93 %.

| Datei | Wert vorher → nachher | Auffälligkeit vorher → nachher |
|---|---|---|
| `src/challenges/breakthrough_challenges.gd` (*Spurt*) | `threshold_at` 0,9 → 0,85 (114 → 111 rpm auf Stufe 1; Stufe 6: 120 → 118 rpm) | Trainierter, Stufe 1–6: 92 / 85 / 49 / 34 / 33 / 29 % → 94 / 93 / 89 / 89 / 86 / 84 %; Sprinter: 81 / 73 / 39 / 27 / 23 / 26 % → 84 / 81 / 77 / 76 / 72 / 71 %; Einsteiger: 27 / 4 / 0 / 0 / 0 / 0 % → 44 / 22 / 6 / 3 / 4 / 0 %; Schwelle auf der Obergrenze: Stufe 4–6 → keine (höchste 118 rpm) |

Mitgezogen: alle zusammen (Trainierter, Stufe 3–6) 83 / 80 / 79 / 78 % → 85 / 83 / 82 / 80 %, Sprinter 70 / 67 / 63 / 59 % → 72 / 70 / 66 / 61 %. Der Vorher-Bericht liegt als `arcade-balancing-vorher.md` bei (gleicher Seed, gleicher Befehl, alte Daten).

**Geänderte Testzeile** – `tests/test_arcade_tiers.gd`, `test_the_guard_catches_what_tier_and_round_would_push_out`: `var spurt := Encounters.find("durchbruch_spurt")` → `….duplicate()` plus `spurt["threshold_at"] = 0.9`. Begründung: Die Gegenprobe des Wächters (`limit_zone`) braucht eine Definition, die **ohne** Wächter über den Bereich hinausschösse; das war *Spurt* mit 90 %. Mit 85 % liegt *Spurt* auch auf Stufe 6, Runde 4 bei 118 rpm und überschießt nicht mehr. Die Assertions (`assert_gt(… + lift, 120.0)`, `Vector2(120, 120)`, `threshold_rpm == 120`) bleiben unverändert und gleich scharf – der Test hält seine eigene Kopie der alten Schwelle, statt vom Pool abzuhängen. Der Wächter selbst und jede Assertion sind unberührt.

Nicht geändert: Wächter, Kadenzbereich, Stufen (`ArcadeTiers.LIST`), Beute (`Loot`), Elite, Fähigkeiten, Muster.

## Offene Fragen an den Nutzer

Ohne messbare Schwelle, daher nicht still entschieden. Zahlen: Trainierter, ohne Ausrüstung, Stufe 1 → 6, falls nicht anders genannt.

1. **Bosse zu lang oder zu kurz?** *Drac de na Coca* Stufe 6: Zeitfenster des ganzen Kampfes 192 s; gewonnen Median 119 s, 90 % in 135 s (Sprinter 136 / 154 s). Stufe 1: 42 s. *Tramuntana* Stufe 6: Median 84 s, *Dimonis* nur 41 s (Stufe 1: 18 s). Ist Drac auf Stufe 6 zu lang, Dimonis zu kurz?
2. **Takt-Tore zu leicht bei konstanter Kadenz?** Direkt am Baustein gemessen: Wer konstant in der Zonenmitte tritt (*Ruhiger Takt* 84 rpm, *Flotter Takt* 99 rpm), schafft beide auf **allen** sechs Stufen. Trainierter: *Ruhiger Takt* 100 → 97 %, *Flotter Takt* 94 → 84 %. Takt-Tore sind also Zone-halten-zu-Schlagzeiten; soll es einen echten Wechsel von Kadenz verlangen?
3. **Elite-Chance unabhängig von der Stufe?** Anteil der Elite-Gruppen an den Herausforderungen ohne Boss: 15 / 15 / 15 / 15 / 14 / 15 % (Chance 0,15 überall). Ihre Quote sinkt dabei von 86 → 64 % (Champions) und 80 → 44 % (Seltene). Soll die Chance mit der Stufe steigen?
4. **Beute-Tempo.** 21 → 19 Funde je Stunde (Einsteiger 9,5 → 4,6). Die Empfohlene Stärke 35 / 50 / 70 erreichen Laufbahnen nach 1 Lauf (0,75 h; Einsteiger 1 / 1 / 2 Läufe), danach liegt die Stärke bei 100 (Obergrenze) und das Arcade-Level bei 12. Legendäre Teile machen 6 % (Stufe 1) bis 29 % (Stufe 6) der Funde aus, also 1,3 bis 5,6 je Stunde (Grundgewicht 2 %; Boss- und Elite-Qualität, Stufe heben es). Fallen zu viele Teile, ist die Stärke-Empfehlung zu früh erfüllt?
5. **Freischalttempo.** Stufe 4 / 5 / 6 nach 1 / 2 / 3 Läufen (0,75 / 1,5 / 2,25 h), Stufe 6 abgeschlossen nach 4 Läufen (3 h); Einsteiger 3 / 5 / 9 Läufe (2,25 / 3,75 / 6,75 h), abgeschlossen nach 11. Hauptgrund ist die schnell wachsende Ausrüstung (Frage 4), nicht das Treten. Soll das länger dauern?
6. **Sammeln für Einsteiger.** Auf Stufe 1 schafft der Einsteiger *Wiese* zu 13 % und *Ufer* zu 3 % (Trainierter 92 / 70 %); alle anderen Herausforderungen liegen für ihn bei 44–90 %. Ursache ist die Zahl der nötigen Objekte (*Wiese* braucht Radius 2,5 m ≈ 92 rpm). Ein Eingriff (`need` 5 → 4) ändert Tests (`test_elite_groups.gd`, `test_arcade_rhythm_collect*.gd`, Bridge-Profile `sammeln_*`) und README – nicht ohne Entscheidung angefasst.
7. **Einsteiger und die Spitzen.** Mit höchstens 118 rpm (Profilannahme) schafft der Einsteiger *Spurt* ab Stufe 3 und *Letzter Ansturm* ab Stufe 4 praktisch nie (0–6 %). Das ist eine Folge der Annahme, nicht der Daten – aber ob ein Einsteiger mit Standardbereich 60–120 rpm diese Schwellen je erreichen soll (oder erst mit angepasstem Bereich), ist eine Produktfrage.
8. **Empfehlung oder Pflicht?** Stufe 6 ohne Ausrüstung: alle Herausforderungen zusammen schafft der Trainierte zu 80 %, der Einsteiger zu 14 %. Mit der Empfohlenen Stärke (70) steigt der Einsteiger bei normalen Herausforderungen von 24 auf 61 %, bei Bossen von 4 auf 34 %; der Trainierte von 85 auf 95 % bzw. von 79 auf 92 %. Für den Einsteiger wirkt die Empfehlung damit wie eine Pflicht – gewollt, oder soll Fitness allein weiter tragen („Ausrüstung ersetzt nie das Treten“)?
9. **Sammeln: *Ufer* ab Stufe 4.** *Ufer* sinkt beim Trainierten von 70 % (Stufe 1) auf 44 / 39 / 33 % (Stufe 4 / 5 / 6), während die Schwester *Wiese* bei 84 % bleibt (Sprinter: *Ufer* 70–79 %). Die vorab festgelegte Schwelle (1) greift nur knapp nicht (*Wiese* 84 statt 85 %), daher nicht angepasst. Ist *Ufer* als schwerste Sammel-Aufgabe der oberen Stufen gewollt, oder sollen ihre Daten (`src/challenges/collect_challenges.gd`: `need`, Radius) näher an *Wiese* rücken?
