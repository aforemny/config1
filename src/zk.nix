{
  # zk, patched to record every change a zk command makes to a notebook as a
  # jj change: after each command (and alias, and the LSP's `zk.new`), the
  # notebook files it touched -- all but the `.zk/notebook.db` index -- are
  # committed with the zk invocation as description, if the notebook is in a
  # jj workspace. Other pending changes (e.g. edits made outside zk) stay in
  # the working copy. Touched files are told by size and mtime, snapshotted
  # before the command. The check phase replaces zk's own (disabled in
  # nixpkgs) with one exercising exactly that jj interaction.
  overlays.zk = _: super: {
    zk = super.zk.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./zk-jj-commit.patch ];
      ldflags = old.ldflags ++ [
        "-X=github.com/zk-org/zk/internal/adapter/jj.Bin=${super.lib.getExe super.jujutsu}"
      ];
      doCheck = true;
      nativeCheckInputs = [
        super.jujutsu
        super.util-linux # script(1), for a tty
      ];
      checkPhase = ''
        runHook preCheck
        zk=$GOPATH/bin/zk
        export HOME=$TMPDIR/home JJ_CONFIG=$TMPDIR/jj.toml
        mkdir -p "$HOME"
        printf '[user]\nname = "zk"\nemail = "zk@example.org"\n' > "$JJ_CONFIG"

        fail() { echo "FAIL: $*" >&2; exit 1; }
        # Changes committed since the repo root, newest first, one per line.
        commits() { jj log --no-graph -r 'root()..@-' -T 'description.first_line() ++ "\n"'; }
        files() { jj diff --name-only -r "$1" | sort | tr '\n' ' '; }
        expect() { [ "$2" = "$3" ] || fail "$1: expected '$3', got '$2'"; }

        # A notebook at the root of a jj repo.
        mkdir "$TMPDIR/repo" && cd "$TMPDIR/repo"
        jj git init --quiet

        # `init` commits the new notebook, without the index.
        $zk init --no-input
        expect "init description" "$(commits)" "zk init --no-input"
        expect "init files" "$(files @-)" ".zk/config.toml .zk/templates/default.md "
        jj file list -r @- | grep -q notebook.db && fail "index committed"

        # A note written outside zk stays pending throughout: no command
        # touches it, so none may commit it.
        echo manual > manual.md
        pending() { jj diff --name-only | grep -qx manual.md || fail "$1: manual.md not pending"; }

        # A read-only command commits nothing.
        $zk list --quiet >/dev/null
        expect "list" "$(commits | wc -l)" 1
        pending list

        # `new` commits the note it creates, and only that.
        note=$($zk new --no-input --print-path --title Hello)
        expect "new description" "$(commits | head -1)" \
          "zk new --no-input --print-path --title Hello"
        expect "new files" "$(files @-)" "$(basename "$note") "
        pending new

        # `edit` commits what the editor changed.
        printf '#!/bin/sh\necho edited >> "$1"\n' > "$TMPDIR/editor"
        chmod +x "$TMPDIR/editor"
        # Under a pty, as interactively: zk reads the editor's stdin from
        # /dev/tty otherwise, which the sandbox lacks.
        ZK_EDITOR=$TMPDIR/editor script -qec "$zk edit --no-input $note" /dev/null >/dev/null
        expect "edit description" "$(commits | head -1)" "zk edit --no-input $note"
        jj file show -r @- "$note" | grep -qx edited || fail "edit not committed"
        expect "edit files" "$(files @-)" "$(basename "$note") "
        pending edit

        # An alias's changes are committed under the alias's invocation.
        sed -i '/^\[alias\]$/a scribble = "echo scribbled >> scribble.md"' .zk/config.toml
        jj commit --quiet -m config .zk/config.toml
        $zk scribble
        expect "alias description" "$(commits | head -1)" "zk scribble"
        expect "alias files" "$(files @-)" "scribble.md "

        # Only the notebook is committed: a notebook in a subdirectory of a
        # repo leaves the rest of the working copy alone.
        mkdir -p "$TMPDIR/outer/notes" && cd "$TMPDIR/outer"
        jj git init --quiet
        echo unrelated > unrelated.txt
        cd notes
        $zk init --no-input >/dev/null
        $zk new --no-input --print-path --title Sub >/dev/null
        case "$(files @-)" in *unrelated*) fail "committed outside the notebook" ;; esac
        jj diff --name-only | grep -qx ../unrelated.txt || fail "unrelated change lost"
        cd "$TMPDIR/repo"

        # The LSP's zk.new commits the note it creates.
        n=$(commits | wc -l)
        lsp() {
          printf 'Content-Length: %d\r\n\r\n%s' "''${#1}" "$1"
        }
        {
          lsp '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}'
          lsp '{"jsonrpc":"2.0","method":"initialized","params":{}}'
          lsp '{"jsonrpc":"2.0","id":2,"method":"workspace/executeCommand","params":{"command":"zk.new","arguments":["'"$PWD"'",{"title":"Lsp"}]}}'
          sleep 2
          lsp '{"jsonrpc":"2.0","id":3,"method":"shutdown"}'
          lsp '{"jsonrpc":"2.0","method":"exit"}'
        } | $zk lsp >/dev/null
        expect "lsp commits" "$(commits | wc -l)" $((n + 1))
        expect "lsp description" "$(commits | head -1)" "zk lsp zk.new"
        case "$(files @-)" in *manual.md*) fail "lsp committed manual.md" ;; esac
        pending lsp

        # Outside a jj workspace zk works as before.
        mkdir "$TMPDIR/plain" && cd "$TMPDIR/plain"
        $zk init --no-input >/dev/null
        $zk new --no-input --print-path --title Plain >/dev/null

        runHook postCheck
      '';
    });
  };

  homeManagerModules.zk =
    { osConfig, lib, ... }:
    lib.mkIf (osConfig.tags.workstation or false) {
      programs.zk = {
        enable = true;
        settings.notebook.dir = "~/s/notes";
      };
      home.activation.zkNotebook = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run mkdir -p "$HOME/s/notes/.zk"
      '';
    };
}
