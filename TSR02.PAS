Program tsr02 ;

{ Copyright (C) 1992 By Dimitri Grinkevich }

{ Borland Turbo Pascal 5.x }

{ Resident program shows 2D random walking rotating symbol }
{ using direct access to text mode screen memory }
{ being called by user defined clock tick handler 1C }
{ automatically 18.2 times per second via BIOS hardware interrupt 08 }

{$M 1024, 0, 512}

uses dos, crt ;

const 
    show : array[0 .. 3] of char = ('³', '/', 'Ä', '\') ; {CP 437, 866}
    pause : integer = 32 ; { can be used for slow downing effective system cpu speed }

var 
    x_position, y_position : integer ;
    screen : array[0 .. 24, 0 .. 79, 0 .. 1] of char absolute $B800 : $0000 ;
    frame : integer ;
    old : char ;

procedure timer ; interrupt ;
begin
      x_position := (x_position + 81 - random(3)) mod 80 ;
      y_position := (y_position + 26 - random(3)) mod 25 ;
      frame := (frame + 1) mod 4 ;
      old := screen[y_position, x_position, 0] ;
      screen[y_position, x_position, 0] := show[frame] ;
      sound((x_position + y_position) * 64) ;
      delay(pause) ;
      screen[y_position, x_position, 0] := old ;
      nosound ;
end;

BEGIN
    x_position := 0 ;
    y_position := 0 ;
    setintvec($1C, addr(timer)) ;
    keep(0) ;
END .
