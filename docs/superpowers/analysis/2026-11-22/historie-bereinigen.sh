#!/usr/bin/env bash
# Entfernt Klarnamen und private E-Mail-Adressen aus den Autor- und Committer-Feldern der Git-Historie (Befund GIT-1).
#
# Was das Skript tut:
#   1. Spiegelt das Repo in einen neuen Ordner und legt eine Sicherung als Bundle an.
#   2. Ersetzt in jedem Commit, dessen Autor- oder Committer-Adresse keine Noreply-Adresse ist, Name und Adresse
#      durch die häufigste Noreply-Identität des Repos. Inhalt, Nachrichten und Zeitstempel bleiben gleich.
#   3. Prüft das Ergebnis (gleiche Dateibäume, gleiche Commit-Zahl je Ref, keine Fremd-Adresse mehr).
#   4. Überschreibt nach Rückfrage die betroffenen Branches und Tags per Force-Push.
#
# Nicht angefasst werden Branches mit signierten Commits (die Signatur ginge verloren) und alles, was die
# betroffenen Commits nicht enthält (z. B. main).
#
# Aufruf:   bash historie-bereinigen.sh <Repo-Adresse>
# Beispiel: bash historie-bereinigen.sh git@github.com:<konto>/<repo>.git
#
# Folgen: Alle Commit-Hashes ab dem ersten betroffenen Commit ändern sich. Vorhandene Klone danach neu holen
# (git fetch --all --tags --force, dann lokale Branches auf origin/<name> zurücksetzen) oder frisch klonen.
set -euo pipefail

URL="${1:?Repo-Adresse fehlt}"
WORK="$(mktemp -d)"
echo "Arbeitsordner: $WORK"
cd "$WORK"

git clone --quiet --mirror "$URL" original.git
git -C original.git bundle create --quiet "$WORK/sicherung-vor-umschreiben.bundle" --all
cp -r original.git neu.git
cd neu.git
git config --unset remote.origin.mirror || true

BETROFFEN=$(git log --all --format='%ae %ce' | grep -vic 'noreply.*noreply' || true)
if [ "$BETROFFEN" = "0" ]; then echo "Keine betroffenen Commits. Nichts zu tun."; exit 0; fi
echo "Betroffene Commits: $BETROFFEN"

NEWN="$(git log --all --format='%an' | sort | uniq -c | sort -rn | head -1 | sed 's/^ *[0-9]* //')"
NEWE="$(git log --all --format='%ae' | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')"
case "$NEWE" in *noreply*) ;; *) echo "Die häufigste Identität ist keine Noreply-Adresse. Abbruch."; exit 1;; esac
export NEWN NEWE

refs() { git -C "$1" for-each-ref --format='%(refname)' refs/heads refs/tags | while read -r r; do
  echo "$r $(git -C "$1" rev-parse "$r") $(git -C "$1" rev-parse "$r^{tree}") $(git -C "$1" rev-list --count "$r")"; done; }
refs "$WORK/original.git" > "$WORK/vorher.txt"

FILTER_BRANCH_SQUELCH_WARNING=1 git filter-branch -f --env-filter '
case "$GIT_AUTHOR_EMAIL" in *noreply*) ;; *) GIT_AUTHOR_NAME="$NEWN"; GIT_AUTHOR_EMAIL="$NEWE";; esac
case "$GIT_COMMITTER_EMAIL" in *noreply*) ;; *) GIT_COMMITTER_NAME="$NEWN"; GIT_COMMITTER_EMAIL="$NEWE";; esac
' --tag-name-filter cat -- --all > /dev/null 2>&1

refs "$WORK/neu.git" > "$WORK/nachher.txt"

# Refs mit signierten Commits nicht überschreiben: filter-branch entfernt Signaturen.
signiert() { git -C "$WORK/original.git" rev-list "$1" | while read -r c; do
  git -C "$WORK/original.git" cat-file commit "$c" | sed '/^$/q' | grep -q '^gpgsig' && { echo ja; break; }; done; }

: > "$WORK/push.txt"
FEHLER=0
while read -r ref alt baum anzahl; do
  read -r _ neu nbaum nanzahl < <(grep "^$ref " "$WORK/nachher.txt")
  [ "$baum" = "$nbaum" ] && [ "$anzahl" = "$nanzahl" ] || { echo "Abweichung bei $ref"; FEHLER=1; }
  [ "$alt" = "$neu" ] && continue
  enthaelt=$(git -C "$WORK/original.git" log "$ref" --format='%ae %ce' | grep -vic 'noreply.*noreply' || true)
  if [ "$enthaelt" = "0" ] || [ "$(signiert "$ref")" = "ja" ]; then
    echo "Übersprungen: $ref"
    [ "$enthaelt" = "0" ] || { echo "  ACHTUNG: enthält betroffene Commits UND signierte Commits, bitte von Hand klären."; }
    continue
  fi
  echo "$ref $alt" >> "$WORK/push.txt"
done < "$WORK/vorher.txt"
[ "$FEHLER" = "0" ] || { echo "Prüfung fehlgeschlagen. Abbruch, nichts wurde gepusht."; exit 1; }

REST=0
while read -r ref _; do
  n=$(git log "$ref" --format='%ae%n%ce' | grep -vic noreply || true); REST=$((REST + n))
done < "$WORK/push.txt"
[ "$REST" = "0" ] || { echo "Es sind noch $REST Fremd-Adressen übrig. Abbruch."; exit 1; }

echo
echo "Geprüft: Dateibäume und Commit-Zahlen unverändert, keine Fremd-Adresse mehr."
echo "Zu überschreiben: $(wc -l < "$WORK/push.txt") Refs"
sed 's#refs/[a-z]*/##; s/ .*//' "$WORK/push.txt" | tr '\n' ' '; echo
echo
read -r -p "Jetzt per Force-Push überschreiben? (ja/nein) " ANTWORT
[ "$ANTWORT" = "ja" ] || { echo "Abgebrochen. Der umgeschriebene Stand liegt in $WORK/neu.git"; exit 0; }

ARGS=()
while read -r ref alt; do ARGS+=("--force-with-lease=$ref:$alt" "$ref:$ref"); done < "$WORK/push.txt"
git push origin "${ARGS[@]}"

echo
echo "Fertig. Sicherung des alten Stands: $WORK/sicherung-vor-umschreiben.bundle"
echo "Noch zu tun:"
echo "  1. Beim GitHub-Support die Bereinigung verwaister Commits und gecachter Ansichten beantragen;"
echo "     bis dahin sind die alten Commits über ihren Hash noch abrufbar."
echo "  2. Lokal einstellen: git config --global user.name / user.email auf die Noreply-Identität."
echo "  3. In GitHub unter Settings → Emails einschalten: 'Keep my email addresses private' und"
echo "     'Block command line pushes that expose my email'."
echo "  4. Vorhandene Klone neu holen oder frisch klonen."
