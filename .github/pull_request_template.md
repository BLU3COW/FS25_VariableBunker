# Pull request

## Summary | Zusammenfassung

Describe what changed and why. | Beschreiben Sie, was sich geändert hat und warum.

## Change type | Art der Änderung

- [ ] Bug fix | Fehlerbehebung
- [ ] Feature or configuration behavior | Funktion oder Konfigurationsverhalten
- [ ] Balancing / values / ranges | Balancing / Werte / Bereiche
- [ ] Localization | Lokalisierung
- [ ] Documentation | Dokumentation
- [ ] Repository or GitHub metadata only | Nur Repository- oder GitHub-Metadaten
- [ ] Release packaging | Release-Paketierung

## Affected area | Betroffener Bereich

- [ ] Core / `modDesc.xml` | Kern
- [ ] `xml/VariableBunker.xml` (placeable / configurations)
- [ ] `i3d/VariableBunker.i3d` / geometry | Geometrie
- [ ] `lua/VariableBunker.lua`
- [ ] `lua/VariableBunkerRegister.lua`
- [ ] `lua/VariableBunkerAutoDrive.lua`
- [ ] Localization in `l10n/` | Lokalisierung
- [ ] Mod icon `icon_VariableBunker.dds` / store assets in `dds/`
- [ ] README / documentation | README / Dokumentation
- [ ] `.github/` templates or community files | Vorlagen oder Community-Dateien

## Repository structure checklist | Checkliste zur Repository-Struktur

- [ ] The repository root still matches the FS25 mod root. | Das Repository-Stammverzeichnis stimmt weiterhin mit dem FS25-Mod-Stammverzeichnis überein.
- [ ] `modDesc.xml` remains in the repository root. | `modDesc.xml` verbleibt im Repository-Stammverzeichnis.
- [ ] The mod icon stays beside `modDesc.xml`; other runtime files stay in `lua/`, `l10n/`, `dds/`, `i3d/`, or `xml/`. | Das Mod-Icon verbleibt neben `modDesc.xml`; andere Laufzeit-Mod-Dateien verbleiben in `lua/`, `l10n/`, `dds/`, `i3d/` oder `xml/`.
- [ ] GitHub-only files stay in `.github/` or root documentation files. | GitHub-spezifische Dateien verbleiben in `.github/` oder im Stammverzeichnis der Dokumentation.
- [ ] No generated zip files, logs, savegames, cache files, or local test output were committed. | Es wurden keine generierten ZIP-Dateien, Protokolle, Spielstände, Cache-Dateien oder lokale Testausgaben eingecheckt.

## Testing | Tests

- [ ] Ran `Build-VariableBunker.ps1` (configuration validation, GIANTS Editor I3D check, TestRunner) locally. | `Build-VariableBunker.ps1` lokal ausgeführt (Konfigurationsvalidierung, GIANTS-Editor-I3D-Check, TestRunner).
- [ ] Tested in Farming Simulator 25. | In „Farming Simulator 25" getestet.
- [ ] Checked `log.txt` for new errors or warnings. | `log.txt` auf neue Fehler oder Warnungen überprüft.
- [ ] Tested on dedicated server, if affected. | Auf einem dedizierten Server getestet, sofern betroffen.
- [ ] Localization was checked in-game, if text changed. | Die Lokalisierung wurde im Spiel überprüft, sofern sich der Text geändert hat.
- [ ] Not applicable because this only changes documentation or GitHub metadata. | Nicht zutreffend, da sich hierdurch nur die Dokumentation oder die GitHub-Metadaten ändern.

## Notes, screenshots, or logs | Anmerkungen, Screenshots oder Protokolle

Add screenshots, videos, or relevant `log.txt` snippets if useful. | Füge Screenshots, Videos oder relevante Ausschnitte aus der `log.txt` hinzu, falls dies hilfreich ist.
