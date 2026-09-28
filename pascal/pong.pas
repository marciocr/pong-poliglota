{ Pong em Object Pascal (Free Pascal) com SDL2. }
program pong;

{$mode objfpc}{$H+}
{ Sem isto, o FPC 3.2+ dá a cada constante real o menor tipo que representa
  seus literais: STEP = 1.0 / 120.0 seria calculado em Single (32 bits) e a
  física divergiria das outras linguagens, que usam Double. }
{$MINFPCONSTPREC 64}

uses
  Math, SysUtils, sdl2mini;

const
  W = 640;
  H = 480;
  PADDLE_W = 10;
  PADDLE_H = 60;
  PADDLE_MARGIN = 20;
  BALL = 10;
  PADDLE_SPEED = 400.0;
  BALL_SPEED = 300.0;
  BALL_MAX = 720.0;
  SPEEDUP = 1.07;
  MAX_ANGLE = Pi / 4;
  STEP = 1.0 / 120.0;
  SERVE_DELAY = 1.0;
  RATE = 44100;

  { Fonte 3x5 para os dígitos do placar. }
  DIGITS: array[0..9] of string[15] = (
    '111101101101111', '001001001001001', '111001111100111', '111001111001111',
    '101101111001001', '111100111001111', '111100111101111', '111001001001001',
    '111101111101111', '111101111001111');

type
  TSound = array of SmallInt;

  TGame = class
    LeftY, RightY: Double;
    BX, BY, VX, VY, Speed: Double;
    ServeTimer, ServeDir: Double;
    ScoreL, ScoreR: Integer;
    Audio: TSDL_AudioDeviceID;
    SndPaddle, SndWall, SndScore: TSound;
    constructor Create;
    procedure Play(const S: TSound);
    procedure ResetBall(Dir: Double);
    procedure Launch;
    procedure Bounce(Dir, PaddleY: Double);
    procedure Update(Keys: PByte; Dt: Double);
  end;

{ Onda quadrada mono S16: um "beep" de console Atari. }
function SquareWave(Freq, Ms: Integer): TSound;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, RATE * Ms div 1000);
  for I := 0 to High(Result) do
    if ((I * 2 * Freq) div RATE) mod 2 = 1 then
      Result[I] := 4000
    else
      Result[I] := -4000;
end;

function OverlapsY(BY, PY: Double): Boolean;
begin
  Result := (BY + BALL >= PY) and (BY <= PY + PADDLE_H);
end;

constructor TGame.Create;
begin
  LeftY := (H - PADDLE_H) / 2;
  RightY := (H - PADDLE_H) / 2;
  SndPaddle := SquareWave(460, 50);
  SndWall := SquareWave(230, 50);
  SndScore := SquareWave(490, 250);
end;

procedure TGame.Play(const S: TSound);
begin
  if Audio = 0 then Exit;
  SDL_ClearQueuedAudio(Audio);
  SDL_QueueAudio(Audio, @S[0], Length(S) * SizeOf(SmallInt));
end;

procedure TGame.ResetBall(Dir: Double);
begin
  BX := (W - BALL) / 2;
  BY := (H - BALL) / 2;
  VX := 0;
  VY := 0;
  Speed := BALL_SPEED;
  ServeDir := Dir;
  ServeTimer := SERVE_DELAY;
end;

procedure TGame.Launch;
var
  A: Double;
begin
  A := (Random * 2 - 1) * Pi / 6;
  VX := ServeDir * Speed * Cos(A);
  VY := Speed * Sin(A);
end;

procedure TGame.Bounce(Dir, PaddleY: Double);
var
  Rel, A: Double;
begin
  Speed := Min(Speed * SPEEDUP, BALL_MAX);
  Rel := ((BY + BALL / 2) - (PaddleY + PADDLE_H / 2)) / (PADDLE_H / 2);
  A := EnsureRange(Rel, -1.0, 1.0) * MAX_ANGLE;
  VX := Dir * Speed * Cos(A);
  VY := Speed * Sin(A);
  Play(SndPaddle);
end;

procedure TGame.Update(Keys: PByte; Dt: Double);
const
  LX = PADDLE_MARGIN;
  RX = W - PADDLE_MARGIN - PADDLE_W;
begin
  if Keys[SDL_SCANCODE_W] <> 0 then LeftY := LeftY - PADDLE_SPEED * Dt;
  if Keys[SDL_SCANCODE_S] <> 0 then LeftY := LeftY + PADDLE_SPEED * Dt;
  if Keys[SDL_SCANCODE_UP] <> 0 then RightY := RightY - PADDLE_SPEED * Dt;
  if Keys[SDL_SCANCODE_DOWN] <> 0 then RightY := RightY + PADDLE_SPEED * Dt;
  LeftY := EnsureRange(LeftY, 0.0, H - PADDLE_H);
  RightY := EnsureRange(RightY, 0.0, H - PADDLE_H);

  if ServeTimer > 0 then
  begin
    ServeTimer := ServeTimer - Dt;
    if ServeTimer <= 0 then Launch;
    Exit;
  end;

  BX := BX + VX * Dt;
  BY := BY + VY * Dt;

  if BY < 0 then
  begin
    BY := 0; VY := Abs(VY); Play(SndWall);
  end;
  if BY + BALL > H then
  begin
    BY := H - BALL; VY := -Abs(VY); Play(SndWall);
  end;

  if (VX < 0) and (BX <= LX + PADDLE_W) and (BX + BALL >= LX) and OverlapsY(BY, LeftY) then
  begin
    BX := LX + PADDLE_W;
    Bounce(1, LeftY);
  end;
  if (VX > 0) and (BX + BALL >= RX) and (BX <= RX + PADDLE_W) and OverlapsY(BY, RightY) then
  begin
    BX := RX - BALL;
    Bounce(-1, RightY);
  end;

  if BX + BALL < 0 then
  begin
    Inc(ScoreR); Play(SndScore); ResetBall(-1);
  end;
  if BX > W then
  begin
    Inc(ScoreL); Play(SndScore); ResetBall(1);
  end;
end;

procedure Fill(R: PSDL_Renderer; X, Y, W, H: LongInt);
var
  Rc: TSDL_Rect;
begin
  Rc.x := X; Rc.y := Y; Rc.w := W; Rc.h := H;
  SDL_RenderFillRect(R, @Rc);
end;

{ Desenha um número; AlignRight=True faz o número terminar em X. }
procedure DrawNumber(R: PSDL_Renderer; N, X, Y: Integer; AlignRight: Boolean);
const
  S = 8;
var
  Txt: string;
  G: string[15];
  C, I: Integer;
begin
  Txt := IntToStr(N);
  if AlignRight then
    X := X - (Length(Txt) * 3 * S + (Length(Txt) - 1) * S);
  for C := 1 to Length(Txt) do
  begin
    G := DIGITS[Ord(Txt[C]) - Ord('0')];
    for I := 0 to 14 do
      if G[I + 1] = '1' then
        Fill(R, X + (I mod 3) * S, Y + (I div 3) * S, S, S);
    X := X + 4 * S;
  end;
end;

procedure Render(R: PSDL_Renderer; G: TGame);
var
  Y: Integer;
begin
  SDL_SetRenderDrawColor(R, 0, 0, 0, 255);
  SDL_RenderClear(R);
  SDL_SetRenderDrawColor(R, 255, 255, 255, 255);
  Y := 6;
  while Y < H do
  begin
    Fill(R, W div 2 - 2, Y, 4, 12);
    Inc(Y, 24);
  end;
  DrawNumber(R, G.ScoreL, W div 2 - 40, 20, True);
  DrawNumber(R, G.ScoreR, W div 2 + 40, 20, False);
  Fill(R, PADDLE_MARGIN, Trunc(G.LeftY), PADDLE_W, PADDLE_H);
  Fill(R, W - PADDLE_MARGIN - PADDLE_W, Trunc(G.RightY), PADDLE_W, PADDLE_H);
  Fill(R, Trunc(G.BX), Trunc(G.BY), BALL, BALL);
  SDL_RenderPresent(R);
end;

var
  Win: PSDL_Window;
  Ren: PSDL_Renderer;
  Game: TGame;
  Want: TSDL_AudioSpec;
  Ev: TSDL_Event;
  Keys: PByte;
  Last, Cur: QWord;
  Acc: Double;
  Running: Boolean;
begin
  { Drivers de vídeo/áudio podem gerar exceções de ponto flutuante que o FPC
    trataria como erro fatal; mascará-las é o procedimento padrão com SDL. }
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  Randomize;

  if SDL_Init(SDL_INIT_VIDEO or SDL_INIT_AUDIO) <> 0 then
  begin
    WriteLn(StdErr, 'SDL_Init: ', SDL_GetError);
    Halt(1);
  end;
  Win := SDL_CreateWindow('Pong - Object Pascal', SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
    W, H, SDL_WINDOW_SHOWN);
  Ren := nil;
  if Win <> nil then
    Ren := SDL_CreateRenderer(Win, -1, SDL_RENDERER_ACCELERATED or SDL_RENDERER_PRESENTVSYNC);
  if Ren = nil then
  begin
    WriteLn(StdErr, 'janela/renderer: ', SDL_GetError);
    Halt(1);
  end;

  Game := TGame.Create;
  FillChar(Want, SizeOf(Want), 0);
  Want.freq := RATE;
  Want.format := AUDIO_S16LSB;
  Want.channels := 1;
  Want.samples := 1024;
  Game.Audio := SDL_OpenAudioDevice(nil, 0, @Want, nil, 0);
  if Game.Audio <> 0 then
    SDL_PauseAudioDevice(Game.Audio, 0)
  else
    WriteLn(StdErr, 'sem áudio: ', SDL_GetError);

  if Random(2) = 0 then Game.ResetBall(1) else Game.ResetBall(-1);

  Last := SDL_GetPerformanceCounter;
  Acc := 0;
  Running := True;
  while Running do
  begin
    while SDL_PollEvent(@Ev) <> 0 do
      if Ev.type_ = SDL_QUITEV then Running := False;
    Keys := SDL_GetKeyboardState(nil);
    if Keys[SDL_SCANCODE_ESCAPE] <> 0 then Running := False;

    Cur := SDL_GetPerformanceCounter;
    Acc := Acc + Min((Cur - Last) / SDL_GetPerformanceFrequency, 0.25);
    Last := Cur;
    while Acc >= STEP do
    begin
      Game.Update(Keys, STEP);
      Acc := Acc - STEP;
    end;
    Render(Ren, Game);
  end;

  if Game.Audio <> 0 then SDL_CloseAudioDevice(Game.Audio);
  Game.Free;
  SDL_DestroyRenderer(Ren);
  SDL_DestroyWindow(Win);
  SDL_Quit;
end.
