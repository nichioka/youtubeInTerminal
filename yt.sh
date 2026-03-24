#!/usr/bin/env bash

set -euo pipefail

MPV_FORMAT_VIDEO="bestvideo[height<=1080]+bestaudio/best"
MPV_FORMAT_MUSIC="bestaudio/best"
MPV_FORMAT="$MPV_FORMAT_VIDEO"
SEARCH_LIMIT=20
SEARCH_MAX=100
QUEUE_MODE=0
MUSIC_MODE=0

show_usage() {
	echo "Uso: ./yt.sh [opções] [termo de busca]"
	echo
	echo "Opções:"
	echo "  -q, --queue   Seleciona múltiplos vídeos para fila"
	echo "  -m, --music   Modo música (prioriza áudio)"
	echo "  -h, --help    Mostra esta ajuda"
	echo
	echo "Também aceita link direto de vídeo ou playlist do YouTube."
	echo "Sem termo de busca, o script pede de forma interativa."
}

prompt_restart() {
	read -r -p "Buscar mais? [S/n]: " search_again
	search_again="${search_again:-s}"
	if [[ "$search_again" =~ ^([sS]|[sS][iI][mM])$ ]]; then
		exec "$0"
	fi
	echo "Fila finalizada."
}

play_video() {
	local video_id="$1"
	mpv "https://www.youtube.com/watch?v=${video_id}" --ytdl-format="$MPV_FORMAT" 2>/dev/null
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
		urls_str+="${queue_url}"$'\n'
	done <<< "$lines"

	if [[ -n "$urls_str" ]]; then
		printf '%s' "$urls_str" | mpv --playlist=- --ytdl-format="$MPV_FORMAT" 2>/dev/null || true
	fi
}

play_lines_as_queue() {
	local lines="$1"
	play_lines_in_mpv "$lines"
}

playlist_selection() {
	local playlist_lines="$1"
	local multi_mode="$2"
	local page=0
	local start=0
	local end=0
	local total=0
	local has_prev=0
	local has_more=0
	local selected_line=""
	local page_lines=""
	local page_input=""
	local selection=""
	local line_id=""
	local next_selected=0
	local prev_selected=0
	local done_selected=0

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

		if [[ "$multi_mode" == "1" ]]; then
			page_input="$page_lines"
			if ((has_prev == 1)); then
				page_input+=$'\nPagina anterior\t__PREV_PAGE__'
			fi
			if ((has_more == 1)); then
				page_input+=$'\nProxima pagina\t__NEXT_PAGE__'
			fi
			page_input+=$'\nFinalizar selecao\t__DONE__'

			selection="$(printf '%s\n' "$page_input" | fzf --height 40% --reverse --multi --prompt "YouTube > " --delimiter=$'\t' --with-nth=1 --header "Página $((page + 1)) | TAB marca | Navegue/Finalize")"

			[[ -z "$selection" ]] && break

			next_selected=0
			prev_selected=0
			done_selected=0
			while IFS= read -r selected_line; do
				[[ -z "$selected_line" ]] && continue
				line_id="$(printf '%s\n' "$selected_line" | cut -f2)"
				case "$line_id" in
					__PREV_PAGE__)
						prev_selected=1
						;;
					__NEXT_PAGE__)
						next_selected=1
						;;
					__DONE__)
						done_selected=1
						;;
					*)
						printf '%s\n' "$selected_line"
						;;
				esac
			done <<< "$selection"

			if ((done_selected == 1)); then
				break
			fi

			if ((prev_selected == 1 && has_prev == 1)); then
				page=$((page - 1))
				continue
			fi

			if ((next_selected == 1 && has_more == 1)); then
				page=$((page + 1))
				continue
			fi

			break
		else
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
		fi
	done
}

handle_url_input() {
	local input_url="$1"
	local mode="$2"
	local playlist_lines=""
	local direct_video_id=""
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
			playlist_selection "$playlist_lines" "$QUEUE_MODE"
			return 0
		fi
	fi

	echo "Link direto detectado: video." >&2
	direct_video_id="$(extract_video_id_from_url "$input_url" || true)"
	if [[ -z "$direct_video_id" ]]; then
		echo "Nao foi possivel extrair o video do link informado." >&2
		return 1
	fi

	echo "Tocando video direto..." >&2
	play_video "$direct_video_id"
	return 0
}

choose_from_search() {
	local search_term="$1"
	local multi_mode="$2"
	local page=0
	local start=0
	local end=0
	local total=0
	local has_prev=0
	local has_more=0
	local selected_line=""
	local page_lines=""
	local page_input=""
	local selection=""
	local line_id=""
	local next_selected=0
	local prev_selected=0
	local done_selected=0
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

		if [[ "$multi_mode" == "1" ]]; then
			page_input="$page_lines"
			if ((has_prev == 1)); then
				page_input+=$'\nPagina anterior\t__PREV_PAGE__'
			fi
			if ((has_more == 1)); then
				page_input+=$'\nProxima pagina\t__NEXT_PAGE__'
			fi
			page_input+=$'\nFinalizar selecao\t__DONE__'

			selection="$(printf '%s\n' "$page_input" | fzf --height 40% --reverse --multi --prompt "YouTube > " --delimiter=$'\t' --with-nth=1 --header "Página $((page + 1)) | TAB marca | Navegue/Finalize")"

			[[ -z "$selection" ]] && break

			next_selected=0
			prev_selected=0
			done_selected=0
			while IFS= read -r selected_line; do
				[[ -z "$selected_line" ]] && continue
				line_id="$(printf '%s\n' "$selected_line" | cut -f2)"
				case "$line_id" in
					__PREV_PAGE__)
						prev_selected=1
						;;
					__NEXT_PAGE__)
						next_selected=1
						;;
					__DONE__)
						done_selected=1
						;;
					*)
						printf '%s\n' "$selected_line"
						;;
				esac
			done <<< "$selection"

			if ((done_selected == 1)); then
				break
			fi

			if ((prev_selected == 1 && has_prev == 1)); then
				page=$((page - 1))
				continue
			fi

			if ((next_selected == 1 && has_more == 1)); then
				page=$((page + 1))
				continue
			fi

			break
		else
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
							playlist_lines_output="$(handle_url_input "$search_term" "change-term" || true)"
							if [[ -n "$playlist_lines_output" ]]; then
								mapfile -t all_results < <(printf '%s\n' "$playlist_lines_output")
							else
								all_results=()
							fi
						else
							handle_url_input "$search_term" "change-term" || true
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
		fi
	done
}

add_lines_to_queue() {
	local lines="$1"
	local line

	while IFS= read -r line; do
		[[ -z "$line" ]] && continue
		queue_lines+=("$line")
	done <<< "$lines"
}

while (($# > 0)); do
	case "$1" in
		-q|--queue)
			QUEUE_MODE=1
			shift
			;;
		-m|--music)
			MUSIC_MODE=1
			MPV_FORMAT="$MPV_FORMAT_MUSIC"
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
	url_result=0
	url_output="$(handle_url_input "$search_term" "main")" || url_result=$?
	
	if [[ "$url_result" == 99 ]]; then
		prompt_restart
		exit 0
	fi
	
	if [[ "$url_result" != 0 ]]; then
		exit 1
	fi
	
	if [[ -n "$url_output" ]]; then
		selected_lines="$url_output"
	else
		prompt_restart
		exit 0
	fi
else
	selected_lines="$(choose_from_search "$search_term" "$QUEUE_MODE")"
fi

if [[ -z "$selected_lines" ]]; then
	echo "Nenhum vídeo selecionado."
	exit 0
fi

declare -a queue_lines=()
add_lines_to_queue "$selected_lines"

first_selected_line="${queue_lines[0]:-}"
first_selected_id="$(printf '%s\n' "$first_selected_line" | cut -f2)"


if [[ -z "$first_selected_id" ]]; then
	echo "Nao foi possivel extrair o ID do video selecionado."
	exit 1
fi

echo "Fila iniciada (${#queue_lines[@]} video(s))."
play_lines_in_mpv "$selected_lines"

prompt_restart
