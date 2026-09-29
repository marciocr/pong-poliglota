#!/usr/bin/env perl
# Pong em Perl com SDL2, chamando a libSDL2 diretamente via FFI::Platypus.
use strict;
use warnings;
use utf8;
use open qw(:std :encoding(UTF-8));

use FFI::CheckLib qw(find_lib);
use FFI::Platypus 2.00;
use FFI::Platypus::Buffer qw(scalar_to_buffer);
use FFI::Platypus::Memory qw(malloc free);
use List::Util qw(min max);
use POSIX qw(floor);

use constant {
    W => 640, H => 480,
    PADDLE_W => 10, PADDLE_H => 60, PADDLE_MARGIN => 20,
    BALL => 10,
    PADDLE_SPEED => 400.0,
    BALL_SPEED => 300.0,
    BALL_MAX => 720.0,
    SPEEDUP => 1.07,
    PI => 4 * atan2(1, 1),
    STEP => 1.0 / 120.0,
    SERVE_DELAY => 1.0,
    RATE => 44100,

    # Constantes dos headers da SDL2.
    SDL_INIT_AUDIO => 0x10, SDL_INIT_VIDEO => 0x20,
    SDL_WINDOWPOS_CENTERED => 0x2FFF0000,
    SDL_WINDOW_SHOWN => 0x04,
    SDL_RENDERER_ACCELERATED => 0x02, SDL_RENDERER_PRESENTVSYNC => 0x04,
    SDL_QUIT_EVENT => 0x100,
    SDL_SCANCODE_S => 22, SDL_SCANCODE_W => 26, SDL_SCANCODE_ESCAPE => 41,
    SDL_SCANCODE_DOWN => 81, SDL_SCANCODE_UP => 82,
    AUDIO_S16LSB => 0x8010,
};

# Fonte 3x5 para os dígitos do placar.
my @DIGITS = qw(
    111101101101111 001001001001001 111001111100111 111001111001111
    101101111001001 111100111001111 111100111101111 111001001001001
    111101111101111 111101111001111
);

# find_lib precisa do symlink libSDL2.so (pacote -devel); sem ele, usa o soname.
my ($libsdl) = find_lib(lib => 'SDL2');
my $ffi = FFI::Platypus->new(api => 2, lib => [$libsdl // 'libSDL2-2.0.so.0']);
$ffi->attach(SDL_Init                    => ['uint32'] => 'int');
$ffi->attach(SDL_Quit                    => [] => 'void');
$ffi->attach(SDL_GetError                => [] => 'string');
$ffi->attach(SDL_CreateWindow            => ['string', 'int', 'int', 'int', 'int', 'uint32'] => 'opaque');
$ffi->attach(SDL_DestroyWindow           => ['opaque'] => 'void');
$ffi->attach(SDL_CreateRenderer          => ['opaque', 'int', 'uint32'] => 'opaque');
$ffi->attach(SDL_DestroyRenderer         => ['opaque'] => 'void');
$ffi->attach(SDL_SetRenderDrawColor      => ['opaque', 'uint8', 'uint8', 'uint8', 'uint8'] => 'int');
$ffi->attach(SDL_RenderClear             => ['opaque'] => 'int');
$ffi->attach(SDL_RenderFillRect          => ['opaque', 'sint32[4]'] => 'int');  # SDL_Rect = 4 x int
$ffi->attach(SDL_RenderPresent           => ['opaque'] => 'void');
$ffi->attach(SDL_PollEvent               => ['opaque'] => 'int');
$ffi->attach(SDL_GetKeyboardState        => ['opaque'] => 'opaque');
$ffi->attach(SDL_GetPerformanceCounter   => [] => 'uint64');
$ffi->attach(SDL_GetPerformanceFrequency => [] => 'uint64');
$ffi->attach(SDL_OpenAudioDevice         => ['string', 'int', 'opaque', 'opaque', 'int'] => 'uint32');
$ffi->attach(SDL_PauseAudioDevice        => ['uint32', 'int'] => 'void');
$ffi->attach(SDL_QueueAudio              => ['uint32', 'opaque', 'uint32'] => 'int');
$ffi->attach(SDL_ClearQueuedAudio        => ['uint32'] => 'void');
$ffi->attach(SDL_CloseAudioDevice        => ['uint32'] => 'void');

# Onda quadrada mono S16 (bytes little-endian): um "beep" de console Atari.
sub square_wave {
    my ($freq, $ms) = @_;
    my $n = int(RATE * $ms / 1000);
    return pack 's<*', map { int($_ * 2 * $freq / RATE) % 2 ? 4000 : -4000 } 0 .. $n - 1;
}

my %snd = (
    paddle => square_wave(460, 50),
    wall   => square_wave(230, 50),
    score  => square_wave(490, 250),
);

my $audio = 0;
my %g = (
    left_y => (H - PADDLE_H) / 2, right_y => (H - PADDLE_H) / 2,
    bx => 0, by => 0, vx => 0, vy => 0, speed => BALL_SPEED,
    serve_timer => 0, serve_dir => 1,
    score_l => 0, score_r => 0,
);

sub play {
    my ($name) = @_;
    return unless $audio;
    SDL_ClearQueuedAudio($audio);
    my ($ptr, $len) = scalar_to_buffer($snd{$name});
    SDL_QueueAudio($audio, $ptr, $len);
}

sub clamp { my ($v, $lo, $hi) = @_; return max($lo, min($hi, $v)) }

sub reset_ball {
    my ($dir) = @_;
    $g{bx} = (W - BALL) / 2;
    $g{by} = (H - BALL) / 2;
    $g{vx} = $g{vy} = 0;
    $g{speed} = BALL_SPEED;
    $g{serve_dir} = $dir;
    $g{serve_timer} = SERVE_DELAY;
}

sub launch {
    my $a = (rand() * 2 - 1) * PI / 6;
    $g{vx} = $g{serve_dir} * $g{speed} * cos($a);
    $g{vy} = $g{speed} * sin($a);
}

sub bounce {
    my ($dir, $paddle_y) = @_;
    $g{speed} = min($g{speed} * SPEEDUP, BALL_MAX);
    my $rel = (($g{by} + BALL / 2) - ($paddle_y + PADDLE_H / 2)) / (PADDLE_H / 2);
    # Direção (1, t) normalizada, com t = tan do ângulo de saída (até 45° na borda da
    # raquete). Usa só sqrt, que o IEEE 754 exige arredondado corretamente: sin/cos
    # diferem no último bit entre as bibliotecas de cada linguagem, e num rali longo
    # essa diferença cresce até separar as versões.
    my $t = clamp($rel, -1, 1);
    my $len = sqrt(1 + $t * $t);
    $g{vx} = $dir * $g{speed} / $len;
    $g{vy} = $g{speed} * $t / $len;
    play('paddle');
}

sub overlaps_y { my ($by, $py) = @_; return $by + BALL >= $py && $by <= $py + PADDLE_H }

sub update {
    my ($keys, $dt) = @_;
    $g{left_y}  -= PADDLE_SPEED * $dt if $keys->[SDL_SCANCODE_W];
    $g{left_y}  += PADDLE_SPEED * $dt if $keys->[SDL_SCANCODE_S];
    $g{right_y} -= PADDLE_SPEED * $dt if $keys->[SDL_SCANCODE_UP];
    $g{right_y} += PADDLE_SPEED * $dt if $keys->[SDL_SCANCODE_DOWN];
    $g{left_y}  = clamp($g{left_y}, 0, H - PADDLE_H);
    $g{right_y} = clamp($g{right_y}, 0, H - PADDLE_H);

    if ($g{serve_timer} > 0) {
        $g{serve_timer} -= $dt;
        launch() if $g{serve_timer} <= 0;
        return;
    }

    $g{bx} += $g{vx} * $dt;
    $g{by} += $g{vy} * $dt;

    if ($g{by} < 0)        { $g{by} = 0;        $g{vy} = abs $g{vy};  play('wall') }
    if ($g{by} + BALL > H) { $g{by} = H - BALL; $g{vy} = -abs $g{vy}; play('wall') }

    my ($lx, $rx) = (PADDLE_MARGIN, W - PADDLE_MARGIN - PADDLE_W);
    if ($g{vx} < 0 && $g{bx} <= $lx + PADDLE_W && $g{bx} + BALL >= $lx && overlaps_y($g{by}, $g{left_y})) {
        $g{bx} = $lx + PADDLE_W;
        bounce(1, $g{left_y});
    }
    if ($g{vx} > 0 && $g{bx} + BALL >= $rx && $g{bx} <= $rx + PADDLE_W && overlaps_y($g{by}, $g{right_y})) {
        $g{bx} = $rx - BALL;
        bounce(-1, $g{right_y});
    }

    if ($g{bx} + BALL < 0) { $g{score_r}++; play('score'); reset_ball(-1) }
    if ($g{bx} > W)        { $g{score_l}++; play('score'); reset_ball(1) }
}

sub fill { my ($r, @rect) = @_; SDL_RenderFillRect($r, [map { floor($_) } @rect]) }

# Desenha um número; $align_right faz o número terminar em $x.
sub draw_number {
    my ($r, $n, $x, $y, $align_right) = @_;
    my $S = 8;
    my @chars = split //, "$n";
    $x -= @chars * 3 * $S + (@chars - 1) * $S if $align_right;
    for my $c (@chars) {
        my @bits = split //, $DIGITS[$c];
        for my $i (0 .. 14) {
            fill($r, $x + ($i % 3) * $S, $y + int($i / 3) * $S, $S, $S) if $bits[$i];
        }
        $x += 4 * $S;
    }
}

sub render {
    my ($r) = @_;
    SDL_SetRenderDrawColor($r, 0, 0, 0, 255);
    SDL_RenderClear($r);
    SDL_SetRenderDrawColor($r, 255, 255, 255, 255);
    for (my $y = 6; $y < H; $y += 24) { fill($r, W / 2 - 2, $y, 4, 12) }
    draw_number($r, $g{score_l}, W / 2 - 40, 20, 1);
    draw_number($r, $g{score_r}, W / 2 + 40, 20, 0);
    fill($r, PADDLE_MARGIN, $g{left_y}, PADDLE_W, PADDLE_H);
    fill($r, W - PADDLE_MARGIN - PADDLE_W, $g{right_y}, PADDLE_W, PADDLE_H);
    fill($r, $g{bx}, $g{by}, BALL, BALL);
    SDL_RenderPresent($r);
}

SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO) == 0 or die 'SDL_Init: ' . SDL_GetError() . "\n";
my $win = SDL_CreateWindow('Pong - Perl', SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, W, H, SDL_WINDOW_SHOWN);
my $ren = $win && SDL_CreateRenderer($win, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
$ren or die 'janela/renderer: ' . SDL_GetError() . "\n";

# SDL_AudioSpec: freq, format, channels, silence, samples, padding, size, callback, userdata.
my $want = pack 'l< S< C C S< S< L< Q< Q<', RATE, AUDIO_S16LSB, 1, 0, 1024, 0, 0, 0, 0;
my ($want_ptr) = scalar_to_buffer($want);
$audio = SDL_OpenAudioDevice(undef, 0, $want_ptr, undef, 0);
if ($audio) { SDL_PauseAudioDevice($audio, 0) }
else        { warn 'sem áudio: ' . SDL_GetError() . "\n" }

reset_ball(rand() < 0.5 ? 1 : -1);

my $event = malloc(56);  # sizeof(SDL_Event)
my $last = SDL_GetPerformanceCounter();
my $freq = SDL_GetPerformanceFrequency();
my $acc = 0;
my $running = 1;
while ($running) {
    while (SDL_PollEvent($event)) {
        $running = 0 if $ffi->cast('opaque' => 'uint32*', $event)->$* == SDL_QUIT_EVENT;
    }
    my $keys = $ffi->cast('opaque' => 'uint8[128]', SDL_GetKeyboardState(undef));
    $running = 0 if $keys->[SDL_SCANCODE_ESCAPE];

    my $now = SDL_GetPerformanceCounter();
    $acc += min(($now - $last) / $freq, 0.25);
    $last = $now;
    while ($acc >= STEP) {
        update($keys, STEP);
        $acc -= STEP;
    }
    render($ren);
}

free($event);
SDL_CloseAudioDevice($audio) if $audio;
SDL_DestroyRenderer($ren);
SDL_DestroyWindow($win);
SDL_Quit();
