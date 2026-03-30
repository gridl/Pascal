{ (C) 1993-2016 by Dimitri Grinkevich }

{$M 2048, 0, 0}
program KeyboardInjectorV2;
uses Dos;

const
  { Мультиплексорный ID для INT 2Fh }
  TsrID = $E1;
  
  { Размер кольцевого буфера для приема данных из COM-порта }
  BufSize = 2048;

  { Таблицы подстановки для мгновенной конвертации полубайта (0..15) }
  AsciiTable: array[0..15] of Char = '0123456789ABCDEF';
  ScanTable:  array[0..15] of Byte = (
    $0B, $02, $03, $04, $05, $06, $07, $08, $09, $0A, { 0-9 }
    $1E, $30, $2E, $20, $12, $21                      { A-F }
  );
  CapsTable:  array[0..15] of Boolean = (
    False, False, False, False, False, False, False, False, False, False, { 0-9 }
    True,  True,  True,  True,  True,  True                               { A-F }
  );

var
  ComBase: Word;
  IrqNum: Byte;
  
  { Внутренний кольцевой буфер }
  IntBuf: array[0..BufSize-1] of Byte;
  BufHead, BufTail: Word;
  
  { Флаг занятости для предотвращения рекурсии в INT 1Ch / 28h }
  Busy: Boolean;

  OldIntVec: Pointer; { Вектор старого IRQ }
  OldInt1C:  Pointer; { Вектор старого Timer Tick }
  OldInt28:  Pointer; { Вектор старого DOS Idle }
  OldInt2F:  Pointer; { Вектор старого Multiplex }

{ ------------------- БЛОК НИЗКОУРОВНЕВЫХ ФУНКЦИЙ ------------------- }

function CallInt15(SC: Byte): Word;
begin
  inline(
    $8A/$46/<SC/    { mov al, [bp+<SC] }
    $F8/            { clc              }
    $B4/$4F/        { mov ah, 4Fh      }
    $CD/$15/        { int 15h          }
    $8A/$E0/        { mov ah, al       }
    $B0/$00/        { mov al, 0        }
    $73/$02/        { jnc +2           }
    $B0/$01/        { mov al, 1        }
    $86/$E0/        { xchg ah, al      }
  );
end;

procedure UpdateLEDs(Flags: Byte);
var
  LedState: Byte;
  Timeout: Word;
begin
  LedState := 0;
  if (Flags and $40) <> 0 then LedState := LedState or 4;
  if (Flags and $20) <> 0 then LedState := LedState or 2;
  if (Flags and $10) <> 0 then LedState := LedState or 1;

  Timeout := $FFFF;
  while ((Port[$64] and 2) <> 0) and (Timeout > 0) do Dec(Timeout);
  if Timeout = 0 then Exit;
  Port[$60] := $ED;

  Timeout := $FFFF;
  while ((Port[$64] and 2) <> 0) and (Timeout > 0) do Dec(Timeout);
  if Timeout = 0 then Exit;
  Port[$60] := LedState;
end;

procedure SetCapsLock(Enable: Boolean);
var Flags: Byte;
begin
  Flags := Mem[$0040:$0017];
  if Enable then Flags := Flags or $40 else Flags := Flags and not $40;
  if Flags <> Mem[$0040:$0017] then
  begin
    Mem[$0040:$0017] := Flags;
    UpdateLEDs(Flags);
  end;
end;

{ ------------------- СТАДИЯ 2: ОБРАБОТКА ДАННЫХ ------------------- }

procedure ProcessNibble(Nibble: Byte);
var
  Ascii: Char;
  ScanCode: Byte;
  Res: Word;
  Head, Tail, NextTail: Word;
begin
  Nibble := Nibble and $0F;
  
  { O(1) извлечение данных через таблицы подстановки }
  Ascii := AsciiTable[Nibble];
  ScanCode := ScanTable[Nibble];
  SetCapsLock(CapsTable[Nibble]);

  Res := CallInt15(ScanCode);
  if Hi(Res) = 1 then Exit; 
  ScanCode := Lo(Res);

  inline($FA); { CLI }
  Tail := MemW[$0040:$001C];
  NextTail := Tail + 2;
  if NextTail >= $003E then NextTail := $001E;
  Head := MemW[$0040:$001A];

  if NextTail <> Head then
  begin
    MemW[$0040:Tail] := (ScanCode shl 8) or Ord(Ascii);
    MemW[$0040:$001C] := NextTail;
  end;
  inline($FB); { STI }
end;

{ Вызывается из INT 1Ch и INT 28h }
procedure ProcessRingBuffer;
var 
  B, OrigCaps: Byte;
begin
  if Busy then Exit;
  Busy := True;
  
  { Разрешаем аппаратные прерывания, чтобы не блокировать COM-порт }
  inline($FB); { STI }
  
  while BufHead <> BufTail do
  begin
    B := IntBuf[BufHead];
    BufHead := (BufHead + 1) mod BufSize;
    
    OrigCaps := Mem[$0040:$0017] and $40;
    
    ProcessNibble(B shr 4);
    ProcessNibble(B and $0F);
    
    SetCapsLock(OrigCaps <> 0);
  end;
  
  Busy := False;
end;

{ ------------------- ОБРАБОТЧИКИ ПРЕРЫВАНИЙ ------------------- }

{ СТАДИЯ 1: Максимально быстрый IRQ UART. Только чтение в буфер }
procedure ComISR; interrupt;
var B: Byte;
begin
  inline($FA); { CLI }
  while (Port[ComBase + 5] and 1) <> 0 do
  begin
    B := Port[ComBase];
    IntBuf[BufTail] := B;
    BufTail := (BufTail + 1) mod BufSize;
  end;
  Port[$20] := $20; { EOI }
end;

{ Обработчик Timer Tick (18.2 раза в секунду) }
procedure Int1CHandler; interrupt;
begin
  ProcessRingBuffer;
  inline($9C / $FF / $1E / >OldInt1C); { PUSHF, CALL FAR [>OldInt1C] }
end;

{ Обработчик DOS Idle (вызывается DOS в моменты простоя консоли) }
procedure Int28Handler; interrupt;
begin
  ProcessRingBuffer;
  inline($9C / $FF / $1E / >OldInt28); { PUSHF, CALL FAR [>OldInt28] }
end;

{ Multiplex Interrupt для проверки установки (Стандарт DOS) }
procedure Int2FHandler(BP, ES, DS, DI, SI, DX, CX, BX, AX, IP, CS, Flags: Word); interrupt;
begin
  if AX = (TsrID shl 8) then { Проверка AH = $E1, AL = 00h }
  begin
    inline(
      $8B/$E5/     { mov sp, bp - сброс стека до параметров }
      $5D/         { pop bp }
      $07/         { pop es }
      $1F/         { pop ds }
      $5F/         { pop di }
      $5E/         { pop si }
      $5A/         { pop dx }
      $59/         { pop cx }
      $5B/         { pop bx }
      $58/         { pop ax }
      $B0/$FF/     { mov al, $FF - сигнал "Я установлен" }
      $CF/         { iret - прямой выход, минуя эпилог TP5 }
    );
  end 
  else 
  begin
    inline(
      $9C/                     { pushf }
      $FF/$1E/>OldInt2F        { call far [>OldInt2F] - передача по цепочке }
    );
  end;
end;

{ ------------------- ИНИЦИАЛИЗАЦИЯ ------------------- }

function IsInstalled: Boolean;
var Regs: Registers;
begin
  Regs.AX := TsrID shl 8; { AH = $E1, AL = $00 }
  Intr($2F, Regs);
  IsInstalled := (Regs.AL = $FF);
end;

procedure InitSystem;
begin
  Port[$21] := Port[$21] or (1 shl IrqNum);

  Port[ComBase + 3] := $80;
  Port[ComBase + 0] := 1;
  Port[ComBase + 1] := 0;
  Port[ComBase + 3] := $03;
  Port[ComBase + 2] := $C7;
  Port[ComBase + 1] := $01;
  Port[ComBase + 4] := $0B;

  { Перехват векторов }
  GetIntVec($1C, OldInt1C); SetIntVec($1C, @Int1CHandler);
  GetIntVec($28, OldInt28); SetIntVec($28, @Int28Handler);
  GetIntVec($2F, OldInt2F); SetIntVec($2F, @Int2FHandler);
  GetIntVec(IrqNum + 8, OldIntVec); SetIntVec(IrqNum + 8, @ComISR);

  Port[$21] := Port[$21] and not (1 shl IrqNum);
end;

var Param: String;
begin
  if ParamCount = 0 then
  begin
    WriteLn('Keyboard Injector V2 (Multiplex & RingBuffer)');
    WriteLn('Usage: KEYBINJV2.EXE /1 | /2');
    Halt(1);
  end;

  Param := ParamStr(1);
  if Param = '/1' then begin ComBase := $3F8; IrqNum := 4; end
  else if Param = '/2' then begin ComBase := $2F8; IrqNum := 3; end
  else Halt(1);

  if IsInstalled then
  begin
    WriteLn('Error: Keyboard Injector is already resident via INT 2Fh.');
    Halt(1);
  end;

  Busy := False;
  BufHead := 0;
  BufTail := 0;
  
  InitSystem;

  WriteLn('Keyboard Injector V2 installed (COM', Copy(Param, 2, 1), ').');
  WriteLn('Architecture: INT 1C/28h Idle Processing, INT 2Fh Check.');
  WriteLn('(C) 1993-2016 by Dimitri Grinkevich');
    
  Keep(0);
end.


