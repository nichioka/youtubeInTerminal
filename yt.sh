
yt-dlp "ytsearch20:$1" --get-title --get-id --flat-playlist | \
fzf --height 15% --reverse --header "Selecione o vídeo" | \
awk '{print $NF}' | xargs -I {} mpv "https://www.youtube.com/watch?v={}" --ytdl-format="bestvideo[height<=1080]+bestaudio/best"
