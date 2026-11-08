# Anleitung: Ein neues Spiel starten

Dieses Repo ist die Vorlage **Claude Code Game Studios** (Quelle: github.com/Donchitos/Claude-Code-Game-Studios, Stand `05ad7c8`, MIT-Lizenz © 2026 Donchitos, siehe `LICENSE`). Sie macht aus einer Claude-Code-Sitzung ein kleines Spielestudio: 49 spezialisierte Agenten (Direktoren, Abteilungsleiter, Spezialisten), 74 Skills, Hooks und Regeln, die auf Qualität achten.

**Hier wird kein Spiel gebaut.** Für jedes Spiel machst du eine Kopie:

1. Auf GitHub in diesem Repo oben auf **„Use this template“** → **„Create a new repository“**. Name = dein Spiel (z. B. `mein-spiel`), Private.
   (Den Knopf gibt es erst, wenn unter **Settings → General** „Template repository“ angehakt ist.)
2. Eine neue Claude-Code-Sitzung mit **dem neuen Spiel-Repo** starten.
3. **`/start`** eingeben. Claude fragt, wo du stehst (keine Idee, grobe Idee, klares Design, vorhandenes Projekt) und führt dich weiter.

Direkt einsteigen geht auch:

- `/brainstorm`: Spielideen von null an entwickeln
- `/setup-engine godot 4.7`: Engine festlegen (Godot, Unity oder Unreal)
- `/settings modes.rigor=minimal|standard|full`: wie viel Planung und Dokumentation vorab (Standard ist `minimal`, am schnellsten)

Voraussetzungen: Git, Python 3 und Bash. Sie sind in Cloud-Sitzungen vorhanden. Die Engine selbst (z. B. Godot) muss für das Spiel installiert sein.

Updates der Vorlage: siehe `UPGRADING.md`.
