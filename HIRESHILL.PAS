unit HiresHill;

{ The hill and its backdrop, resampled to texture resolution.

  This is where the game's own data - Graffa, the camera, the row extents -
  is turned into finished pixels. It lives apart from SDLPort so that the
  platform layer can go back to being about windows, textures and input
  rather than about how a ski jumping hill is stored.

  Everything here is display only. LaskeLinjat, ProfiiliY, the profile
  checksum and every collision query keep reading the original 1024x512
  data; nothing in this unit is allowed to feed back into them. }

interface

const
  { The logical frame the game draws, and how much larger the texture is.
    Only 4 is correct at present - see MODERNIZATION.md - because the
    resampling weights, the font atlas and the rim thickness all assume it. }
  LogicalW = 320;
  LogicalH = 200;
  pixelScale = 4;
  TexW = LogicalW * pixelScale;
  TexH = LogicalH * pixelScale;

type
  { r, g, b per palette entry, already at 0..255 }
  THiPalette = array[0..255, 0..2] of byte;
  { how the destination texture packs a pixel }
  THiFormat = record
    Rshift, Gshift, Bshift : byte;
    Rmask, Gmask, Bmask, Amask : UInt32;
  end;

procedure Invalidate;
function  BackdropReady : boolean;
function  ForegroundReady : boolean;

procedure BuildBackdrop(const pal : THiPalette; const fmt : THiFormat);
procedure BuildForeground(const pal : THiPalette; const fmt : THiFormat);

{ Composite the resampled layers into a locked texture, putting back anything
  the game drew over the frame since Tulosta ran. }
procedure Compose(pixels : Pointer; pitch : LongInt;
                  src : Pointer; srcPitch : LongInt;
                  wantBack, wantFront : boolean;
                  const fmt : THiFormat);

implementation

uses Maki;

const
  { The backdrop as stored in Graffa, and its high-resolution counterpart. }
  backW = 1024;
  backH = 400;
  hiBackW = backW * pixelScale;
  hiBackH = backH * pixelScale;
  { The hill itself, which is Graffa's first page. }
  frontW = 1024;
  frontH = 512;
  hiFrontW = frontW * pixelScale;
  hiFrontH = frontH * pixelScale;
  { Row extents differing by more than this between neighbouring rows are a
    real feature of the hill - the takeoff lip, the tower - and are left as
    drawn. Anything gentler is a smooth curve that 1024 columns could not
    represent, and is reconstructed. }
  edgeSmoothLimit = 4;
  edgeFixed = 256;   { boundary positions are kept in 1/256 hi-res pixels }
  { The hill is drawn with a dark rim along its top edge, two or three pixels
    wide. Upscaled it is a staircase four times as coarse, so it is stripped
    out of the resample and redrawn along the reconstructed boundary. }
  rimSource = 4;
  rimHi = 5;

type
  TPixelRow = array[0..TexW-1] of UInt32;
  PPixelRow = ^TPixelRow;
  TWideRow = array[0..hiFrontW-1] of UInt32;
  PWideRow = ^TWideRow;

var
  hiBack : array of UInt32;
  hiBackReady : boolean;
  hiFront : array of UInt32;
  hiEdge : array of LongInt;
  hiFrontReady : boolean;
  hiRim : UInt32;

procedure Invalidate;
begin
  hiBackReady := false;
  hiFrontReady := false;
end;

function BackdropReady : boolean;
begin
  BackdropReady := hiBackReady;
end;

function ForegroundReady : boolean;
begin
  ForegroundReady := hiFrontReady;
end;

{ Resample the backdrop to pixelScale resolution, once per hill.

  The source is 8-bit palette indices, which cannot be interpolated - a value
  half way between index 40 and index 90 means nothing - so each sample is
  turned into colour first and the interpolation is done on the colours. The
  result is therefore stored as finished pixels rather than indices, which is
  fine because the palette range the backdrop uses (64..214) is only ever
  modified at hill load, by SavytaPaletti. }
procedure BuildBackdrop(const pal : THiPalette; const fmt : THiFormat);

var pr, pg, pb : array[0..255] of LongInt;
    unusedfmt : LongInt;
    i, hx, hy, x0, x1, y0, y1, fx, fy : LongInt;
    base : LongInt;
    c00, c01, c10, c11, top, bot : LongInt;
    r, g, b : LongInt;
    weights : array[0..pixelScale-1] of LongInt;
begin
  if (Length(Maki.Graffa) < Maki.Alue + backW * backH) then exit;

  if (Length(hiBack) <> hiBackW * hiBackH) then
    SetLength(hiBack, hiBackW * hiBackH);

  for i := 0 to 255 do
    begin
      pr[i] := pal[i,0];
      pg[i] := pal[i,1];
      pb[i] := pal[i,2];
    end;

  { Sub-pixel offsets, in eighths, of the pixelScale samples that fall inside
    one source pixel: 5/8, 7/8, 1/8, 3/8 with the source index stepping. }
  for i := 0 to pixelScale-1 do
    weights[i] := ((i + pixelScale - 2) mod pixelScale) * 2 + 1;

  base := Maki.Alue;

  for hy := 0 to hiBackH - 1 do
    begin
      y0 := (hy - 2) div pixelScale;
      if (hy < 2) then y0 := -1;
      fy := weights[hy mod pixelScale];
      y1 := y0 + 1;
      if (y0 < 0) then y0 := 0;
      if (y1 > backH-1) then y1 := backH-1;
      if (y0 > backH-1) then y0 := backH-1;

      for hx := 0 to hiBackW - 1 do
        begin
          x0 := (hx - 2) div pixelScale;
          if (hx < 2) then x0 := -1;
          fx := weights[hx mod pixelScale];
          x1 := x0 + 1;
          if (x0 < 0) then x0 := 0;
          if (x1 > backW-1) then x1 := backW-1;
          if (x0 > backW-1) then x0 := backW-1;

          c00 := Maki.Graffa[base + y0*backW + x0];
          c10 := Maki.Graffa[base + y0*backW + x1];
          c01 := Maki.Graffa[base + y1*backW + x0];
          c11 := Maki.Graffa[base + y1*backW + x1];

          top := pr[c00]*(8-fx) + pr[c10]*fx;
          bot := pr[c01]*(8-fx) + pr[c11]*fx;
          r   := (top*(8-fy) + bot*fy) div 64;

          top := pg[c00]*(8-fx) + pg[c10]*fx;
          bot := pg[c01]*(8-fx) + pg[c11]*fx;
          g   := (top*(8-fy) + bot*fy) div 64;

          top := pb[c00]*(8-fx) + pb[c10]*fx;
          bot := pb[c01]*(8-fx) + pb[c11]*fx;
          b   := (top*(8-fy) + bot*fy) div 64;

          { Pack using the surface's own channel layout rather than assuming
            one; the expansion path copies these pixels verbatim, so the two
            must agree exactly. }
          hiBack[hy*hiBackW + hx] :=
            (UInt32(r) shl fmt.Rshift) or
            (UInt32(g) shl fmt.Gshift) or
            (UInt32(b) shl fmt.Bshift) or fmt.Amask;
        end;
    end;

  hiBackReady := true;
end;

{ Resample the hill to texture resolution, and rebuild its silhouette.

  Two different jobs. The interior is resampled the same way as the backdrop,
  which removes the blockiness but adds nothing that was not there. The
  silhouette is different: KopioiMaki does not test each pixel for
  transparency, it uses LinjanPituus - the rightmost solid column of each row -
  so the edge is stored as 512 numbers rather than as pixels. Those numbers can
  be interpolated, which recovers a smooth curve the 1024-column grid could not
  hold. That is reconstruction rather than invention, and it is the only part
  of this that genuinely gains detail.

  Steps larger than edgeSmoothLimit are left alone; they are the takeoff lip
  and the tower, and rounding them off would deform the hill. }
procedure BuildForeground(const pal : THiPalette; const fmt : THiFormat);

var pr, pg, pb : array[0..255] of LongInt;
    unusedfmt : LongInt;
    filled : array of byte;
    ext : array[0..frontH-1] of LongInt;
    i, x, y, hx, hy, x0, x1, y0, y1, fx, fy : LongInt;
    c00, c01, c10, c11, top, bot, r, g, b : LongInt;
    weights : array[0..pixelScale-1] of LongInt;
    lastSolid, a, bnd, step, rimIx : LongInt;
    rimSeen : array[0..255] of LongInt;
begin
  if (Length(Maki.Graffa) < frontW * frontH) then exit;

  if (Length(hiFront) <> hiFrontW * hiFrontH) then
    SetLength(hiFront, hiFrontW * hiFrontH);
  if (Length(hiEdge) <> hiFrontH) then SetLength(hiEdge, hiFrontH);
  SetLength(filled, frontW * frontH);

  for i := 0 to 255 do
    begin
      pr[i] := pal[i,0]; pg[i] := pal[i,1]; pb[i] := pal[i,2];
      rimSeen[i] := 0;
    end;
  for i := 0 to pixelScale-1 do
    weights[i] := ((i + pixelScale - 2) mod pixelScale) * 2 + 1;

  { Row extents, and a copy of the hill with the transparent margin filled by
    the last solid colour of its row, so that resampling near the silhouette
    does not drag the void inwards. }
  for y := 0 to frontH-1 do
    begin
      lastSolid := 0;
      ext[y] := 0;
      for x := 0 to frontW-1 do
        begin
          a := Maki.Graffa[y*frontW + x];
          if (a <> 0) then begin lastSolid := a; ext[y] := x+1; end;
          filled[y*frontW + x] := lastSolid;
        end;

      { Strip the rim: walk back from the edge over pixels matching the
        outermost colour, then flood that row's tail with what lies inside. }
      if (ext[y] > rimSource + 1) then
        begin
          rimIx := filled[y*frontW + ext[y] - 1];
          x := ext[y] - 1;
          i := 0;
          while (i < rimSource) and (x > 0) and
                (filled[y*frontW + x] = rimIx) do
            begin dec(x); inc(i); end;
          a := filled[y*frontW + x];
          for x := x+1 to frontW-1 do filled[y*frontW + x] := a;
          rimSeen[rimIx] := rimSeen[rimIx] + 1;
        end;
    end;

  { the rim colour is whichever index bordered the most rows }
  a := 0; lastSolid := 0;
  for i := 0 to 255 do
    if (rimSeen[i] > a) then begin a := rimSeen[i]; lastSolid := i; end;
  hiRim := (UInt32(pal[lastSolid,0]) shl fmt.Rshift) or
           (UInt32(pal[lastSolid,1]) shl fmt.Gshift) or
           (UInt32(pal[lastSolid,2]) shl fmt.Bshift) or fmt.Amask;

  { Silhouette: one fractional boundary per texture row. }
  for hy := 0 to hiFrontH-1 do
    begin
      y0 := hy div pixelScale;
      y1 := y0 + 1;
      if (y1 > frontH-1) then y1 := frontH-1;
      step := ext[y1] - ext[y0];
      if (ext[y0] = 0) or (ext[y1] = 0) or (abs(step) > edgeSmoothLimit) then
        bnd := ext[y0] * pixelScale * edgeFixed
      else
        bnd := (ext[y0] * pixelScale * edgeFixed) +
               ((step * pixelScale * edgeFixed * (hy mod pixelScale)) div pixelScale);
      hiEdge[hy] := bnd;
    end;

  { Interior. }
  for hy := 0 to hiFrontH-1 do
    begin
      y0 := (hy - 2) div pixelScale;
      if (hy < 2) then y0 := -1;
      fy := weights[hy mod pixelScale];
      y1 := y0 + 1;
      if (y0 < 0) then y0 := 0;
      if (y1 > frontH-1) then y1 := frontH-1;
      if (y0 > frontH-1) then y0 := frontH-1;

      for hx := 0 to hiFrontW-1 do
        begin
          x0 := (hx - 2) div pixelScale;
          if (hx < 2) then x0 := -1;
          fx := weights[hx mod pixelScale];
          x1 := x0 + 1;
          if (x0 < 0) then x0 := 0;
          if (x1 > frontW-1) then x1 := frontW-1;
          if (x0 > frontW-1) then x0 := frontW-1;

          c00 := filled[y0*frontW + x0]; c10 := filled[y0*frontW + x1];
          c01 := filled[y1*frontW + x0]; c11 := filled[y1*frontW + x1];

          top := pr[c00]*(8-fx) + pr[c10]*fx;
          bot := pr[c01]*(8-fx) + pr[c11]*fx;
          r := (top*(8-fy) + bot*fy) div 64;
          top := pg[c00]*(8-fx) + pg[c10]*fx;
          bot := pg[c01]*(8-fx) + pg[c11]*fx;
          g := (top*(8-fy) + bot*fy) div 64;
          top := pb[c00]*(8-fx) + pb[c10]*fx;
          bot := pb[c01]*(8-fx) + pb[c11]*fx;
          b := (top*(8-fy) + bot*fy) div 64;

          hiFront[hy*hiFrontW + hx] :=
            (UInt32(r) shl fmt.Rshift) or (UInt32(g) shl fmt.Gshift) or
            (UInt32(b) shl fmt.Bshift) or fmt.Amask;
        end;
    end;

  SetLength(filled, 0);
  hiFrontReady := true;
end;

{ Mix two finished pixels. }
function MixPixel(lo, hi : UInt32; t, scale : LongInt; const fmt : THiFormat) : UInt32;

var unusedfmt : LongInt;
    r, g, b : LongInt;
begin
  r := ((((hi and fmt.Rmask) shr fmt.Rshift) * t) +
        (((lo and fmt.Rmask) shr fmt.Rshift) * (scale - t))) div scale;
  g := ((((hi and fmt.Gmask) shr fmt.Gshift) * t) +
        (((lo and fmt.Gmask) shr fmt.Gshift) * (scale - t))) div scale;
  b := ((((hi and fmt.Bmask) shr fmt.Bshift) * t) +
        (((lo and fmt.Bmask) shr fmt.Bshift) * (scale - t))) div scale;
  MixPixel := (UInt32(r) shl fmt.Rshift) or (UInt32(g) shl fmt.Gshift) or
              (UInt32(b) shl fmt.Bshift) or fmt.Amask;
end;

{ Expansion with the high-resolution layers mixed in.

  Laid out as spans rather than pixel by pixel. Along a texture row the hill
  and the backdrop are both contiguous in their resampled buffers and aligned
  with the destination, so the bulk of the row is two memory copies; only the
  few pixels straddling the silhouette need coverage arithmetic. Whatever the
  game drew over the frame since Tulosta ran is written back afterwards, so it
  keeps its original blocky look and its exact position. }
procedure Compose(pixels : Pointer; pitch : LongInt;
                  src : Pointer; srcPitch : LongInt;
                  wantBack, wantFront : boolean;
                  const fmt : THiFormat);

var srcRow, dstRow : PPixelRow;
    srcX, srcY, dstX, dstY, sub, rep : LongInt;
    colour, hillPix, backPix : UInt32;
    camX, camY, backOffX, backOffY, li : LongInt;
    fHiY, bHiY, bnd, bnd2, cov, edgeLocal : LongInt;
    sample, sub2, rim, rimT, hillEnd, skyStart, frontBase, backBase : LongInt;
    haveFront, haveBack, rowFront : boolean;
begin
  camX := Maki.X;
  camY := Maki.Y;
  backOffX := camX - (camX div 2);
  backOffY := camY - (camY div 2);
  haveFront := wantFront and hiFrontReady;
  haveBack  := wantBack and hiBackReady;

  for dstY := 0 to TexH - 1 do
    begin
      srcY := dstY div pixelScale;
      sub  := dstY mod pixelScale;
      srcRow := PPixelRow(PtrUInt(src) +
                          PtrUInt(srcY * srcPitch));
      dstRow := PPixelRow(PtrUInt(pixels) + PtrUInt(dstY * pitch));

      fHiY := camY * pixelScale + dstY;
      bHiY := (srcY + backOffY) * pixelScale + sub;
      { where each resampled row starts, in destination coordinates }
      frontBase := fHiY * hiFrontW + camX * pixelScale;
      backBase  := bHiY * hiBackW + backOffX * pixelScale;

      rowFront := haveFront and (fHiY >= 0) and (fHiY < hiFrontH);
      bnd := 0; bnd2 := 0;
      if (rowFront) then
        begin
          bnd := hiEdge[fHiY];
          if (fHiY + 1 < hiFrontH) then bnd2 := hiEdge[fHiY + 1] else bnd2 := bnd;
          edgeLocal := (((bnd + bnd2) div 2) shr 8) - camX * pixelScale;
          hillEnd  := edgeLocal - rimHi - 2;
          skyStart := edgeLocal + 2;
        end
      else
        begin
          { no reconstructed silhouette: split on the logical row extent }
          hillEnd  := (Maki.LinjanPituus[srcY + camY] - camX) * pixelScale;
          skyStart := hillEnd;
        end;
      if (hillEnd < 0) then hillEnd := 0;
      if (hillEnd > TexW) then hillEnd := TexW;
      if (skyStart < hillEnd) then skyStart := hillEnd;
      if (skyStart > TexW) then skyStart := TexW;

      { --- hill, in one copy --- }
      if (hillEnd > 0) then
        begin
          if (rowFront) then
            Move(hiFront[frontBase], dstRow^[0], hillEnd * SizeOf(UInt32))
          else
            for dstX := 0 to hillEnd - 1 do
              dstRow^[dstX] := srcRow^[dstX div pixelScale];
        end;

      { --- backdrop, in one copy --- }
      if (skyStart < TexW) then
        begin
          if (haveBack) and (bHiY >= 0) and (bHiY < hiBackH) then
            Move(hiBack[backBase + skyStart], dstRow^[skyStart],
                 (TexW - skyStart) * SizeOf(UInt32))
          else
            for dstX := skyStart to TexW - 1 do
              dstRow^[dstX] := srcRow^[dstX div pixelScale];
        end;

      { --- the handful of pixels across the edge --- }
      for dstX := hillEnd to skyStart - 1 do
        begin
          backPix := srcRow^[dstX div pixelScale];
          if (haveBack) and (bHiY >= 0) and (bHiY < hiBackH) then
            backPix := hiBack[backBase + dstX];

          cov := 0;
          for sample := 0 to 3 do
            begin
              sub2 := bnd + ((bnd2 - bnd) * (sample*2+1)) div 8
                          - (camX * pixelScale + dstX) * edgeFixed;
              if (sub2 > edgeFixed) then sub2 := edgeFixed;
              if (sub2 < 0) then sub2 := 0;
              cov := cov + sub2;
            end;
          cov := cov div 4;

          if (cov = 0) then dstRow^[dstX] := backPix
          else
            begin
              hillPix := hiFront[frontBase + dstX];
              rim := ((bnd + bnd2) div 2) - (camX * pixelScale + dstX) * edgeFixed;
              if (rim < rimHi * edgeFixed) then
                begin
                  rimT := (rimHi * edgeFixed) - rim;
                  if (rimT > edgeFixed) then rimT := edgeFixed;
                  if (rimT < 0) then rimT := 0;
                  hillPix := MixPixel(hillPix, hiRim, rimT, edgeFixed, fmt);
                end;
              if (cov = edgeFixed) then dstRow^[dstX] := hillPix
              else dstRow^[dstX] := MixPixel(backPix, hillPix, cov, edgeFixed, fmt);
            end;
        end;

      { --- put back whatever the game drew on top --- }
      for srcX := 0 to LogicalW - 1 do
        begin
          li := srcY * LogicalW + srcX;
          if (Maki.Video[li] <> Maki.VideoBase[li]) then
            begin
              colour := srcRow^[srcX];
              dstX := srcX * pixelScale;
              for rep := 0 to pixelScale - 1 do
                begin
                  dstRow^[dstX] := colour;
                  inc(dstX);
                end;
            end;
        end;
    end;
end;

end.
