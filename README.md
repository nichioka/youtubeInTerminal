# youtubeInTerminal

Busca e reproduz vídeos do YouTube no terminal com `fzf` + `mpv`, com suporte a fila, paginação e links diretos.

## Requisitos

- `yt-dlp`
- `fzf`
- `mpv`

## Instalação

Use o script de setup para instalar dependências e ajustar permissões:

```bash
./setup.sh
```

## Uso

Busca por termo:

```bash
./yt.sh "lofi hip hop"
```

Modo interativo (sem argumento):

```bash
./yt.sh
```

Ajuda:

```bash
./yt.sh --help
```

## Opções disponíveis

- `-m`, `--music`: prioriza áudio (`bestaudio`)
- `-h`, `--help`: exibe ajuda

No modo `--music`, o player roda sem vídeo e mantém controles/HUD no terminal.

Exemplo com música:

```bash
./yt.sh --music "chill mix"
```

## Links diretos

Vídeo:

```bash
./yt.sh "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
```

Playlist:

```bash
./yt.sh "https://www.youtube.com/playlist?list=PLxxxxxxxxxxxxxxxx"
```

Ao informar uma playlist, o script pergunta:

- `Tocar como fila? [S/n]`
- Enter (padrão `S`): toca tudo em uma única instância do `mpv`
- `n`: abre a seleção da própria playlist no `fzf` (com paginação)

## Fluxo da seleção

- Títulos completos no `fzf`
- Paginação de 20 resultados por página
- Navegação por `Pagina anterior` e `Proxima pagina`
- Seleção com `ENTER`
- Opção `Mudar termo` durante a escolha

## Histórico de reprodução

Cada vídeo tocado é registrado em `play_history.log` com:

- data e hora
- título
- URL

Exemplo:

```text
[2026-03-26 04:46:24] Resultado 1 | https://www.youtube.com/watch?v=vid001
```

## Controles durante reprodução (mpv)

Enquanto a música/vídeo estiver tocando, use:

- `9` / `0`: diminuir / aumentar volume
- `←` / `→`: voltar / adiantar 5s
- `↓` / `↑`: voltar / adiantar 1min
- `<` / `>`: faixa anterior / próxima faixa
- `Space`: pausar/continuar
- `q`: sair do player
