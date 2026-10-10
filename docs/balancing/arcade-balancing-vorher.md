# Arcade-Balancing – Bericht der Simulation

- Seed: 1
- Läufe je Kadenzverlauf und Stufe: 1000 ohne Ausrüstung, 300 mit Empfohlener Stärke; Laufbahnen je Kadenzverlauf: 100 (höchstens 120 Läufe)
- Fahrt: 45 min auf dem Insel-Rundkurs (9210 m), Standardbereich 60–120 rpm
- Befehl: `godot --headless --path games/island-ride -s res://tools/balancing_sim.gd -- --runs=1000 --gear-runs=300 --careers=100 --seed=1 --commit=1a104b5 --date=2026-10-09 --note=Datenstand vor der Nachjustierung (Spurt threshold_at 0,9); Dezimalkomma seit der Nacharbeit 2026-10-10 --out=../../docs/balancing/arcade-balancing-vorher.md`
- Stand (Commit): 1a104b5
- Datum: 2026-10-09
- Hinweis: Datenstand vor der Nachjustierung (Spurt threshold_at 0,9); Dezimalkomma seit der Nacharbeit 2026-10-10

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
| Stufe 1 | 1000 | 9,3 | 3355 (48 %) | 2168 (31 %) | 1139 (16 %) | 352 (5 %) |
| Stufe 2 | 1000 | 7,9 | 2494 (42 %) | 1795 (30 %) | 1202 (20 %) | 457 (8 %) |
| Stufe 3 | 1000 | 6,5 | 1702 (35 %) | 1577 (32 %) | 1112 (23 %) | 529 (11 %) |
| Stufe 4 | 1000 | 6,0 | 1368 (30 %) | 1380 (31 %) | 1131 (25 %) | 631 (14 %) |
| Stufe 5 | 1000 | 5,5 | 997 (24 %) | 1166 (28 %) | 1222 (30 %) | 734 (18 %) |
| Stufe 6 | 1000 | 4,6 | 650 (19 %) | 956 (27 %) | 1096 (31 %) | 782 (22 %) |

### Erfolgsquote je Herausforderung und Stufe (ohne Ausrüstung)

Erfolgsquote (Zahl der beendeten Herausforderungen).

| Herausforderung | Stufe 1 | Stufe 2 | Stufe 3 | Stufe 4 | Stufe 5 | Stufe 6 |
|---|---|---|---|---|---|---|
| zone_mitte (Zone halten) | 78 % (582) | 70 % (611) | 56 % (607) | 49 % (620) | 40 % (607) | 28 % (600) |
| zone_ruhig (Zone halten) | 89 % (580) | 83 % (612) | 62 % (620) | 54 % (596) | 43 % (621) | 17 % (561) |
| zone_zuegig (Zone halten) | 71 % (583) | 64 % (572) | 57 % (633) | 52 % (610) | 39 % (533) | 27 % (618) |
| durchbruch_bruecke (Durchbruch) | 57 % (570) | 37 % (583) | 23 % (598) | 17 % (666) | 18 % (623) | 7 % (586) |
| durchbruch_spurt (Durchbruch) | 27 % (589) | 4 % (629) | 0 % (599) | 0 % (609) | 0 % (607) | 0 % (637) |
| jagd_verfolger (Jagd) | 64 % (585) | 57 % (597) | 54 % (626) | 49 % (617) | 49 % (629) | 49 % (632) |
| jagd_wild (Jagd) | 58 % (593) | 49 % (568) | 43 % (606) | 38 % (620) | 35 % (619) | 31 % (574) |
| takt_ruhig (Takt-Tore) | 85 % (643) | 78 % (600) | 72 % (631) | 64 % (597) | 68 % (607) | 59 % (614) |
| takt_flott (Takt-Tore) | 57 % (583) | 55 % (602) | 42 % (586) | 41 % (595) | 38 % (656) | 36 % (580) |
| sammeln_wiese (Sammeln) | 13 % (604) | 17 % (630) | 6 % (608) | 6 % (629) | 6 % (591) | 7 % (593) |
| sammeln_ufer (Sammeln) | 3 % (554) | 3 % (580) | 2 % (595) | 1 % (595) | 0 % (610) | 0 % (651) |
| Elite: Champions | 45 % (733) | 31 % (821) | 21 % (819) | 18 % (762) | 13 % (789) | 10 % (778) |
| Elite: Seltene | 38 % (409) | 22 % (395) | 10 % (431) | 8 % (434) | 5 % (435) | 4 % (438) |
| Boss: Tramuntana | 44 % (2000) | 32 % (2000) | 18 % (2000) | 13 % (2000) | 7 % (2000) | 3 % (2000) |
| Boss: Drac de na Coca | 13 % (2000) | 5 % (2000) | 2 % (2000) | 0 % (2000) | 0 % (2000) | 0 % (2000) |
| Boss: Dimonis | 44 % (1433) | 34 % (1594) | 17 % (1718) | 14 % (1776) | 13 % (1830) | 8 % (1804) |
| **alle zusammen** | 45 % (13041) | 35 % (13394) | 25 % (13677) | 22 % (13726) | 19 % (13757) | 14 % (13666) |
| Elite-Anteil an den Herausforderungen ohne Boss | 15 % | 16 % | 16 % | 15 % | 15 % | 15 % |

### Erfolgsquote der Boss-Phasen (ohne Ausrüstung)

Anteil der erreichten Phasen, die geschafft wurden.

| Phase | Stufe 1 | Stufe 2 | Stufe 3 | Stufe 4 | Stufe 5 | Stufe 6 |
|---|---|---|---|---|---|---|
| Tramuntana · Phase 1 Gegenwind | 80 % | 71 % | 58 % | 54 % | 41 % | 28 % |
| Tramuntana · Phase 2 Böe | 65 % | 59 % | 51 % | 50 % | 47 % | 45 % |
| Tramuntana · Phase 3 Sturmfront | 86 % | 76 % | 61 % | 48 % | 38 % | 24 % |
| Drac de na Coca · Phase 1 Feueratem | 83 % | 74 % | 64 % | 58 % | 48 % | 31 % |
| Drac de na Coca · Phase 2 Flügelschlag | 53 % | 29 % | 22 % | 18 % | 22 % | 19 % |
| Drac de na Coca · Phase 3 Schuppenpanzer | 82 % | 74 % | 64 % | 52 % | 50 % | 35 % |
| Drac de na Coca · Phase 4 Letzter Ansturm | 36 % | 31 % | 18 % | 0 % | 0 % | 0 % |
| Dimonis · Phase 1 Durch die Gassen | 65 % | 62 % | 57 % | 53 % | 50 % | 45 % |
| Dimonis · Phase 2 Über den Dorfplatz | 76 % | 65 % | 39 % | 37 % | 35 % | 30 % |
| Dimonis · Phase 3 Hinaus aus dem Dorf | 88 % | 83 % | 77 % | 73 % | 71 % | 61 % |

### Dauer je Boss (ohne Ausrüstung)

Sekunden vom Beginn des Kampfes bis zum Sieg bzw. Entkommen; Quantile nach dem Nächster-Rang-Verfahren.

| Boss | Stufe | Kämpfe | Sieg | Sieg: Median s | Sieg: 90 % s | Entkommen: Median s |
|---|---|---|---|---|---|---|
| Tramuntana | Stufe 1 | 2000 | 44 % | 37 | 44 | 26 |
| Tramuntana | Stufe 2 | 2000 | 32 % | 51 | 60 | 33 |
| Tramuntana | Stufe 3 | 2000 | 18 % | 69 | 78 | 32 |
| Tramuntana | Stufe 4 | 2000 | 13 % | 85 | 94 | 37 |
| Tramuntana | Stufe 5 | 2000 | 7 % | 100 | 112 | 43 |
| Tramuntana | Stufe 6 | 2000 | 3 % | 116 | 126 | 49 |
| Drac de na Coca | Stufe 1 | 2000 | 13 % | 56 | 62 | 32 |
| Drac de na Coca | Stufe 2 | 2000 | 5 % | 75 | 82 | 41 |
| Drac de na Coca | Stufe 3 | 2000 | 2 % | 97 | 105 | 52 |
| Drac de na Coca | Stufe 4 | 2000 | 0 % | – | – | 62 |
| Drac de na Coca | Stufe 5 | 2000 | 0 % | – | – | 51 |
| Drac de na Coca | Stufe 6 | 2000 | 0 % | – | – | 59 |
| Dimonis | Stufe 1 | 1433 | 44 % | 21 | 27 | 10 |
| Dimonis | Stufe 2 | 1594 | 34 % | 29 | 36 | 16 |
| Dimonis | Stufe 3 | 1718 | 17 % | 34 | 43 | 22 |
| Dimonis | Stufe 4 | 1776 | 14 % | 42 | 53 | 22 |
| Dimonis | Stufe 5 | 1830 | 13 % | 48 | 59 | 22 |
| Dimonis | Stufe 6 | 1804 | 8 % | 58 | 75 | 20 |

### Mit Empfohlener Stärke (300 Fahrten je Stufe)

Erfolgsquote ohne → mit Ausrüstung der Empfohlenen Stärke.

| Stufe | Empfohlene Stärke | Normal ohne | Normal mit | Elite ohne | Elite mit | Boss ohne | Boss mit |
|---|---|---|---|---|---|---|---|
| Stufe 1 | 0 (Zone +0 rpm, Fortschritt +0 %) | 55 % | 54 % | 42 % | 39 % | 33 % | 34 % |
| Stufe 2 | 10 (Zone +1 rpm, Fortschritt +6 %) | 47 % | 50 % | 28 % | 33 % | 23 % | 26 % |
| Stufe 3 | 20 (Zone +2 rpm, Fortschritt +12 %) | 38 % | 45 % | 17 % | 23 % | 12 % | 21 % |
| Stufe 4 | 35 (Zone +4 rpm, Fortschritt +19 %) | 34 % | 50 % | 15 % | 30 % | 9 % | 25 % |
| Stufe 5 | 50 (Zone +6 rpm, Fortschritt +26 %) | 31 % | 54 % | 10 % | 39 % | 6 % | 30 % |
| Stufe 6 | 70 (Zone +8 rpm, Fortschritt +38 %) | 24 % | 60 % | 8 % | 46 % | 4 % | 33 % |

## Trainierter

### Häufigkeit je Seltenheit (ohne Ausrüstung)

Funde je Stufe: absolut (Anteil an allen Funden).

| Stufe | Fahrten | Funde/h | Gewöhnlich | Magisch | Selten | Legendär |
|---|---|---|---|---|---|---|
| Stufe 1 | 1000 | 21,1 | 7328 (46 %) | 4847 (31 %) | 2703 (17 %) | 983 (6 %) |
| Stufe 2 | 1000 | 20,8 | 6057 (39 %) | 4835 (31 %) | 3337 (21 %) | 1451 (9 %) |
| Stufe 3 | 1000 | 20,0 | 4925 (33 %) | 4447 (30 %) | 3711 (25 %) | 1965 (13 %) |
| Stufe 4 | 1000 | 19,4 | 3815 (26 %) | 4231 (29 %) | 4099 (28 %) | 2482 (17 %) |
| Stufe 5 | 1000 | 19,2 | 3039 (21 %) | 3824 (26 %) | 4356 (30 %) | 3258 (23 %) |
| Stufe 6 | 1000 | 18,8 | 2105 (15 %) | 3364 (24 %) | 4584 (32 %) | 4129 (29 %) |

### Erfolgsquote je Herausforderung und Stufe (ohne Ausrüstung)

Erfolgsquote (Zahl der beendeten Herausforderungen).

| Herausforderung | Stufe 1 | Stufe 2 | Stufe 3 | Stufe 4 | Stufe 5 | Stufe 6 |
|---|---|---|---|---|---|---|
| zone_mitte (Zone halten) | 100 % (810) | 100 % (798) | 98 % (800) | 99 % (783) | 98 % (830) | 98 % (810) |
| zone_ruhig (Zone halten) | 99 % (771) | 99 % (825) | 98 % (801) | 98 % (807) | 96 % (780) | 95 % (802) |
| zone_zuegig (Zone halten) | 97 % (827) | 96 % (767) | 97 % (773) | 96 % (763) | 95 % (784) | 95 % (756) |
| durchbruch_bruecke (Durchbruch) | 93 % (808) | 93 % (810) | 91 % (802) | 93 % (763) | 92 % (782) | 92 % (780) |
| durchbruch_spurt (Durchbruch) | 92 % (829) | 85 % (829) | 49 % (800) | 34 % (793) | 33 % (789) | 29 % (755) |
| jagd_verfolger (Jagd) | 92 % (778) | 90 % (833) | 90 % (836) | 87 % (782) | 90 % (745) | 88 % (760) |
| jagd_wild (Jagd) | 89 % (821) | 88 % (805) | 86 % (843) | 85 % (802) | 85 % (775) | 84 % (823) |
| takt_ruhig (Takt-Tore) | 100 % (817) | 100 % (794) | 98 % (761) | 98 % (732) | 97 % (800) | 97 % (743) |
| takt_flott (Takt-Tore) | 93 % (810) | 87 % (834) | 83 % (804) | 85 % (819) | 82 % (777) | 84 % (776) |
| sammeln_wiese (Sammeln) | 91 % (813) | 89 % (814) | 85 % (786) | 84 % (814) | 83 % (774) | 84 % (760) |
| sammeln_ufer (Sammeln) | 70 % (802) | 68 % (821) | 59 % (791) | 45 % (827) | 38 % (807) | 33 % (737) |
| Elite: Champions | 85 % (1033) | 81 % (1027) | 74 % (970) | 68 % (999) | 69 % (893) | 58 % (931) |
| Elite: Seltene | 79 % (531) | 70 % (525) | 65 % (530) | 57 % (516) | 52 % (554) | 43 % (526) |
| Boss: Tramuntana | 91 % (2841) | 89 % (2946) | 88 % (2988) | 88 % (2995) | 87 % (2997) | 88 % (3000) |
| Boss: Drac de na Coca | 85 % (2000) | 81 % (2000) | 78 % (2000) | 76 % (2000) | 72 % (2000) | 71 % (2000) |
| Boss: Dimonis | 86 % (2000) | 84 % (2000) | 83 % (2000) | 80 % (2000) | 80 % (2000) | 77 % (2000) |
| **alle zusammen** | 90 % (17291) | 87 % (17428) | 83 % (17285) | 80 % (17195) | 79 % (17087) | 78 % (16959) |
| Elite-Anteil an den Herausforderungen ohne Boss | 15 % | 15 % | 15 % | 15 % | 14 % | 15 % |

### Erfolgsquote der Boss-Phasen (ohne Ausrüstung)

Anteil der erreichten Phasen, die geschafft wurden.

| Phase | Stufe 1 | Stufe 2 | Stufe 3 | Stufe 4 | Stufe 5 | Stufe 6 |
|---|---|---|---|---|---|---|
| Tramuntana · Phase 1 Gegenwind | 100 % | 99 % | 98 % | 98 % | 98 % | 98 % |
| Tramuntana · Phase 2 Böe | 93 % | 93 % | 93 % | 94 % | 93 % | 95 % |
| Tramuntana · Phase 3 Sturmfront | 99 % | 97 % | 96 % | 95 % | 95 % | 95 % |
| Drac de na Coca · Phase 1 Feueratem | 100 % | 100 % | 100 % | 99 % | 100 % | 100 % |
| Drac de na Coca · Phase 2 Flügelschlag | 91 % | 91 % | 93 % | 91 % | 91 % | 92 % |
| Drac de na Coca · Phase 3 Schuppenpanzer | 99 % | 97 % | 96 % | 96 % | 96 % | 95 % |
| Drac de na Coca · Phase 4 Letzter Ansturm | 94 % | 92 % | 88 % | 87 % | 83 % | 81 % |
| Dimonis · Phase 1 Durch die Gassen | 92 % | 91 % | 90 % | 89 % | 88 % | 87 % |
| Dimonis · Phase 2 Über den Dorfplatz | 97 % | 97 % | 96 % | 96 % | 96 % | 96 % |
| Dimonis · Phase 3 Hinaus aus dem Dorf | 96 % | 95 % | 96 % | 93 % | 95 % | 91 % |

### Dauer je Boss (ohne Ausrüstung)

Sekunden vom Beginn des Kampfes bis zum Sieg bzw. Entkommen; Quantile nach dem Nächster-Rang-Verfahren.

| Boss | Stufe | Kämpfe | Sieg | Sieg: Median s | Sieg: 90 % s | Entkommen: Median s |
|---|---|---|---|---|---|---|
| Tramuntana | Stufe 1 | 2841 | 91 % | 31 | 33 | 27 |
| Tramuntana | Stufe 2 | 2946 | 89 % | 40 | 44 | 33 |
| Tramuntana | Stufe 3 | 2988 | 88 % | 50 | 57 | 41 |
| Tramuntana | Stufe 4 | 2995 | 88 % | 60 | 69 | 50 |
| Tramuntana | Stufe 5 | 2997 | 87 % | 71 | 83 | 59 |
| Tramuntana | Stufe 6 | 3000 | 88 % | 84 | 97 | 69 |
| Drac de na Coca | Stufe 1 | 2000 | 85 % | 42 | 47 | 32 |
| Drac de na Coca | Stufe 2 | 2000 | 81 % | 55 | 61 | 56 |
| Drac de na Coca | Stufe 3 | 2000 | 78 % | 70 | 79 | 75 |
| Drac de na Coca | Stufe 4 | 2000 | 76 % | 83 | 94 | 88 |
| Drac de na Coca | Stufe 5 | 2000 | 72 % | 99 | 113 | 104 |
| Drac de na Coca | Stufe 6 | 2000 | 71 % | 119 | 135 | 123 |
| Dimonis | Stufe 1 | 2000 | 86 % | 18 | 18 | 12 |
| Dimonis | Stufe 2 | 2000 | 84 % | 22 | 24 | 16 |
| Dimonis | Stufe 3 | 2000 | 83 % | 26 | 31 | 14 |
| Dimonis | Stufe 4 | 2000 | 80 % | 31 | 39 | 20 |
| Dimonis | Stufe 5 | 2000 | 80 % | 36 | 45 | 16 |
| Dimonis | Stufe 6 | 2000 | 77 % | 41 | 53 | 25 |

### Mit Empfohlener Stärke (300 Fahrten je Stufe)

Erfolgsquote ohne → mit Ausrüstung der Empfohlenen Stärke.

| Stufe | Empfohlene Stärke | Normal ohne | Normal mit | Elite ohne | Elite mit | Boss ohne | Boss mit |
|---|---|---|---|---|---|---|---|
| Stufe 1 | 0 (Zone +0 rpm, Fortschritt +0 %) | 92 % | 92 % | 83 % | 84 % | 88 % | 87 % |
| Stufe 2 | 10 (Zone +1 rpm, Fortschritt +6 %) | 90 % | 92 % | 77 % | 85 % | 85 % | 87 % |
| Stufe 3 | 20 (Zone +2 rpm, Fortschritt +12 %) | 85 % | 91 % | 71 % | 78 % | 84 % | 86 % |
| Stufe 4 | 35 (Zone +4 rpm, Fortschritt +19 %) | 82 % | 93 % | 65 % | 85 % | 82 % | 89 % |
| Stufe 5 | 50 (Zone +6 rpm, Fortschritt +26 %) | 81 % | 94 % | 62 % | 88 % | 81 % | 90 % |
| Stufe 6 | 70 (Zone +8 rpm, Fortschritt +38 %) | 80 % | 96 % | 52 % | 92 % | 80 % | 92 % |

## Sprinter

### Häufigkeit je Seltenheit (ohne Ausrüstung)

Funde je Stufe: absolut (Anteil an allen Funden).

| Stufe | Fahrten | Funde/h | Gewöhnlich | Magisch | Selten | Legendär |
|---|---|---|---|---|---|---|
| Stufe 1 | 1000 | 20,0 | 7074 (47 %) | 4529 (30 %) | 2482 (17 %) | 886 (6 %) |
| Stufe 2 | 1000 | 19,1 | 5686 (40 %) | 4275 (30 %) | 2955 (21 %) | 1384 (10 %) |
| Stufe 3 | 1000 | 17,6 | 4306 (33 %) | 4033 (31 %) | 3236 (25 %) | 1630 (12 %) |
| Stufe 4 | 1000 | 16,9 | 3436 (27 %) | 3719 (29 %) | 3414 (27 %) | 2100 (17 %) |
| Stufe 5 | 1000 | 16,1 | 2713 (22 %) | 3203 (27 %) | 3662 (30 %) | 2503 (21 %) |
| Stufe 6 | 1000 | 15,2 | 1899 (17 %) | 2792 (24 %) | 3641 (32 %) | 3088 (27 %) |

### Erfolgsquote je Herausforderung und Stufe (ohne Ausrüstung)

Erfolgsquote (Zahl der beendeten Herausforderungen).

| Herausforderung | Stufe 1 | Stufe 2 | Stufe 3 | Stufe 4 | Stufe 5 | Stufe 6 |
|---|---|---|---|---|---|---|
| zone_mitte (Zone halten) | 99 % (851) | 97 % (809) | 94 % (816) | 94 % (757) | 89 % (762) | 85 % (738) |
| zone_ruhig (Zone halten) | 94 % (802) | 90 % (779) | 81 % (777) | 77 % (805) | 70 % (792) | 58 % (780) |
| zone_zuegig (Zone halten) | 95 % (784) | 93 % (802) | 90 % (847) | 87 % (780) | 81 % (756) | 76 % (788) |
| durchbruch_bruecke (Durchbruch) | 85 % (811) | 82 % (826) | 84 % (803) | 81 % (766) | 78 % (790) | 77 % (819) |
| durchbruch_spurt (Durchbruch) | 81 % (753) | 73 % (763) | 39 % (839) | 27 % (770) | 23 % (705) | 26 % (761) |
| jagd_verfolger (Jagd) | 85 % (813) | 80 % (801) | 76 % (735) | 72 % (738) | 73 % (786) | 72 % (744) |
| jagd_wild (Jagd) | 76 % (824) | 72 % (803) | 68 % (733) | 68 % (785) | 68 % (800) | 62 % (777) |
| takt_ruhig (Takt-Tore) | 97 % (816) | 94 % (814) | 91 % (799) | 85 % (766) | 86 % (695) | 82 % (750) |
| takt_flott (Takt-Tore) | 90 % (815) | 79 % (797) | 72 % (795) | 76 % (761) | 65 % (792) | 72 % (764) |
| sammeln_wiese (Sammeln) | 94 % (780) | 89 % (796) | 88 % (740) | 88 % (808) | 89 % (773) | 90 % (726) |
| sammeln_ufer (Sammeln) | 80 % (838) | 77 % (827) | 71 % (792) | 70 % (813) | 74 % (781) | 72 % (701) |
| Elite: Champions | 84 % (1067) | 77 % (1029) | 65 % (1024) | 63 % (1008) | 53 % (985) | 50 % (972) |
| Elite: Seltene | 77 % (529) | 65 % (591) | 48 % (583) | 41 % (506) | 35 % (541) | 34 % (552) |
| Boss: Tramuntana | 81 % (3000) | 78 % (3000) | 70 % (3000) | 68 % (3000) | 60 % (3000) | 55 % (3000) |
| Boss: Drac de na Coca | 67 % (2000) | 64 % (2000) | 54 % (2000) | 51 % (2000) | 46 % (2000) | 34 % (2000) |
| Boss: Dimonis | 74 % (2000) | 69 % (2000) | 62 % (2000) | 58 % (2000) | 54 % (2000) | 51 % (2000) |
| **alle zusammen** | 82 % (17483) | 78 % (17437) | 70 % (17283) | 67 % (17063) | 63 % (16958) | 59 % (16872) |
| Elite-Anteil an den Herausforderungen ohne Boss | 15 % | 16 % | 16 % | 15 % | 15 % | 15 % |

### Erfolgsquote der Boss-Phasen (ohne Ausrüstung)

Anteil der erreichten Phasen, die geschafft wurden.

| Phase | Stufe 1 | Stufe 2 | Stufe 3 | Stufe 4 | Stufe 5 | Stufe 6 |
|---|---|---|---|---|---|---|
| Tramuntana · Phase 1 Gegenwind | 98 % | 96 % | 92 % | 90 % | 87 % | 81 % |
| Tramuntana · Phase 2 Böe | 84 % | 86 % | 84 % | 86 % | 85 % | 87 % |
| Tramuntana · Phase 3 Sturmfront | 98 % | 95 % | 91 % | 87 % | 81 % | 78 % |
| Drac de na Coca · Phase 1 Feueratem | 98 % | 96 % | 92 % | 91 % | 90 % | 83 % |
| Drac de na Coca · Phase 2 Flügelschlag | 83 % | 82 % | 83 % | 83 % | 82 % | 79 % |
| Drac de na Coca · Phase 3 Schuppenpanzer | 98 % | 97 % | 93 % | 91 % | 87 % | 80 % |
| Drac de na Coca · Phase 4 Letzter Ansturm | 83 % | 84 % | 76 % | 74 % | 72 % | 64 % |
| Dimonis · Phase 1 Durch die Gassen | 87 % | 83 % | 78 % | 76 % | 73 % | 71 % |
| Dimonis · Phase 2 Über den Dorfplatz | 91 % | 92 % | 91 % | 89 % | 90 % | 89 % |
| Dimonis · Phase 3 Hinaus aus dem Dorf | 93 % | 91 % | 88 % | 86 % | 83 % | 81 % |

### Dauer je Boss (ohne Ausrüstung)

Sekunden vom Beginn des Kampfes bis zum Sieg bzw. Entkommen; Quantile nach dem Nächster-Rang-Verfahren.

| Boss | Stufe | Kämpfe | Sieg | Sieg: Median s | Sieg: 90 % s | Entkommen: Median s |
|---|---|---|---|---|---|---|
| Tramuntana | Stufe 1 | 3000 | 81 % | 31 | 37 | 27 |
| Tramuntana | Stufe 2 | 3000 | 78 % | 40 | 49 | 35 |
| Tramuntana | Stufe 3 | 3000 | 70 % | 55 | 65 | 44 |
| Tramuntana | Stufe 4 | 3000 | 68 % | 68 | 81 | 53 |
| Tramuntana | Stufe 5 | 3000 | 60 % | 82 | 97 | 64 |
| Tramuntana | Stufe 6 | 3000 | 55 % | 100 | 115 | 72 |
| Drac de na Coca | Stufe 1 | 2000 | 67 % | 40 | 48 | 35 |
| Drac de na Coca | Stufe 2 | 2000 | 64 % | 54 | 64 | 43 |
| Drac de na Coca | Stufe 3 | 2000 | 54 % | 72 | 84 | 66 |
| Drac de na Coca | Stufe 4 | 2000 | 51 % | 89 | 104 | 80 |
| Drac de na Coca | Stufe 5 | 2000 | 46 % | 110 | 127 | 93 |
| Drac de na Coca | Stufe 6 | 2000 | 34 % | 136 | 154 | 99 |
| Dimonis | Stufe 1 | 2000 | 74 % | 18 | 24 | 20 |
| Dimonis | Stufe 2 | 2000 | 69 % | 22 | 31 | 17 |
| Dimonis | Stufe 3 | 2000 | 62 % | 26 | 38 | 16 |
| Dimonis | Stufe 4 | 2000 | 58 % | 31 | 43 | 19 |
| Dimonis | Stufe 5 | 2000 | 54 % | 36 | 51 | 19 |
| Dimonis | Stufe 6 | 2000 | 51 % | 41 | 60 | 22 |

### Mit Empfohlener Stärke (300 Fahrten je Stufe)

Erfolgsquote ohne → mit Ausrüstung der Empfohlenen Stärke.

| Stufe | Empfohlene Stärke | Normal ohne | Normal mit | Elite ohne | Elite mit | Boss ohne | Boss mit |
|---|---|---|---|---|---|---|---|
| Stufe 1 | 0 (Zone +0 rpm, Fortschritt +0 %) | 89 % | 88 % | 82 % | 81 % | 75 % | 74 % |
| Stufe 2 | 10 (Zone +1 rpm, Fortschritt +6 %) | 84 % | 87 % | 73 % | 72 % | 71 % | 73 % |
| Stufe 3 | 20 (Zone +2 rpm, Fortschritt +12 %) | 78 % | 84 % | 59 % | 76 % | 63 % | 72 % |
| Stufe 4 | 35 (Zone +4 rpm, Fortschritt +19 %) | 75 % | 88 % | 56 % | 75 % | 60 % | 76 % |
| Stufe 5 | 50 (Zone +6 rpm, Fortschritt +26 %) | 73 % | 90 % | 47 % | 79 % | 55 % | 79 % |
| Stufe 6 | 70 (Zone +8 rpm, Fortschritt +38 %) | 70 % | 92 % | 44 % | 84 % | 48 % | 82 % |

## Zielzonen und Schwellen je Stufe

Standardbereich 60–120 rpm, erste Runde, ohne Ausrüstung (rpm).

| Herausforderung | Stufe 1 | Stufe 2 | Stufe 3 | Stufe 4 | Stufe 5 | Stufe 6 |
|---|---|---|---|---|---|---|
| zone_mitte | 80–100 | 83–97 | 85–95 | 86–95 | 86–94 | 87–94 |
| zone_ruhig | 71–91 | 74–88 | 76–86 | 77–86 | 77–85 | 78–85 |
| zone_zuegig | 87–107 | 90–104 | 92–102 | 93–102 | 93–101 | 94–101 |
| durchbruch_bruecke | ab 108 | ab 111 | ab 113 | ab 114 | ab 114 | ab 115 |
| durchbruch_spurt | ab 114 | ab 117 | ab 119 | ab 120 (Obergrenze) | ab 120 (Obergrenze) | ab 120 (Obergrenze) |
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

Laufbahn: neuer Spielstand (nur im Speicher), gefahren wird immer auf der höchsten freien Stufe; bessere Teile werden angelegt, der Rest verwertet, Talente und Arcade-Level wachsen mit den Punkten. Eine Stufe gilt als erreicht, wenn sie innerhalb der Läufe freigeschaltet wird (Stufen 1–3 sind von Beginn an frei). Ein Lauf = eine Fahrt von 0,75 Stunden.

| Verlauf | Ziel | Verläufe, die es schaffen | Läufe (Median) | Stunden (Median) | Läufe (90 %) | Stunden (90 %) |
|---|---|---|---|---|---|---|
| Einsteiger | Stufe 4 | 100 von 100 (100 %) | 3 | 2,3 | 5 | 3,8 |
| Einsteiger | Stufe 5 | 100 von 100 (100 %) | 5 | 3,8 | 8 | 6,0 |
| Einsteiger | Stufe 6 | 100 von 100 (100 %) | 8 | 6,0 | 11 | 8,3 |
| Einsteiger | Stufe 6 abgeschlossen | 100 von 100 (100 %) | 11 | 8,3 | 15 | 11,3 |
| Trainierter | Stufe 4 | 100 von 100 (100 %) | 1 | 0,8 | 1 | 0,8 |
| Trainierter | Stufe 5 | 100 von 100 (100 %) | 2 | 1,5 | 3 | 2,3 |
| Trainierter | Stufe 6 | 100 von 100 (100 %) | 3 | 2,3 | 4 | 3,0 |
| Trainierter | Stufe 6 abgeschlossen | 100 von 100 (100 %) | 4 | 3,0 | 5 | 3,8 |
| Sprinter | Stufe 4 | 100 von 100 (100 %) | 1 | 0,8 | 2 | 1,5 |
| Sprinter | Stufe 5 | 100 von 100 (100 %) | 2 | 1,5 | 3 | 2,3 |
| Sprinter | Stufe 6 | 100 von 100 (100 %) | 3 | 2,3 | 4 | 3,0 |
| Sprinter | Stufe 6 abgeschlossen | 100 von 100 (100 %) | 4 | 3,0 | 6 | 4,5 |

Wann die Ausrüstung (mit Talenten) die Empfohlene Stärke der Stufen 4–6 erreicht:

| Verlauf | Ziel | Verläufe, die es schaffen | Läufe (Median) | Stunden (Median) | Läufe (90 %) | Stunden (90 %) |
|---|---|---|---|---|---|---|
| Einsteiger | Stärke 35 (Empfehlung Stufe 4) | 100 von 100 (100 %) | 1 | 0,8 | 2 | 1,5 |
| Einsteiger | Stärke 50 (Empfehlung Stufe 5) | 100 von 100 (100 %) | 1 | 0,8 | 2 | 1,5 |
| Einsteiger | Stärke 70 (Empfehlung Stufe 6) | 100 von 100 (100 %) | 2 | 1,5 | 3 | 2,3 |
| Trainierter | Stärke 35 (Empfehlung Stufe 4) | 100 von 100 (100 %) | 1 | 0,8 | 1 | 0,8 |
| Trainierter | Stärke 50 (Empfehlung Stufe 5) | 100 von 100 (100 %) | 1 | 0,8 | 1 | 0,8 |
| Trainierter | Stärke 70 (Empfehlung Stufe 6) | 100 von 100 (100 %) | 1 | 0,8 | 1 | 0,8 |
| Sprinter | Stärke 35 (Empfehlung Stufe 4) | 100 von 100 (100 %) | 1 | 0,8 | 1 | 0,8 |
| Sprinter | Stärke 50 (Empfehlung Stufe 5) | 100 von 100 (100 %) | 1 | 0,8 | 1 | 0,8 |
| Sprinter | Stärke 70 (Empfehlung Stufe 6) | 100 von 100 (100 %) | 1 | 0,8 | 1 | 0,8 |

Stärke und Arcade-Level am Ende der Laufbahn (Median):

| Verlauf | Stärke | Level |
|---|---|---|
| Einsteiger | 100 | 12 |
| Trainierter | 100 | 12 |
| Sprinter | 100 | 12 |
