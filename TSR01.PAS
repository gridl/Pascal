Program tsr01 ;

{ Copyright (C) 1992 By Dimitri Grinkevich }

{ Borland Turbo Pascal 5.x }

{ Resident program shows rotating symbols on both upper corner }
{ using direct access to text mode screen memory }
{ being called by user defined clock tick handler 1C }
{ automatically 18.2 times per second via BIOS hardware interrupt 08 }

{$M 1024, 0, 512}

uses 
    dos, crt ;

const 
    show : array[0 .. 3] of char = ('³', '/', 'Ä', '\') ; {CP 437, 866}

var 
    screen : array[1 .. 25, 1 .. 80, 1 .. 2] of char absolute $B800 : $0000 ;
    frame : integer ;

procedure timer ; interrupt ;
begin
    frame := (frame + 1) mod 4 ;
    screen[01, 01, 1] := show[frame] ;
    screen[01, 80, 1] := show[frame] ;
end ;

BEGIN
  setintvec($1C, addr(timer)) ;
  keep(0) ;
END .
