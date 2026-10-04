#!/usr/bin/env bats

setup() {
  SR="$BATS_TEST_DIRNAME/../bin/sync-rehearsal"
  R="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$R/docs" && git -C "$R" init -q && git -C "$R" config user.email t@t && git -C "$R" config user.name t
  printf 'line1\nline2\nline3\n' >"$R/README.md"
  echo old >"$R/app.rb"
  git -C "$R" add -A && git -C "$R" commit -qm old && git -C "$R" tag v1.0.0
  echo new >"$R/app.rb"; echo extra >"$R/other.rb"
  git -C "$R" add -A && git -C "$R" commit -qm new && git -C "$R" tag v1.1.0
  mkdir -p "$R/opskit"
  echo "kit" >"$R/opskit/tool.sh"
  printf '| Pinned release tag | v1.1.0 |\n' >"$R/docs/UPSTREAM_CHANGES.md"
  sed -i 's/^| Pinned release tag | v1.1.0 |$/| Pinned release tag | v1.1.0 |/' "$R/docs/UPSTREAM_CHANGES.md"
  git -C "$R" add -A && git -C "$R" commit -qm kit
}

@test "a clean sync: upstream changes elsewhere do not conflict with our paths" {
  run "$SR" v1.0.0 v1.1.0 --repo "$R"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK: v1.1.0 merges cleanly"* ]]
}

@test "the real branch and worktrees are untouched afterwards" {
  before="$(git -C "$R" rev-parse HEAD)"
  "$SR" v1.0.0 v1.1.0 --repo "$R" >/dev/null
  [ "$(git -C "$R" rev-parse HEAD)" = "$before" ]
  [ "$(git -C "$R" worktree list | wc -l)" -eq 1 ]
  [ -z "$(git -C "$R" status --porcelain)" ]
}

@test "a kit that edits an upstream file conflicts with an upstream change and is reported" {
  git -C "$R" tag -d v1.1.0 >/dev/null
  # rebuild: kit commit edits README.md line 2; upstream also edits it in the new release
  git -C "$R" reset -q --hard v1.0.0
  echo new >"$R/app.rb"; printf 'line1\nUPSTREAM\nline3\n' >"$R/README.md"
  git -C "$R" add -A && git -C "$R" commit -qm new && git -C "$R" tag v1.1.0
  printf 'line1\nOURS\nline3\n' >"$R/README.md"; mkdir -p "$R/opskit" "$R/docs"
  echo kit >"$R/opskit/tool.sh"; printf '| Pinned release tag | v1.1.0 |\n' >"$R/docs/UPSTREAM_CHANGES.md"
  git -C "$R" add -A && git -C "$R" commit -qm kit
  run "$SR" v1.0.0 v1.1.0 --repo "$R"
  [ "$status" -eq 1 ]
  [[ "$output" == *"CONFLICTS"* ]]
  [[ "$output" == *"README.md"* ]]
}

@test "an upstream patch that merges cleanly must be listed in the ledger" {
  # kit patches app.rb (an upstream file) in a place upstream did not change
  git -C "$R" tag -d v1.1.0 >/dev/null
  git -C "$R" reset -q --hard v1.0.0
  printf 'old\nmore\n' >"$R/big.rb"; git -C "$R" add -A && git -C "$R" commit -qm up2 && git -C "$R" tag v1.0.5
  git -C "$R" reset -q --hard v1.0.0
  printf 'a\nb\nc\nd\ne\nf\ng\n' >"$R/long.txt"; git -C "$R" add -A && git -C "$R" commit -qm base2 && git -C "$R" tag v1.0.9
  printf 'a\nb\nc\nd\ne\nf\nUPSTREAM\n' >"$R/long.txt"; git -C "$R" add -A && git -C "$R" commit -qm new2 && git -C "$R" tag v1.1.0
  printf 'OURS\nb\nc\nd\ne\nf\nUPSTREAM\n' >"$R/long.txt"
  mkdir -p "$R/opskit" "$R/docs"; echo kit >"$R/opskit/tool.sh"
  printf '| Pinned release tag | v1.1.0 |\n' >"$R/docs/UPSTREAM_CHANGES.md"
  git -C "$R" add -A && git -C "$R" commit -qm kit
  run "$SR" v1.0.9 v1.1.0 --repo "$R"
  [ "$status" -eq 1 ]
  [[ "$output" == *"NOT in the patch ledger"* ]]
  [[ "$output" == *"long.txt"* ]]
  printf '| 1 | today | long.txt | test | x | x | x | active |\n' >>"$R/docs/UPSTREAM_CHANGES.md"
  git -C "$R" add -A && git -C "$R" commit -qm ledger
  run "$SR" v1.0.9 v1.1.0 --repo "$R"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ledger-listed upstream patches"* ]]
}

@test "usage errors, bad tags and missing tags" {
  run "$SR" v1.0.0
  [ "$status" -eq 2 ]
  run "$SR" "v1.0.0;id" v1.1.0 --repo "$R"
  [ "$status" -eq 2 ]
  run "$SR" v1.0.0 v9.9.9 --repo "$R"
  [ "$status" -eq 2 ]
  [[ "$output" == *"git fetch upstream tag"* ]]
}
