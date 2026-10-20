#!/usr/bin/env bats

load test_helper

setup() {
  setup_test_env
  # Create a team and two agents
  bash "$SCRIPTS/join.sh" testteam alice claude-code /tmp/project-a
  bash "$SCRIPTS/join.sh" testteam bob claude-code /tmp/project-b
}

teardown() {
  teardown_test_env
}

# --- send.sh ---

@test "send: delivers a message" {
  run bash "$SCRIPTS/send.sh" testteam alice bob "hello"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Sent to bob" ]]
}

@test "send: fails without required args" {
  run bash "$SCRIPTS/send.sh"
  [ "$status" -ne 0 ]
}

# --- inbox.sh ---

@test "inbox: shows no messages when empty" {
  run bash "$SCRIPTS/inbox.sh" testteam alice
  [ "$status" -eq 0 ]
  [[ "$output" =~ "No new messages" ]]
}

@test "inbox: shows received message" {
  bash "$SCRIPTS/send.sh" testteam alice bob "hello bob"
  run bash "$SCRIPTS/inbox.sh" testteam bob
  [ "$status" -eq 0 ]
  [[ "$output" =~ "hello bob" ]]
  [[ "$output" =~ "alice" ]]
}

@test "inbox: marks messages as read" {
  bash "$SCRIPTS/send.sh" testteam alice bob "read me"
  bash "$SCRIPTS/inbox.sh" testteam bob >/dev/null
  run bash "$SCRIPTS/inbox.sh" testteam bob
  [ "$status" -eq 0 ]
  [[ "$output" =~ "No new messages" ]]
}

@test "inbox: --quiet suppresses output when no messages" {
  run bash "$SCRIPTS/inbox.sh" testteam alice --quiet
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "inbox: --quiet shows output when messages exist" {
  bash "$SCRIPTS/send.sh" testteam bob alice "ping"
  run bash "$SCRIPTS/inbox.sh" testteam alice --quiet
  [ "$status" -eq 0 ]
  [[ "$output" =~ "ping" ]]
}

@test "inbox: handles multiline message body" {
  bash "$SCRIPTS/send.sh" testteam alice bob "line1
line2
line3"
  run bash "$SCRIPTS/inbox.sh" testteam bob
  [ "$status" -eq 0 ]
  [[ "$output" =~ "1 new message" ]]
  [[ "$output" =~ "alice" ]]
}

@test "inbox: a crafted agent arg cannot inject SQL to delete other messages (#87)" {
  bash "$SCRIPTS/send.sh" testteam alice bob "keepme"
  run bash "$SCRIPTS/inbox.sh" testteam "bob' AND read_at IS NULL; DELETE FROM messages; --"
  [ "$status" -eq 0 ]
  run bash "$SCRIPTS/inbox.sh" testteam bob
  [[ "$output" =~ "keepme" ]]
}

@test "inbox: an agent name containing a quote still receives its own messages (#87)" {
  bash "$SCRIPTS/join.sh" testteam "o'brien" claude-code /tmp/project-c
  bash "$SCRIPTS/send.sh" testteam alice "o'brien" "for quote"
  run bash "$SCRIPTS/inbox.sh" testteam "o'brien"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "for quote" ]]
}

@test "check-inbox: a team name containing a quote still delivers without a SQL error (#87)" {
  local project; project="$(mktemp -d)"
  bash "$SCRIPTS/join.sh" "te'am" carol claude-code "$project"
  bash "$SCRIPTS/send.sh" "te'am" alice carol "quoted team delivery"
  run bash -c "echo '{}' | bash '$SCRIPTS/check-inbox.sh' claude-code '$project'"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "quoted team delivery" ]]
}

@test "history: handles multiline message body" {
  bash "$SCRIPTS/send.sh" testteam alice bob "multi
line"
  run bash "$SCRIPTS/history.sh" testteam
  [ "$status" -eq 0 ]
  [[ "$output" =~ "alice" ]]
  [[ "$output" =~ "bob" ]]
}

# --- history.sh ---

@test "history: shows message history" {
  bash "$SCRIPTS/send.sh" testteam alice bob "msg1"
  bash "$SCRIPTS/send.sh" testteam bob alice "msg2"
  run bash "$SCRIPTS/history.sh" testteam
  [ "$status" -eq 0 ]
  [[ "$output" =~ "msg1" ]]
  [[ "$output" =~ "msg2" ]]
}

@test "history: filters by agent" {
  bash "$SCRIPTS/send.sh" testteam alice bob "for bob"
  bash "$SCRIPTS/send.sh" testteam bob alice "for alice"
  run bash "$SCRIPTS/history.sh" testteam alice
  [ "$status" -eq 0 ]
  [[ "$output" =~ "for" ]]
}

@test "history: respects limit" {
  bash "$SCRIPTS/send.sh" testteam alice bob "msg1"
  bash "$SCRIPTS/send.sh" testteam alice bob "msg2"
  bash "$SCRIPTS/send.sh" testteam alice bob "msg3"
  # limit=1 should return exactly 1 line with arrow
  run bash "$SCRIPTS/history.sh" testteam "" 1
  [ "$status" -eq 0 ]
  local count=$(echo "$output" | grep -c "→")
  [ "$count" -eq 1 ]
}

@test "history: shows no history message when empty" {
  run bash "$SCRIPTS/history.sh" testteam
  [ "$status" -eq 0 ]
  [[ "$output" =~ "No message history" ]]
}

@test "history: a non-numeric limit falls back to the default instead of injecting SQL (#87)" {
  bash "$SCRIPTS/send.sh" testteam alice bob "msg1"
  bash "$SCRIPTS/send.sh" testteam alice bob "msg2"
  run bash "$SCRIPTS/history.sh" testteam bob "1; DELETE FROM messages; --"
  [ "$status" -eq 0 ]
  run bash "$SCRIPTS/history.sh" testteam
  [[ "$output" =~ "msg1" ]]
  [[ "$output" =~ "msg2" ]]
}

@test "history: a team/agent name containing a quote does not break the query (#87)" {
  bash "$SCRIPTS/join.sh" testteam "o'brien" claude-code /tmp/project-c
  bash "$SCRIPTS/send.sh" testteam alice "o'brien" "for quote"
  run bash "$SCRIPTS/history.sh" testteam "o'brien"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "for quote" ]]
}

# --- search.sh ---

@test "search: finds messages containing the keyword" {
  bash "$SCRIPTS/send.sh" testteam alice bob "deploy finished"
  bash "$SCRIPTS/send.sh" testteam bob alice "lunch?"
  run bash "$SCRIPTS/search.sh" testteam deploy
  [ "$status" -eq 0 ]
  [[ "$output" =~ "deploy finished" ]]
  [[ ! "$output" =~ "lunch" ]]
}

@test "search: is case-insensitive" {
  bash "$SCRIPTS/send.sh" testteam alice bob "Deploy Done"
  run bash "$SCRIPTS/search.sh" testteam deploy
  [[ "$output" =~ "Deploy Done" ]]
}

@test "search: filters by agent" {
  bash "$SCRIPTS/send.sh" testteam alice bob "ping one"
  bash "$SCRIPTS/send.sh" testteam bob alice "ping two"
  run bash "$SCRIPTS/search.sh" testteam ping alice
  [[ "$output" =~ "ping one" ]]
  [[ "$output" =~ "ping two" ]]
  bash "$SCRIPTS/join.sh" testteam carol claude-code /tmp/project-c
  run bash "$SCRIPTS/search.sh" testteam ping carol
  [[ "$output" =~ "No messages matching" ]]
}

@test "search: treats % literally" {
  bash "$SCRIPTS/send.sh" testteam alice bob "100% done"
  bash "$SCRIPTS/send.sh" testteam alice bob "other text"
  run bash "$SCRIPTS/search.sh" testteam "%"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "100% done" ]]
  [[ ! "$output" =~ "other text" ]]
}

@test "search: treats _ literally" {
  bash "$SCRIPTS/send.sh" testteam alice bob "snake_case"
  bash "$SCRIPTS/send.sh" testteam alice bob "snakeXcase"
  run bash "$SCRIPTS/search.sh" testteam "snake_case"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "snake_case" ]]
  [[ ! "$output" =~ "snakeXcase" ]]
}

@test "search: treats backslash literally" {
  bash "$SCRIPTS/send.sh" testteam alice bob 'path C:\temp\x'
  bash "$SCRIPTS/send.sh" testteam alice bob "path C:temp"
  run bash "$SCRIPTS/search.sh" testteam 'C:\temp'
  [ "$status" -eq 0 ]
  [[ "$output" =~ 'C:\temp\x' ]]
  [[ ! "$output" =~ "path C:temp" ]]
}

@test "search: finds a body containing a single quote" {
  bash "$SCRIPTS/send.sh" testteam alice bob "it's working"
  bash "$SCRIPTS/send.sh" testteam alice bob "unrelated"
  run bash "$SCRIPTS/search.sh" testteam "it's"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "it's working" ]]
  [[ ! "$output" =~ "unrelated" ]]
}

@test "search: respects limit" {
  bash "$SCRIPTS/send.sh" testteam alice bob "hit 1"
  bash "$SCRIPTS/send.sh" testteam alice bob "hit 2"
  run bash "$SCRIPTS/search.sh" testteam hit "" 1
  [ "$(echo "$output" | grep -c "→")" -eq 1 ]
}

@test "search: requires a keyword" {
  run bash "$SCRIPTS/search.sh" testteam
  [ "$status" -ne 0 ]
}

@test "search: reports no match when nothing contains the keyword" {
  bash "$SCRIPTS/send.sh" testteam alice bob "hello"
  run bash "$SCRIPTS/search.sh" testteam zzz
  [ "$status" -eq 0 ]
  [[ "$output" =~ 'No messages matching "zzz"' ]]
  [[ ! "$output" =~ "hello" ]]
}

@test "search: reports an uninitialized DB without failing" {
  rm -f "$TEST_SKILL_DIR/db/messages.db"
  run bash "$SCRIPTS/search.sh" testteam hello
  [ "$status" -eq 0 ]
  [[ "$output" =~ "DB not initialized" ]]
}

@test "search: does not return messages from another team" {
  bash "$SCRIPTS/join.sh" otherteam alice claude-code /tmp/project-a
  bash "$SCRIPTS/join.sh" otherteam bob claude-code /tmp/project-b
  bash "$SCRIPTS/send.sh" testteam alice bob "shared word in testteam"
  bash "$SCRIPTS/send.sh" otherteam alice bob "shared word in otherteam"
  run bash "$SCRIPTS/search.sh" testteam shared
  [ "$status" -eq 0 ]
  [[ "$output" =~ "in testteam" ]]
  [[ ! "$output" =~ "in otherteam" ]]
}

@test "search: matches Japanese keywords" {
  bash "$SCRIPTS/send.sh" testteam alice bob "デプロイが完了しました"
  bash "$SCRIPTS/send.sh" testteam alice bob "別の話題"
  run bash "$SCRIPTS/search.sh" testteam "デプロイ"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "デプロイが完了しました" ]]
  [[ ! "$output" =~ "別の話題" ]]
}

@test "search: finds a keyword inside a multiline body" {
  bash "$SCRIPTS/send.sh" testteam alice bob "first line
second needle line"
  run bash "$SCRIPTS/search.sh" testteam needle
  [ "$status" -eq 0 ]
  [[ "$output" =~ "needle" ]]
}

@test "search: limit keeps the newest matches" {
  bash "$SCRIPTS/send.sh" testteam alice bob "hit old"
  sleep 1
  bash "$SCRIPTS/send.sh" testteam alice bob "hit new"
  run bash "$SCRIPTS/search.sh" testteam hit "" 1
  [ "$status" -eq 0 ]
  [[ "$output" =~ "hit new" ]]
  [[ ! "$output" =~ "hit old" ]]
}

@test "search: a non-numeric limit falls back to the default instead of injecting SQL" {
  bash "$SCRIPTS/send.sh" testteam alice bob "hit 1"
  run bash "$SCRIPTS/search.sh" testteam hit "" "1; DELETE FROM messages; --"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "hit 1" ]]
  run bash "$SCRIPTS/history.sh" testteam
  [[ "$output" =~ "hit 1" ]]
}

@test "search: a crafted keyword cannot inject SQL" {
  bash "$SCRIPTS/send.sh" testteam alice bob "keep me"
  run bash "$SCRIPTS/search.sh" testteam "x'; DELETE FROM messages; --"
  [ "$status" -eq 0 ]
  run bash "$SCRIPTS/history.sh" testteam
  [[ "$output" =~ "keep me" ]]
}

@test "search: a team name containing a quote does not break the query" {
  run bash "$SCRIPTS/search.sh" "te'am" hello
  [ "$status" -eq 0 ]
  [[ "$output" =~ "No messages matching" ]]
}
