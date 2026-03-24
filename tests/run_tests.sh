#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_PATH="$ROOT_DIR/yt.sh"

PASS_COUNT=0
FAIL_COUNT=0

print_ok() {
	echo "[OK] $1"
	PASS_COUNT=$((PASS_COUNT + 1))
}

print_fail() {
	echo "[ERRO] $1"
	FAIL_COUNT=$((FAIL_COUNT + 1))
}

assert_contains() {
	local text="$1"
	local expected="$2"
	local label="$3"
	if grep -Fq -- "$expected" <<< "$text"; then
		print_ok "$label"
	else
		print_fail "$label (esperado conter: $expected)"
	fi
}

assert_file_contains() {
	local file_path="$1"
	local expected="$2"
	local label="$3"
	if [[ -f "$file_path" ]] && grep -Fq "$expected" "$file_path"; then
		print_ok "$label"
	else
		print_fail "$label (arquivo sem conteúdo esperado: $expected)"
	fi
}

TEST_TMP_DIR="$(mktemp -d "$ROOT_DIR/.test_tmp.XXXXXX")"
MOCK_BIN_DIR="$TEST_TMP_DIR/mock_bin"
LOG_DIR="$TEST_TMP_DIR/logs"
mkdir -p "$MOCK_BIN_DIR" "$LOG_DIR"

cleanup() {
	rm -rf "$TEST_TMP_DIR"
}
trap cleanup EXIT

cat > "$MOCK_BIN_DIR/yt-dlp" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "$*" >> "$TEST_LOG_YTDLP"

args="$*"
if [[ "$args" == *"ytsearch"*"--get-title"*"--get-id"*"--flat-playlist"* ]]; then
	echo "Resultado 1"
	echo "vid001"
	echo "Resultado 2"
	echo "vid002"
	exit 0
fi

if [[ "$args" == *"--no-playlist --get-id"* ]]; then
	echo "vidurl001"
	exit 0
fi

if [[ "$args" == *"--no-playlist --get-title"* ]]; then
	echo "Titulo URL"
	exit 0
fi

if [[ "$args" == *"playlist"*"--get-title"*"--get-id"*"--flat-playlist"* ]]; then
	echo "Playlist 1"
	echo "pl001"
	echo "Playlist 2"
	echo "pl002"
	exit 0
fi

exit 0
EOF
chmod +x "$MOCK_BIN_DIR/yt-dlp"

cat > "$MOCK_BIN_DIR/fzf" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

input="$(cat)"
first_line="$(printf '%s\n' "$input" | head -n 1)"
printf '%s\n' "$first_line"
EOF
chmod +x "$MOCK_BIN_DIR/fzf"

cat > "$MOCK_BIN_DIR/mpv" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "$*" >> "$TEST_LOG_MPV"
exit 0
EOF
chmod +x "$MOCK_BIN_DIR/mpv"

export TEST_LOG_YTDLP="$LOG_DIR/yt-dlp.log"
export TEST_LOG_MPV="$LOG_DIR/mpv.log"
export PATH="$MOCK_BIN_DIR:$PATH"

if bash -n "$SCRIPT_PATH"; then
	print_ok "Sintaxe do script"
else
	print_fail "Sintaxe do script"
fi

help_output="$(bash "$SCRIPT_PATH" --help 2>&1 || true)"
assert_contains "$help_output" "Uso: ./yt.sh" "Ajuda exibe uso"
assert_contains "$help_output" "--queue" "Ajuda exibe opcao de fila"

url_output="$(printf 'n\n' | bash "$SCRIPT_PATH" "https://www.youtube.com/watch?v=abc" 2>&1 || true)"
assert_contains "$url_output" "Link direto detectado: video." "Fluxo URL detecta link"
assert_contains "$url_output" "Fila finalizada." "Fluxo URL oferece continuidade"
assert_file_contains "$TEST_LOG_MPV" "youtube.com/watch?v=vidurl001" "Fluxo URL toca vídeo no mpv"

rm -f "$TEST_LOG_MPV"
playlist_output="$(printf 's\nn\n' | bash "$SCRIPT_PATH" "https://www.youtube.com/playlist?list=PLabc" 2>&1 || true)"
assert_contains "$playlist_output" "Link direto detectado: playlist." "Fluxo playlist detecta link"

mpv_count="$(wc -l < "$TEST_LOG_MPV" 2>/dev/null || echo 0)"
if [[ "$mpv_count" == "1" ]]; then
	print_ok "Fluxo playlist em mpv único (1 chamada)"
else
	print_fail "Fluxo playlist em mpv único (esperado 1 chamada, recebido $mpv_count)"
fi

assert_file_contains "$TEST_LOG_MPV" "playlist=-" "Fluxo playlist usa modo playlist do mpv"

rm -f "$TEST_LOG_MPV"
interactive_output="$(printf 'lofi\nn\n' | bash "$SCRIPT_PATH" 2>&1 || true)"
assert_contains "$interactive_output" "resultado(s) carregado(s)." "Busca interativa carrega resultados"
assert_file_contains "$TEST_LOG_MPV" "playlist=-" "Busca interativa usa modo playlist do mpv"

if ((FAIL_COUNT > 0)); then
	echo
	echo "Resumo: $PASS_COUNT OK, $FAIL_COUNT falha(s)."
	exit 1
fi

echo
echo "Resumo: $PASS_COUNT OK, 0 falhas."
