var
  G: TGame;
  F: TextFile;
  Line, Ks, Tok, Cmd: string;
  Keys: array[0..511] of Byte;
  Steps, I, P, Code: Integer;
  Dir, Vx, Vy: Integer;
begin
  { Driver de teste (Pascal): o programa foi cortado antes do bloco principal. }
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  G := TGame.Create;
  AssignFile(F, ParamStr(1));
  Reset(F);
  while not EOF(F) do
  begin
    ReadLn(F, Line);
    P := Pos(' ', Line);
    Cmd := Copy(Line, 1, P - 1);
    Line := Copy(Line, P + 1, MaxInt);
    if Cmd = 'init' then  { saque fixo: direção e velocidade inteiras }
    begin
      P := Pos(' ', Line); Val(Copy(Line, 1, P - 1), Dir, Code); Line := Copy(Line, P + 1, MaxInt);
      P := Pos(' ', Line); Val(Copy(Line, 1, P - 1), Vx, Code); Line := Copy(Line, P + 1, MaxInt);
      Val(Line, Vy, Code);
      G.ResetBall(Dir);
      G.ServeTimer := 0;
      G.VX := Vx;
      G.VY := Vy;
      Continue;
    end;
    Val(Cmd, Steps, Code);
    Ks := Line + ',';
    FillChar(Keys, SizeOf(Keys), 0);
    if Ks <> '-,' then
      while Ks <> '' do
      begin
        P := Pos(',', Ks);
        Tok := Copy(Ks, 1, P - 1);
        Delete(Ks, 1, P);
        Keys[StrToInt(Tok)] := 1;
      end;
    for I := 1 to Steps do G.Update(@Keys[0], STEP);
  end;
  WriteLn(Format('left_y=%.4f right_y=%.4f bx=%.4f by=%.4f vx=%.4f vy=%.4f speed=%.4f score=%d-%d serve_timer=%.4f',
    [G.LeftY, G.RightY, G.BX, G.BY, G.VX, G.VY, G.Speed, G.ScoreL, G.ScoreR, G.ServeTimer]));
end.
