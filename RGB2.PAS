Program RGB2;

{ (C) 1991-2018 By Dimitri Grinkevich }

{ Borland Turbo Pascal 3.X }

type
    rgb = 
    record
        r, g, b : byte;
    end;

var
    reg : array[0 .. 15] of byte ;   { color register table }

    pal : array[0 .. 63] of rgb ; {  EGA palette }
    
    regs : record case integer of { 80i86 BIOS CALL}
          1 : (ax,bx,cx,dx,bp,si,di,ds,es,flags : integer) ;
          2 : (al,ah,bl,bh,cl,ch,dl,dh : byte) ;
    end ;
    
    nn, rr, gg, bb, en, er, eg, eb : integer ;

{
AL = 07 read palette register (PS/2)
BL = palette register to read (0-15)
on return:
BH = value of palette register
}
procedure init ;
begin                          
    for nn:=0 to 15 do
    with regs do
    begin
        ax := $1007 ;
        bl := nn ;
        intr($10, regs) ;
        reg[nn] := bh ;
    end;
end;


{
AL = 15 read DAC color register (PS/2)
BX = color register to read
on return:
CH = green value
CL = blue value
DH = red value
}
procedure readrgb ;
begin
  for nn:= 0 to 63 do  
    with regs do
    begin
        ax := $1015 ;
        bx := nn ;
        intr($10, regs) ;
        pal[nn].r := dh ;
        pal[nn].g := ch ;
        pal[nn].b := cl ;
    end;
end;

{
AL = 10 set DAC color register
BX = color register to set
CH = green value
CL = blue value
DH = red value
}
procedure changergb(nn, rr, gg, bb : byte) ;
begin
    with regs do
    begin
        ax := $1010 ;
        bx := reg[nn mod 16] ;
        ch := gg mod 64 ;
        cl := bb mod 64 ;
        dh := rr mod 64 ;
        intr($10,regs) ;
    end ;
end ;

procedure show16;
begin
    for nn := 0 to 15 do begin
        textcolor(nn) ;
        write('°±²±°') ;
        textcolor(15) ;
        write(' Color #', nn:2, ' is mapped to EGA palette #', reg[nn]:2 
              , ' with r=', pal[reg[nn]].r
              , ' with g=', pal[reg[nn]].g
              , ' with b=', pal[reg[nn]].b
              ) ; 
        writeln('') ; 
   { readln ; }   
    end ;
    textcolor(15) ;
end;


procedure show64;
begin
    textcolor(15) ;
    for nn := 0 to 63 do begin
        write(' EGA #'
              , nn:2 
              , ' r', pal[nn].r:2
              , ' g', pal[nn].g:2
              , ' b', pal[nn].b:2
              ) ; 
    end ;
    writeln('') ;
end;


procedure help;
begin
    textcolor(15) ;
    writeln('(C) 1991-2018 by Dimitri Grinkevich') ;
    writeln('RGB palette changer for text mode, usage:') ;
    writeln('rgb2 color rvalue gvalue bvalue - for set new') ;
    writeln('     0..15 0..63  0..63  0..63') ;
    writeln('rgb2 rgb - for view current rgb palette') ;
    writeln('rgb2 ega - for view current ega registers') ;
end;

BEGIN
    clrscr ;
    init ;
    readrgb ;
    
    if paramcount = 1 then
    begin
        if paramstr(1) = 'rgb' then
        begin
            show16 ;
            exit ;
        end;
        
        if paramstr(1) = 'ega' then
        begin
            show64 ;
            exit ;
        end;
        
        help ;
        exit ;
    end;
    
    if paramcount=4 then { }
    begin
        val(paramstr(1), nn, en) ; 
        val(paramstr(2), rr, er) ;
        val(paramstr(3), gg, eg) ; 
        val(paramstr(4), bb, eb) ;
        if ((en=0) and (er=0) and (eg=0) and (eb=0))
        then
            changergb(nn, rr, gg, bb)
        else
            writeln('        ERROR IN PARAMETERS      ') ;
            help ;
            exit ;
    end;
    
    help ;
    
END.
