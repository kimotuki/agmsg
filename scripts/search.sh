#!/usr/bin/env bash
set -euo pipefail

# Usage: search.sh <team> <keyword> [agent_id] [limit]
# Searches past messages in a team whose body contains <keyword>
# (case-insensitive substring). If agent_id given, only that agent's
# messages (sent or received) are searched. Newest matches are kept, shown
# oldest first.

TEAM="${1:?Usage: search.sh <team> <keyword> [agent_id] [limit]}"
KEYWORD="${2:?Usage: search.sh <team> <keyword> [agent_id] [limit]}"
AGENT="${3:-}"
LIMIT="${4:-20}"
# Same guard as history.sh: never interpolate a non-numeric limit into SQL.
case "$LIMIT" in ''|*[!0-9]*) LIMIT=20 ;; esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/storage.sh"
DB="$(agmsg_db_path)"

if [ ! -f "$DB" ]; then
  echo "No messages (DB not initialized)"
  exit 0
fi

_agmsg_sqlesc() { printf %s "$1" | sed "s/'/''/g"; }
# Escape LIKE wildcards so the keyword is matched literally (ESCAPE '\').
_agmsg_likeesc() { printf %s "$1" | sed -e 's/\\/\\\\/g' -e 's/%/\\%/g' -e 's/_/\\_/g'; }

PATTERN="%$(_agmsg_likeesc "$KEYWORD")%"
WHERE="WHERE team='$(_agmsg_sqlesc "$TEAM")' AND body LIKE '$(_agmsg_sqlesc "$PATTERN")' ESCAPE '\\'"
if [ -n "$AGENT" ]; then
  A="$(_agmsg_sqlesc "$AGENT")"
  WHERE="$WHERE AND (from_agent='$A' OR to_agent='$A')"
fi

RESULT=$(agmsg_sqlite "$DB" "
  SELECT from_agent || char(31) || to_agent || char(31) || replace(replace(body, char(10), '\n'), char(9), '\t') || char(31) || created_at || char(31) || CASE WHEN read_at IS NULL THEN '●' ELSE '○' END
  FROM messages $WHERE ORDER BY created_at DESC LIMIT $LIMIT;
")

if [ -z "$RESULT" ]; then
  echo "No messages matching \"$KEYWORD\"."
  exit 0
fi

REVERSED=$(echo "$RESULT" | tail -r 2>/dev/null || echo "$RESULT" | tac 2>/dev/null || echo "$RESULT" | awk '{a[NR]=$0} END{for(i=NR;i>=1;i--)print a[i]}')
while IFS=$'\x1f' read -r from to body ts status; do
  echo "  $status [$ts] $from → $to: $body"
done <<< "$REVERSED"
