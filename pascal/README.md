# Pong — Object Pascal (Free Pascal)

Object Pascal (`{$mode objfpc}`) compilado com o FPC 3.2. O FPC não traz
units para SDL2, e o Fedora não empacota nenhuma, então `sdl2mini.pas` declara
só as ~20 funções e os records que o jogo usa (`TSDL_Rect`, `TSDL_AudioSpec`,
`TSDL_Event`). Todas as funções usam `cdecl; external 'SDL2'`, e o layout dos
records segue os headers C (`{$PACKRECORDS C}`).

O programa mascara as exceções de ponto flutuante (`SetExceptionMask`) antes
de iniciar a SDL, que é o procedimento padrão em FPC: drivers de vídeo e áudio
podem gerar exceções de FPU que o runtime do Pascal trataria como erro fatal.

## Dependências (Fedora)

```bash
sudo dnf install fpc sdl2-compat-devel
```

O `sdl2-compat-devel` fornece o symlink `libSDL2.so` usado pelo linker.

## Build

```bash
./build.sh
```

O script roda `fpc -O2 -Xs -FUbuild -obuild/pong pong.pas`. Para limpar,
use `./build.sh clean`.

## Execução

```bash
./build/pong
```
