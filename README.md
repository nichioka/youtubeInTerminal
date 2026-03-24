# youtubeInTerminal

Busca vídeos do YouTube no terminal, permite selecionar com `fzf` e reproduz com `mpv`.

## Pré-requisitos

- `yt-dlp`
- `fzf`
- `mpv`

## Inicialização

Use o script de setup para instalar dependências e ajustar permissões:

```bash
./init.sh
```

## Uso

Depois do setup:

```bash
./yt.sh "termo de busca"
```

Também aceita link direto de vídeo:

```bash
./yt.sh "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
```

E link direto de playlist:

```bash
./yt.sh "https://www.youtube.com/playlist?list=PLxxxxxxxxxxxxxxxx"
```

Também funciona sem argumento (modo interativo):

```bash
./yt.sh
```

Modo fila (seleciona vários resultados na busca):

```bash
./yt.sh --queue "termo de busca"
```

Modo YouTube Music (prioriza áudio):

```bash
./yt.sh --music "termo de busca"
```

Combinação fila + música:

```bash
./yt.sh --queue --music "termo de busca"
```

Exemplo:

```bash
./yt.sh "lofi hip hop"
```

## Como funciona

1. Busca resultados no YouTube com `yt-dlp`.
2. Mostra no `fzf` com título completo.
3. Exibe 20 por página e inclui as opções `Pagina anterior` e `Proxima pagina`.
4. Permite montar fila (com `--queue`) e reproduz em sequência no `mpv`.
5. Com `--music`, usa formato focado em áudio.
6. Se receber URL de vídeo/playlist, toca direto sem abrir busca.

## Ajuda rápida

```bash
./yt.sh --help
```

Atalhos de argumentos:

- `-q` = `--queue`
- `-m` = `--music`
- `-h` = `--help`

## Testes

Para validar o comportamento principal do script com mocks locais:

```bash
./tests/run_tests.sh
```

O runner testa sintaxe, ajuda, fluxo por URL e fluxo interativo.
