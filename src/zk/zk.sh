mkdir -p "$ZK_STATE_DIR"
cd "$ZK_STATE_DIR"

while true; do
  if ! f=$(
    find . -iname '*.md' |
      fzf \
        --bind ctrl-e:accept-or-print-query \
        --ghost 'C-e to create from query. C-c to exit' \
        --preview='pandoc -t plain {}'
  ); then
    break
  fi
  mkdir -p "$(dirname "$f")"
  "${EDITOR:-vim}" "$f"
done
