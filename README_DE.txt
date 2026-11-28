Levelmate 1.1.0 – Leveling-Assistent für WoW Forever
=====================================================

Levelmate plant für dich die effizienteste Questroute von Stufe 1 bis 60:
welche Quest du als Nächstes annimmst, erledigst oder abgibst, wohin du
fliegst, wann sich der Ruhestein lohnt und wann du zum Klassenlehrer gehst.

Voraussetzung
- QuestieDB (liefert die Quest- und NPC-Daten).
- Optional: TomTom (zusätzliche Wegpunkte), What's Training (Zauberpreise
  mit Rabatten).

Installation
1. WoW schließen.
2. Den Ordner "Levelmate" nach World of Warcraft\_forever_\Interface\AddOns
   kopieren (oder über die CurseForge-App installieren).
3. WoW starten. Beim ersten Einloggen erscheint die Moduswahl.

Das Fenster
- Oben: Stufe, Restzeit bis zur nächsten Stufe, unverteilte Talentpunkte.
  Rechts: Schriftrolle (neue Zauber beim Lehrer), Pfeil an/aus, Modus,
  Einstellungen.
- Darunter die empfohlenen Gebiete für deine Stufe.
- Die Karte zeigt den aktuellen Schritt mit Bewertung, XP und Zeit.
  "Später" stellt den Schritt zurück (kommt nach einem halben Level wieder),
  "Überspringen" nimmt eine Quest dauerhaft aus der Route. Der Pfeil holt
  den letzten Schritt sofort zurück, /lm ausgelassen leeren holt alle zurück.
- Klick auf einen Questnamen: Quests im Log öffnen das Questlog, Quests zum
  Annehmen öffnen die Weltkarte beim Questgeber.
- "Nächste Schritte" und "Questlog" lassen sich per Klick auf- und zuklappen.
- Dungeon-Fenster (Schlüssel-Symbol): Dungeons für deine Stufe mit ihren Quests
  ("Zuerst" setzt eine Quest an den Anfang der Route, "Karte" zeigt, wo sie
  anfängt), Bosse und die Beute, die bei dir gefallen ist. Mit AtlasLoot zeigt
  der Reiter "Beute" die komplette Beute jedes Bosses mit Dropchance.
- Klassenlehrer: Erscheint als Schritt, wenn du neue Zauber lernen kannst
  und der Lehrer in der Nähe ist oder du in seiner Hauptstadt bist.

Sprache
- Im Zahnrad-Fenster unter "Sprache": Automatisch (Spielsprache), Deutsch
  oder English. Quest-, NPC- und Gebietsnamen kommen immer in der Sprache
  deines Spiels.

Minimap-Knopf
- Linksklick: Fenster, Rechtsklick: Modus, Umschalt+Linksklick: Pfeil.

Befehle
/lm            Fenster anzeigen
/lm hide       Fenster ausblenden
/lm optionen   Einstellungen
/lm mode       Modus wählen
/lm arrow      Pfeil ein/aus
/lm tomtom     TomTom-Wegpunkte ein/aus
/lm minimap    Minimap-Knopf ein/aus
/lm scale 0.8  Fenstergröße (0.5 bis 1.5)
/lm reset      übersprungene Quests und Fensterposition zurücksetzen
/lm warum <Quest>  erklärt, warum eine Quest (nicht) vorgeschlagen wird
/lm karte      Route auf der Weltkarte ein/aus
/lm wege       bekannte Gebietsübergänge und Wege
/lm ausgelassen  dauerhaft übersprungene Quests (/lm ausgelassen leeren: alle zurück)
Rechtsklick auf den Pfeil: direkt zum Ziel / wieder dem Weg folgen
/lm lehrer     zeigt, was Levelmate über Lehrer und Zauber weiß
/lm export     gelernte Wege als Text zum Kopieren (z. B. für den Entwickler)
/lm import     Wege aus so einem Text übernehmen
/lm smart      gemessene XP pro Minute
/lm gruppe     Gruppenmodus: welche Mitspieler (mit Levelmate) deine Quests auch haben
/lm gruppe fenster  kleines Fenster mit Mitspielern, Stufe und gemeinsamen Quests
/lm sitzung    Spielzeit, Quests und XP dieser und der letzten Sitzung
/lm tipps      Einführung nochmal zeigen
/lm leistung   Rechenzeit des Addons
/lm zuerst <Quest>  Quest aus dem Questlog an erste Stelle (/lm zuerst: normale Reihenfolge)
/lm aufgang    Aufgang aufzeichnen (Rampe/Aufzug/Brücke): unten starten, oben nochmal
/lm bug        Fehlerbericht zum Kopieren (für Discord)
/lm diag       Diagnose

Hinweise
- Zeiten und XP sind Schätzungen; Levelmate lernt beim Spielen dein Tempo.
- Levelmate bringt Startwissen mit (bekannte Gebietsübergänge und Wege) und
  lernt beim Spielen weiter. Gelernte Wege werden nur auf deinem PC
  gespeichert und in der Gruppe mit anderen Levelmate-Nutzern geteilt.
- Inoffizielles Fan-Addon, nicht mit Blizzard Entertainment verbunden.
