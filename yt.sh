#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HISTORY_FILE="$SCRIPT_DIR/play_history.log"

MPV_FORMAT_VIDEO="bestvideo[height<=1080]+bestaudio/best"
MPV_FORMAT_MUSIC="bestaudio/best"
MPV_FORMAT="$MPV_FORMAT_VIDEO"
SEARCH_LIMIT=20
SEARCH_MAX=100
QUEUE_MODE=0
URL_OUTPUT=""
RESTART_ARGS=()

show_usage() {
	echo "Uso: ./yt.sh [opções] [termo de busca]"
	echo
	echo "Opções:"
	echo "  -m, --music   Modo música (prioriza áudio)"
	echo "  -h, --help    Mostra esta ajuda"
	echo
	echo "Também aceita link direto de vídeo ou playlist do YouTube."
	echo "Sem termo de busca, o script pede de forma interativa."
}

prompt_restart() {
	read -r -p "Buscar mais? [S/n ou termo/url]: " search_again
	search_again="${search_again:-s}"
	if [[ "$search_again" =~ ^([sS]|[sS][iI][mM])$ ]]; then
		exec "$0" "${RESTART_ARGS[@]}"
	fi
	if [[ "$search_again" =~ ^([nN]|[nN][aA][oO])$ ]]; then
		echo "Fila finalizada."
		return
	fi
	exec "$0" "${RESTART_ARGS[@]}" "$search_again"
	echo "Fila finalizada."
}

run_mpv() {
	local -a mpv_args
	mpv_args=(--input-terminal=yes --no-fullscreen --ytdl-format="$MPV_FORMAT")

	if [[ "$MPV_FORMAT" == "$MPV_FORMAT_MUSIC" ]]; then
		mpv_args+=(--no-video --force-window=no --term-osd-bar --osd-level=1)
	fi
		if [[ "$MPV_FORMAT" != "$MPV_FORMAT_MUSIC" ]]; then
			mpv_args+=(--autofit=90%x90%)
		fi

	mpv "$@" "${mpv_args[@]}"
}

play_video() {
	local video_id="$1"
	local video_title="${2:-Video direto}"
	local video_url="https://www.youtube.com/watch?v=${video_id}"
	echo "Tocando: $video_title"
	log_playback "$video_title" "$video_url"
	run_mpv "https://www.youtube.com/watch?v=${video_id}"
}

log_playback() {
	local video_title="$1"
	local video_url="$2"
	local played_at=""
	played_at="$(date '+%Y-%m-%d %H:%M:%S')"
	printf '[%s] %s | %s\n' "$played_at" "$video_title" "$video_url" >> "$HISTORY_FILE"
}

is_youtube_url() {
	local input_value="$1"
	[[ "$input_value" =~ ^https?://(www\.)?(youtube\.com|youtu\.be)/ ]]
}

is_playlist_url() {
	local input_value="$1"
	[[ "$input_value" == *"list="* ]]
}

extract_video_id_from_url() {
	local video_url="$1"
	yt-dlp --no-warnings --no-playlist --get-id "$video_url" 2>/dev/null | head -n 1
}

get_playlist_lines() {
	local playlist_url="$1"
	yt-dlp "$playlist_url" --get-title --get-id --flat-playlist | paste - -
}

play_lines_in_mpv() {
	local lines="$1"
	local queue_line=""
	local queue_url=""
	local queue_title=""
	local queue_id=""
	local urls_str=""
	local playlist_file=""
	local first=1

	while IFS= read -r queue_line; do
		[[ -z "$queue_line" ]] && continue
		queue_title="$(printf '%s\n' "$queue_line" | cut -f1)"
		queue_id="$(printf '%s\n' "$queue_line" | cut -f2)"
		[[ -z "$queue_id" ]] && continue
		
		if ((first == 1)); then
			echo "Tocando: $queue_title"
			first=0
		fi
		
		queue_url="https://www.youtube.com/watch?v=${queue_id}"
		log_playback "$queue_title" "$queue_url"
		urls_str+="${queue_url}"$'\n'
	done <<< "$lines"

	if [[ -n "$urls_str" ]]; then
		playlist_file="$(mktemp)"
		printf '%s' "$urls_str" > "$playlist_file"
		run_mpv --playlist="$playlist_file" || true
		rm -f "$playlist_file"
	fi
}

playlist_selection() {
	local playlist_lines="$1"
	local page=0
	local start=0
	local end=0
	local total=0
	local has_prev=0
	local has_more=0
	local selected_line=""
	local page_lines=""
	local page_input=""
	local line_id=""

	mapfile -t all_results <<< "$playlist_lines"
	total=${#all_results[@]}
	if ((total == 0)); then
		echo "Playlist vazia." >&2
		return 0
	fi

	echo "$total video(s) na playlist." >&2

	while true; do
		start=$((page * SEARCH_LIMIT))
		if ((start >= total)); then
			break
		fi

		end=$((start + SEARCH_LIMIT))
		if ((end > total)); then
			end=$total
		fi

		has_prev=0
		if ((page > 0)); then
			has_prev=1
		fi

		has_more=0
		if ((end < total)); then
			has_more=1
		fi

		page_lines="$(printf '%s\n' "${all_results[@]:$start:$((end - start))}")"

		page_input="$page_lines"
		if ((has_prev == 1)); then
			page_input+=$'\nPagina anterior\t__PREV_PAGE__'
		fi
		if ((has_more == 1)); then
			page_input+=$'\nProxima pagina\t__NEXT_PAGE__'
		fi

		selected_line="$(printf '%s\n' "$page_input" | fzf --height 40% --reverse --prompt "YouTube > " --delimiter=$'\t' --with-nth=1 --header "Pagina $((page + 1)) | ENTER seleciona")"

		if [[ -z "$selected_line" ]]; then
			break
		fi

		line_id="$(printf '%s\n' "$selected_line" | cut -f2)"
		if [[ "$line_id" == "__PREV_PAGE__" && "$has_prev" == "1" ]]; then
			page=$((page - 1))
			continue
		fi
		if [[ "$line_id" == "__NEXT_PAGE__" && "$has_more" == "1" ]]; then
			page=$((page + 1))
			continue
		fi

		printf '%s\n' "$selected_line"
		break
	done
}

handle_url_input() {
	local input_url="$1"
	local playlist_lines=""
	local direct_video_id=""
	local direct_video_title=""
	local run_as_queue=""

	if is_playlist_url "$input_url"; then
		echo "Link direto detectado: playlist." >&2
		playlist_lines="$(get_playlist_lines "$input_url")"
		if [[ -z "$playlist_lines" ]]; then
			echo "Nao foi possivel carregar a playlist." >&2
			return 1
		fi

		read -r -p "Tocar como fila? [S/n]: " run_as_queue || true
		run_as_queue="${run_as_queue:-s}"
		if [[ "$run_as_queue" =~ ^([sS]|[sS][iI][mM])$ ]]; then
			play_lines_in_mpv "$playlist_lines"
			return 99
		else
			URL_OUTPUT="$(playlist_selection "$playlist_lines")"
			return 0
		fi
	fi

	echo "Link direto detectado: video." >&2
	direct_video_id="$(extract_video_id_from_url "$input_url" || true)"
	if [[ -z "$direct_video_id" ]]; then
		echo "Nao foi possivel extrair o video do link informado." >&2
		return 1
	fi
	direct_video_title="$(yt-dlp --no-warnings --no-playlist --get-title "$input_url" 2>/dev/null | head -n 1)"
	[[ -z "$direct_video_title" ]] && direct_video_title="Video direto"

	echo "Tocando video direto..." >&2
	if [[ "$MPV_FORMAT" == "$MPV_FORMAT_MUSIC" ]]; then
		play_lines_in_mpv "${direct_video_title}"$'\t'"${direct_video_id}"
	else
		play_video "$direct_video_id" "$direct_video_title"
	fi
	return 0
}

choose_from_search() {
	local search_term="$1"
	local page=0
	local start=0
	local end=0
	local total=0
	local has_prev=0
	local has_more=0
	local selected_line=""
	local page_lines=""
	local page_input=""
	local line_id=""
	local playlist_lines_output=""

	echo "Buscando resultados para: $search_term" >&2
	mapfile -t all_results < <(
		yt-dlp "ytsearch${SEARCH_MAX}:${search_term}" --get-title --get-id --flat-playlist | paste - -
	)

	total=${#all_results[@]}
	if ((total == 0)); then
		echo "Nenhum resultado encontrado." >&2
		return 0
	fi
	echo "$total resultado(s) carregado(s)." >&2

	while true; do
		start=$((page * SEARCH_LIMIT))
		if ((start >= total)); then
			break
		fi

		end=$((start + SEARCH_LIMIT))
		if ((end > total)); then
			end=$total
		fi

		has_prev=0
		if ((page > 0)); then
			has_prev=1
		fi

		has_more=0
		if ((end < total)); then
			has_more=1
		fi

		page_lines="$(printf '%s\n' "${all_results[@]:$start:$((end - start))}")"

		page_input="$page_lines"
		if ((has_prev == 1)); then
			page_input+=$'\nPagina anterior\t__PREV_PAGE__'
		fi
		if ((has_more == 1)); then
			page_input+=$'\nProxima pagina\t__NEXT_PAGE__'
		fi
		page_input+=$'\nMudar termo\t__CHANGE_TERM__'

		selected_line="$(printf '%s\n' "$page_input" | fzf --height 40% --reverse --prompt "YouTube > " --delimiter=$'\t' --with-nth=1 --header "Pagina $((page + 1)) | ENTER seleciona")"

		if [[ -z "$selected_line" ]]; then
			break
		fi

		line_id="$(printf '%s\n' "$selected_line" | cut -f2)"
		if [[ "$line_id" == "__PREV_PAGE__" && "$has_prev" == "1" ]]; then
			page=$((page - 1))
			continue
		fi
		if [[ "$line_id" == "__NEXT_PAGE__" && "$has_more" == "1" ]]; then
			page=$((page + 1))
			continue
		fi
		if [[ "$line_id" == "__CHANGE_TERM__" ]]; then
			read -r -p "Digite novo termo: " new_term
			if [[ -n "${new_term// }" ]]; then
				search_term="$new_term"
				page=0
				echo "Buscando: $search_term" >&2
				if is_youtube_url "$search_term"; then
					if is_playlist_url "$search_term"; then
						URL_OUTPUT=""
						handle_url_input "$search_term" || true
						playlist_lines_output="$URL_OUTPUT"
						if [[ -n "$playlist_lines_output" ]]; then
							mapfile -t all_results < <(printf '%s\n' "$playlist_lines_output")
						else
							all_results=()
						fi
					else
						handle_url_input "$search_term" || true
					fi
				else
					mapfile -t all_results < <(yt-dlp "ytsearch${SEARCH_MAX}:${search_term}" --get-title --get-id --flat-playlist | paste - -)
				fi
				total=${#all_results[@]}
				if ((total == 0)); then
					echo "Sem resultados." >&2
				fi
			fi
			continue
		fi

		printf '%s\n' "$selected_line"
		break
	done
}

while (($# > 0)); do
	case "$1" in
		-m|--music)
			MPV_FORMAT="$MPV_FORMAT_MUSIC"
			RESTART_ARGS+=(--music)
			shift
			;;
		-h|--help)
			show_usage
			exit 0
			;;
		--)
			shift
			break
			;;
		-*)
			echo "Opcao invalida: $1"
			show_usage
			exit 1
			;;
		*)
			break
			;;
	esac
done

if (($# == 0)); then
	read -r -p "Digite o termo de busca ou url: " search_term
else
	search_term="$*"
fi

if [[ -z "${search_term// }" ]]; then
	echo "Informe um termo de busca valido."
	exit 1
fi

if is_youtube_url "$search_term"; then
	URL_OUTPUT=""
	url_result=0
	handle_url_input "$search_term" || url_result=$?
	
	if [[ "$url_result" == 99 ]]; then
		prompt_restart
		exit 0
	fi
	
	if [[ "$url_result" != 0 ]]; then
		exit 1
	fi

	if [[ -n "$URL_OUTPUT" ]]; then
		selected_lines="$URL_OUTPUT"
	else
		prompt_restart
		exit 0
	fi
else
	selected_lines="$(choose_from_search "$search_term")"
fi

if [[ -z "$selected_lines" ]]; then
	echo "Nenhum vídeo selecionado."
	exit 0
fi

selected_count="$(printf '%s\n' "$selected_lines" | grep -c . || true)"
first_selected_line="$(printf '%s\n' "$selected_lines" | head -n 1)"
first_selected_id="$(printf '%s\n' "$first_selected_line" | cut -f2)"


if [[ -z "$first_selected_id" ]]; then
	echo "Nao foi possivel extrair o ID do video selecionado."
	exit 1
fi

echo "Fila iniciada (${selected_count} video(s))."
play_lines_in_mpv "$selected_lines"

prompt_restart
