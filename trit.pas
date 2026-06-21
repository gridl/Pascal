program TritrisDMA;

uses Crt;

{ ====================================================================== }
{ СТРУКТУРЫ ДАННЫХ                                                       }
{ ====================================================================== }

const
  BW = 10; { Ширина игрового стакана }
  BH = 20; { Высота игрового стакана }
  SX = 30; { Смещение поля по X      }
  SY = 3;  { Смещение поля по Y      }

type
  TPoint = record X, Y: Integer; end;
  TBlocks = array[1..3] of TPoint;
  
  TFig = record B: TBlocks; X, Y: Integer; C: Byte; end;

  TBoard = array[1..BW, 1..BH] of Byte;
  TState = (gsRun, gsOver);

var
  Board: TBoard;
  Fig: TFig;
  State: TState;
  Score, Spd: Integer;

{ ====================================================================== }
{ ХАКИ УРОВНЯ BIOS И ЖЕЛЕЗА (VRAM & BDA)                                 }
{ ====================================================================== }

procedure PutChar(X, Y: Integer; Ch: Char; Attr: Byte);
begin
  MemW[$B800: ((Y - 1) * 80 + (X - 1)) shl 1] := (Attr shl 8) or Ord(Ch);
end;

procedure PutStr(X, Y: Integer; S: String; Attr: Byte);
var I: Integer;
begin
  for I := 1 to Length(S) do PutChar(X + I - 1, Y, S[I], Attr);
end;

procedure ClearVRAM;
var I: Word;
begin
  for I := 0 to 1999 do MemW[$B800: I shl 1] := $0720;
end;

{ Прямое обнуление буфера клавиатуры через BIOS Data Area }
procedure FlushKbd;
begin
  { Приравниваем Head (0x1A) к Tail (0x1C), сбрасывая очередь }
  MemW[$0040:$001A] := MemW[$0040:$001C];
end;

{ ====================================================================== }
{ ГРАФИЧЕСКИЕ ПРИМИТИВЫ ИГРЫ                                             }
{ ====================================================================== }

procedure SetP(var P: TPoint; AX, AY: Integer);
begin P.X := AX; P.Y := AY; end;

procedure DrawB(X, Y: Integer; C: Byte);
var ScX, ScY: Integer;
begin
  if Y < 1 then Exit;
  ScX := SX + (X - 1) * 2; ScY := SY + Y - 1;
  PutChar(ScX, ScY, #219, C); PutChar(ScX + 1, ScY, #219, C);
end;

procedure EraseB(X, Y: Integer);
var ScX, ScY: Integer;
begin
  if Y < 1 then Exit;
  ScX := SX + (X - 1) * 2; ScY := SY + Y - 1;
  PutChar(ScX, ScY, ' ', $07); PutChar(ScX + 1, ScY, ' ', $07);
end;

procedure InitBoard;
var I, J: Integer;
begin
  for I := 1 to BW do for J := 1 to BH do Board[I, J] := 0;
end;

procedure DrawBorder;
var I: Integer;
begin
  for I := 1 to BH do begin
    PutChar(SX - 1, SY + I - 1, #186, LightGray);
    PutChar(SX + BW * 2, SY + I - 1, #186, LightGray);
  end;
  PutChar(SX - 1, SY + BH, #200, LightGray);
  for I := 1 to BW * 2 do PutChar(SX - 1 + I, SY + BH, #205, LightGray);
  PutChar(SX + BW * 2, SY + BH, #188, LightGray);
end;

procedure Redraw;
var X, Y: Integer;
begin
  for X := 1 to BW do
    for Y := 1 to BH do
      if Board[X, Y] <> 0 then DrawB(X, Y, Board[X,Y]) else EraseB(X, Y);
end;

{ ====================================================================== }
{ ЛОГИКА ФИГУР                                                           }
{ ====================================================================== }

procedure Spawn;
begin
  Fig.X := BW div 2; Fig.Y := 0;
  if Random(2) = 0 then begin
    SetP(Fig.B[1], -1, 0); SetP(Fig.B[2], 0, 0); SetP(Fig.B[3], 1, 0);
    Fig.C := LightCyan;
  end else begin
    SetP(Fig.B[1], 0, 0); SetP(Fig.B[2], 1, 0); SetP(Fig.B[3], 0, 1);
    Fig.C := LightBlue;
  end;
end;

procedure DrawFig(Erase: Boolean);
var I, WX, WY: Integer;
begin
  for I := 1 to 3 do begin
    WX := Fig.X + Fig.B[I].X; WY := Fig.Y + Fig.B[I].Y;
    if Erase then EraseB(WX, WY) else DrawB(WX, WY, Fig.C);
  end;
end;

function IsCol(F: TFig): Boolean;
var I, WX, WY: Integer; Col: Boolean;
begin
  Col := False;
  for I := 1 to 3 do begin
    WX := F.X + F.B[I].X; WY := F.Y + F.B[I].Y;
    if (WX < 1) or (WX > BW) or (WY > BH) then Col := True
    else if (WY > 0) and (Board[WX, WY] <> 0) then Col := True;
  end;
  IsCol := Col;
end;

{ ====================================================================== }
{ МУТАЦИИ СОСТОЯНИЯ                                                      }
{ ====================================================================== }

procedure LockFig;
var I, WX, WY: Integer;
begin
  for I := 1 to 3 do begin
    WX := Fig.X + Fig.B[I].X; WY := Fig.Y + Fig.B[I].Y;
    if WY > 0 then Board[WX, WY] := Fig.C;
  end;
end;

procedure ClearLines;
var X, Y, Y2, LC: Integer; Full: Boolean;
begin
  LC := 0; Y := BH;
  while Y > 0 do begin
    Full := True;
    for X := 1 to BW do if Board[X, Y] = 0 then Full := False;
    if Full then begin
      Inc(LC);
      for Y2 := Y downto 2 do
        for X := 1 to BW do Board[X, Y2] := Board[X, Y2 - 1];
      for X := 1 to BW do Board[X, 1] := 0;
    end else Dec(Y);
  end;
  if LC > 0 then begin Inc(Score, LC * 100); Redraw; end;
end;

procedure Rotate;
var Tmp: TFig; I, TX: Integer;
begin
  Tmp := Fig;
  for I := 1 to 3 do begin
    TX := Tmp.B[I].X; Tmp.B[I].X := -Tmp.B[I].Y; Tmp.B[I].Y := TX;
  end;
  if not IsCol(Tmp) then begin
    DrawFig(True); Fig := Tmp; DrawFig(False);
  end;
end;

procedure MoveFig(DX, DY: Integer; var Landed: Boolean);
var Tmp: TFig;
begin
  Landed := False; Tmp := Fig;
  Tmp.X := Tmp.X + DX; Tmp.Y := Tmp.Y + DY;
  if not IsCol(Tmp) then begin
    DrawFig(True); Fig := Tmp; DrawFig(False);
  end else if DY > 0 then Landed := True;
end;

{ ====================================================================== }
{ ГЛАВНЫЙ ЦИКЛ УПРАВЛЕНИЯ                                                }
{ ====================================================================== }

procedure Input;
var Ch: Char; Landed: Boolean;
begin
  { Забираем ВСЕ клавиши из буфера за этот кадр (убирает лаг) }
  while KeyPressed do begin
    Ch := ReadKey;
    if Ch = #0 then begin
      Ch := ReadKey;
      case Ch of
        #75: MoveFig(-1, 0, Landed);
        #77: MoveFig(1, 0, Landed);
        #72: Rotate;
        #80: MoveFig(0, 1, Landed);
      end;
    end else if Ch = #27 then State := gsOver;
  end;
end;

procedure Run;
var Landed: Boolean; SStr: String[10];
begin
  InitBoard; Score := 0; Spd := 200; State := gsRun;
  ClearVRAM; DrawBorder; Spawn;

  while State = gsRun do begin
    Str(Score, SStr);
    PutStr(5, 5, 'Score: ' + SStr + '    ', LightGray);

    Input;

    Delay(Spd);
    MoveFig(0, 1, Landed);
    
    if Landed then begin
      LockFig; 
      ClearLines; 
      
      { Уничтожаем все старые нажатия перед созданием новой фигуры }
      FlushKbd; 
      
      Spawn;
      if IsCol(Fig) then State := gsOver; 
    end;
  end;
end;

begin
  Randomize;
  Run;
  PutStr(SX + 2, SY + BH div 2, ' GAME OVER ', 140);
  GotoXY(1, 24);
end.