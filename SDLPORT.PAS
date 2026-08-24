unit SDLPort;

interface

type TPalette = array[0..255,0..2] of byte;

type TCloseCallback = procedure ;

type TOverlayCallback = procedure ;

function GetVersion : string;
function PracticeMode : boolean;
function PhysicsTestMode : boolean;
procedure ReportFrameTime;
procedure InvalidateHiresBackdrop;

{ Draw at texture resolution rather than logical resolution. SetOverlayCallback
  registers something to run once per frame, after the logical frame has been
  expanded and while the texture is still locked; PlotHiIndex is what it draws
  with, taking texture coordinates and a palette index. }
procedure SetOverlayCallback(callback : TOverlayCallback);
procedure PlotHiIndex(x, y : integer; index : byte);
procedure PlotHiBlend(x, y : integer; index, alpha : byte);
function HiresTextEnabled : boolean;
function PixelScaleFactor : integer;

procedure Init;
procedure DeinitGraphics;
procedure Deinit;

procedure SetCloseCallback(callback : TCloseCallback);
procedure SetPalette(input : TPalette);
procedure Render(buffer : array of byte);
procedure WaitRaster;

function KeyPressed : boolean;
procedure WaitForKeyPress(var ch1, ch2 : char);

procedure Wait(ticks : integer);

implementation

uses sdl2, getopts, math, HiresHill;

const version: string = 'SP5';
  xRes = 320;
  yRes = 200;
  { Each logical pixel becomes a pixelScale x pixelScale block in the texture;
    the game still draws into a 320x200 byte buffer and knows nothing of it.
    The geometry lives in HiresHill, which is what resamples into it. }
  pixelScale = HiresHill.pixelScale;
  texW = HiresHill.TexW;
  texH = HiresHill.TexH;
  targetFrames = 70;
  aspectRes: real = xRes / yRes;
  msPerTick: real = 1000 / 18.2065; { typical IBM PC PIT system clock tick rate }

type TPixelRow = array[0..texW-1] of UInt32;
     PPixelRow = ^TPixelRow;

var windowMultiplier: integer;
  window: PSDL_Window;
  renderer: PSDL_Renderer;
  originalSurface: PSDL_Surface;
  displaySurface: PSDL_Surface;
  displayTexture: PSDL_Texture;
  palette: array[0..255] of TSDL_Color;
  renderDestRect: TSDL_Rect;

  windowResized: boolean;
  fullScreen: boolean;
  aspect: real;

  timer: TSDL_TimerID;
  frameCount, lastFrameCount, subFrameCount, lastFrameTick: LongInt;
  closeCallback: TCloseCallback;

  swRendering: boolean;
  practiceRun: boolean;
  timeFrames: boolean;
  physicsTest: boolean;
  hiresTest: boolean;
  hiresBack: boolean;
  hiresFront: boolean;
  { The backdrop, resampled once per hill to pixelScale resolution and held as
    finished colours. It is purely decorative - LaskeLinjat never reads it - so
    smoothing it cannot affect the hill profile or the physics. }
  hiresText: boolean;
  { the palette range the resampled layers were built from, watched so that a
    new hill's colours force a rebuild }
  hiBackPalette: array[0..214] of TSDL_Color;
  hiPal: THiPalette;
  hiFmt: THiFormat;
  overlayCallback: TOverlayCallback;
  { valid only while the overlay callback runs }
  overlayPixels: Pointer;
  overlayPitch: LongInt;
  renderTicks, renderCount, renderPeak: UInt64;
  expandTicks: UInt64;

procedure GetArguments;

var c : char;
  optionindex : Longint;
  { One more than there are options: getopts walks this array until it finds
    an entry with an empty name, so it must be terminated. Without that it
    reads past the end into whatever follows, which happened to be harmless
    on Linux and faulted on Windows. }
  options : array[1..14] of TOption;

begin
  with options[1] do
    begin
      name := '--sw-rendering';
      has_arg := 0;
      flag := nil;
      value := #0;
    end;
  with options[2] do
    begin
      name := '--practice';
      has_arg := 0;
      flag := nil;
      value := #0;
    end;
  with options[3] do
    begin
      name := '--frame-time';
      has_arg := 0;
      flag := nil;
      value := #0;
    end;
  with options[4] do
    begin
      name := '--hires-test';
      has_arg := 0;
      flag := nil;
      value := #0;
    end;
  with options[5] do
    begin
      name := '--hires-back';
      has_arg := 0;
      flag := nil;
      value := #0;
    end;
  with options[6] do
    begin
      name := '--hires-text';
      has_arg := 0;
      flag := nil;
      value := #0;
    end;
  with options[7] do
    begin
      name := '--no-hires';
      has_arg := 0;
      flag := nil;
      value := #0;
    end;
  with options[8] do
    begin
      name := '--no-hires-text';
      has_arg := 0;
      flag := nil;
      value := #0;
    end;
  with options[9] do
    begin
      name := '--no-hires-back';
      has_arg := 0;
      flag := nil;
      value := #0;
    end;
  with options[10] do
    begin
      name := '--no-hires-front';
      has_arg := 0;
      flag := nil;
      value := #0;
    end;
  with options[11] do
    begin
      name := '--hires-front';
      has_arg := 0;
      flag := nil;
      value := #0;
    end;
  with options[12] do
    begin
      name := '--accelerated-rendering';
      has_arg := 0;
      flag := nil;
      value := #0;
    end;
  with options[13] do
    begin
      name := '--physics-test';
      has_arg := 0;
      flag := nil;
      value := #0;
    end;
  with options[14] do          { terminator - see the declaration }
    begin
      name := '';
      has_arg := 0;
      flag := nil;
      value := #0;
    end;
  c := #0;
  optionindex := 0;
  repeat
    c := getlongopts('sp', @options[1], optionindex);
    case c of
      #0 :
           begin
             if (options[optionindex].name = '--sw-rendering') then
               begin
                 swRendering := true;
               end;
             if (options[optionindex].name = '--practice') then
               begin
                 practiceRun := true;
               end;
             if (options[optionindex].name = '--frame-time') then
               begin
                 timeFrames := true;
               end;
             if (options[optionindex].name = '--hires-test') then
               begin
                 hiresTest := true;
               end;
             if (options[optionindex].name = '--hires-back') then
               begin
                 hiresBack := true;
               end;
             if (options[optionindex].name = '--hires-text') then
               begin
                 hiresText := true;
               end;
             if (options[optionindex].name = '--no-hires') then
               begin
                 hiresText := false;
                 hiresBack := false;
                 hiresFront := false;
               end;
             if (options[optionindex].name = '--no-hires-text') then
               begin
                 hiresText := false;
               end;
             if (options[optionindex].name = '--no-hires-back') then
               begin
                 hiresBack := false;
               end;
             if (options[optionindex].name = '--no-hires-front') then
               begin
                 hiresFront := false;
               end;
             if (options[optionindex].name = '--hires-front') then
               begin
                 hiresFront := true;
               end;
             if (options[optionindex].name = '--accelerated-rendering') then
               begin
                 swRendering := false;
               end;
             if (options[optionindex].name = '--physics-test') then
               begin
                 physicsTest := true;
               end;
           end;
      's' : swRendering := true;
      'p' : practiceRun := true;
    end; { case }
  until c=endofoptions;
end;

function TimerCallback(interval: UInt32; param: Pointer): UInt32;
cdecl;

var frameIntervalMs, nowMs, elapsed : LongInt;
begin
  frameIntervalMs := 1000 div targetFrames;
  nowMs := SDL_GetTicks();
  elapsed := nowMs - lastFrameTick;
  if (elapsed >= frameIntervalMs) then
    begin
      lastFrameTick := nowMs;
      subFrameCount := subFrameCount + elapsed;

      while (subFrameCount >= frameIntervalMs) do
        begin
          dec(subFrameCount, frameIntervalMs);
          inc(framecount);
        end;
    end;
  TimerCallback := interval;
end;

procedure GetRenderRect(var rect : TSDL_Rect);

var windowW, windowH, h, w: LongInt;
begin
  SDL_GetRendererOutputSize(renderer, @windowW, @windowH);
  if (windowW / windowH <= aspect) then
    begin
      h := round(windowW / aspect);
      rect.x := 0;
      rect.y := (windowH - h) div 2;
      rect.w := windowW;
      rect.h := h;
    end
  else
    begin
      w := round(windowH * aspect);
      rect.x := (windowW - w) div 2;
      rect.y := 0;
      rect.w := w;
      rect.h := windowH;
    end;
end;

procedure RefreshRendering;
begin
  GetRenderRect(renderDestRect);
end;

procedure ResetWindowSize;
begin
  SDL_SetWindowSize(window, xRes * windowMultiplier, Round(yRes * windowMultiplier * aspectRes /
                    aspect));
  windowResized := true;
end;

function GetVersion: string;
begin
  GetVersion := version;
end;

{ Skip the menus and drop straight into practice on the first hill. Used when
  iterating on the jump itself, so a run takes one command instead of a dozen
  keypresses. Normal play is unaffected. }
function PracticeMode: boolean;
begin
  PracticeMode := practiceRun;
end;

{ Run jumps as fast as the machine allows and hash what the simulation did,
  rather than drawing anything. See PhysicsTest in SJ3.PAS. }
function PhysicsTestMode: boolean;
begin
  PhysicsTestMode := physicsTest;
end;

{ With --frame-time, report how long Render took. The frame budget is
  1000/targetFrames ms, so this says how much of it the pixel work costs. }
procedure ReportFrameTime;

var freq : UInt64;
begin
  if (not timeFrames) or (renderCount = 0) then exit;
  freq := SDL_GetPerformanceFrequency;
  writeln;
  writeln('Render: ', renderCount, ' frames, ',
          (renderTicks * 1000000) div (freq * renderCount), ' us average, ',
          (renderPeak * 1000000) div freq, ' us peak, budget ',
          (1000000 div targetFrames), ' us');
  writeln('  of which expansion: ',
          (expandTicks * 1000000) div (freq * renderCount), ' us average');
end;

procedure Init;

var rendererFlags : UInt32;
begin
  rendererFlags := 0;
  windowMultiplier := pixelScale;
  aspect := aspectRes;
  { Software rendering by default. The game hands SDL one full-screen texture
    per frame and asks nothing else of the renderer, so there is little for a
    GPU to do - but the accelerated path pays for one anyway. Where the driver
    is a software implementation of OpenGL, SDL_LockTexture returns
    write-combined memory and the per-frame copies into it cost about twice
    what they do against ordinary RAM. Measured during a jump on a machine
    reporting no acceleration: 14.6-17.2 ms through OpenGL against 8.8-10.6 ms
    in software, on a 14.3 ms budget. --accelerated-rendering asks for the
    accelerated path on machines that really have one. }
  swRendering := true;
  practiceRun := false;
  timeFrames := false;
  hiresTest := false;
  physicsTest := false;
  { The high-resolution paths are the point of the port now, so they are on
    unless asked otherwise. --no-hires restores the original rendering, which
    is also how the pixel-identity regression check is run. }
  hiresBack := true;
  hiresFront := true;
  hiresText := true;
  HiresHill.Invalidate;
  overlayCallback := nil;
  overlayPixels := nil;
  renderTicks := 0;
  renderCount := 0;
  renderPeak := 0;
  expandTicks := 0;

  GetArguments;

{ Free Pascal leaves the FPU exception mask open, so any invalid operation
    performed internally by the video driver (Mesa/OpenGL in particular) is
    trapped and re-raised as EInvalidOp, killing the process before the first
    frame. Mask them; none of the game's own arithmetic relies on trapping. }
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide,
                   exOverflow, exUnderflow, exPrecision]);

  if SDL_Init( SDL_INIT_VIDEO or SDL_INIT_TIMER ) < 0 then HALT;

  window := SDL_CreateWindow('Ski Jump International v3',
            SDL_WINDOWPOS_UNDEFINED,
            SDL_WINDOWPOS_UNDEFINED,
            xRes * windowMultiplier,
            yRes * windowMultiplier,
            SDL_WINDOW_SHOWN or SDL_WINDOW_RESIZABLE);
  if window = nil then Halt;

  if (swRendering) then
    rendererFlags := rendererFlags or SDL_RENDERER_SOFTWARE
  else
    { Ask for acceleration rather than leaving the choice to SDL, so that
      --accelerated-rendering means what its name says. }
    rendererFlags := rendererFlags or SDL_RENDERER_ACCELERATED;

  { Nearest-neighbour scaling. This is SDL's default, so the game already
    looked right, but nothing said so: a host that sets the hint globally would
    silently blur every pixel. Pin it before the renderer is created, which is
    when the hint is read. }
  SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, '0');

  renderer := SDL_CreateRenderer(window, -1, rendererFlags);
  { no accelerated driver available: fall back rather than refuse to start }
  if (renderer = nil) and (not swRendering) then
    renderer := SDL_CreateRenderer(window, -1, 0);
  if renderer = nil then Halt;

  { The game never fills the whole window - GetRenderRect letterboxes to keep
    the aspect ratio - so the bars are painted with the clear colour. SDL does
    not promise a particular default, so say black explicitly. }
  SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);

  // 8-bit surface for original data
  originalSurface := SDL_CreateRGBSurface(0, xRes, yRes, 8, 0, 0, 0, 0);
  if originalSurface = nil then Halt;

  { 32-bit staging surface, in the texture's own format so that expanding into
    the texture is a straight copy with no pixel conversion. }
  displaySurface := SDL_CreateRGBSurfaceWithFormat(0, xRes, yRes, 32,
                    SDL_PIXELFORMAT_RGBA8888);
  if displaySurface = nil then Halt;

  { The texture is pixelScale times larger than the logical frame. }
  displayTexture := SDL_CreateTexture(renderer,
                    SDL_PIXELFORMAT_RGBA8888,
                    SDL_TEXTUREACCESS_STREAMING,
                    texW,
                    texH);
  if displayTexture = nil then Halt;

  RefreshRendering();

  windowResized := false;
  fullScreen := false;

  frameCount := 0;
  lastFrameCount := 0;
  subFrameCount := 0;
  lastFrameTick := SDL_GetTicks();

  timer := SDL_AddTimer(1, TimerCallback, nil);

  closeCallback := nil;
end;

procedure DeinitGraphics;
begin
  ReportFrameTime;
  SDL_RemoveTimer(timer);
  SDL_FreeSurface(originalSurface);
  SDL_FreeSurface(displaySurface);
  SDL_DestroyTexture(displayTexture);
  SDL_DestroyRenderer(renderer);
  SDL_DestroyWindow(window);
end;

procedure Deinit;
begin
  SDL_Quit;
end;

procedure SetPalette(input : TPalette);

var index : integer;
begin
  for index:=0 to 255 do
    begin
      palette[index].r := input[index,0] shl 2;
      palette[index].g := input[index,1] shl 2;
      palette[index].b := input[index,2] shl 2;
    end;

  SDL_SetPaletteColors(originalSurface^.format^.palette, @palette, 0, 256);

  { The resampled backdrop holds finished colours, so it has to be rebuilt if
    the palette range it was built from changes. LoadHill leaves the previous
    hill's palette in place until the game calls AsetaPaletti, which is after
    the first frame is drawn, so keying off the hill alone is not enough. }
  for index := 0 to 214 do
    if (palette[index].r <> hiBackPalette[index].r) or
       (palette[index].g <> hiBackPalette[index].g) or
       (palette[index].b <> hiBackPalette[index].b) then
      begin
        HiresHill.Invalidate;
        Move(palette[0], hiBackPalette[0], 215 * SizeOf(TSDL_Color));
        break;
      end;
end;

procedure SetCloseCallback(callback : TCloseCallback);
begin
  closeCallback := callback;
end;

{ Describe the palette and the texture's pixel layout in HiresHill's terms,
  so that it needs to know nothing about SDL. }
procedure DescribeTarget(var pal : THiPalette; var fmt : THiFormat);

var i : integer;
begin
  for i := 0 to 255 do
    begin
      pal[i,0] := palette[i].r;
      pal[i,1] := palette[i].g;
      pal[i,2] := palette[i].b;
    end;
  fmt.Rshift := displaySurface^.format^.Rshift;
  fmt.Gshift := displaySurface^.format^.Gshift;
  fmt.Bshift := displaySurface^.format^.Bshift;
  fmt.Rmask  := displaySurface^.format^.Rmask;
  fmt.Gmask  := displaySurface^.format^.Gmask;
  fmt.Bmask  := displaySurface^.format^.Bmask;
  fmt.Amask  := displaySurface^.format^.Amask;
end;

procedure InvalidateHiresBackdrop;
begin
  HiresHill.Invalidate;
end;

procedure SetOverlayCallback(callback : TOverlayCallback);
begin
  overlayCallback := callback;
end;

function HiresTextEnabled: boolean;
begin
  HiresTextEnabled := hiresText;
end;

function PixelScaleFactor: integer;
begin
  PixelScaleFactor := pixelScale;
end;

{ Blend a palette colour over what is already in the texture. Anti-aliased
  glyph edges arrive as coverage values rather than as on or off, so they have
  to be mixed with the background rather than overwriting it. }
procedure PlotHiBlend(x, y : integer; index, alpha : byte);

var fmt : PSDL_PixelFormat;
    row : PPixelRow;
    old : UInt32;
    orr, og, ob, nr, ng, nb : LongInt;
begin
  if (overlayPixels = nil) or (alpha = 0) then exit;
  if (x < 0) or (x >= texW) or (y < 0) or (y >= texH) then exit;
  fmt := displaySurface^.format;
  row := PPixelRow(PtrUInt(overlayPixels) + PtrUInt(y * overlayPitch));

  if (alpha = 255) then
    begin
      row^[x] := (UInt32(palette[index].r) shl fmt^.Rshift) or
                 (UInt32(palette[index].g) shl fmt^.Gshift) or
                 (UInt32(palette[index].b) shl fmt^.Bshift) or fmt^.Amask;
      exit;
    end;

  old := row^[x];
  orr := (old and fmt^.Rmask) shr fmt^.Rshift;
  og  := (old and fmt^.Gmask) shr fmt^.Gshift;
  ob  := (old and fmt^.Bmask) shr fmt^.Bshift;

  nr := (palette[index].r * alpha + orr * (255 - alpha)) div 255;
  ng := (palette[index].g * alpha + og  * (255 - alpha)) div 255;
  nb := (palette[index].b * alpha + ob  * (255 - alpha)) div 255;

  row^[x] := (UInt32(nr) shl fmt^.Rshift) or
             (UInt32(ng) shl fmt^.Gshift) or
             (UInt32(nb) shl fmt^.Bshift) or fmt^.Amask;
end;

procedure PlotHiIndex(x, y : integer; index : byte);

var fmt : PSDL_PixelFormat;
begin
  if (overlayPixels = nil) then exit;
  if (x < 0) or (x >= texW) or (y < 0) or (y >= texH) then exit;
  fmt := displaySurface^.format;
  PPixelRow(PtrUInt(overlayPixels) + PtrUInt(y * overlayPitch))^[x] :=
    (UInt32(palette[index].r) shl fmt^.Rshift) or
    (UInt32(palette[index].g) shl fmt^.Gshift) or
    (UInt32(palette[index].b) shl fmt^.Bshift) or fmt^.Amask;
end;

{ Plot a single texture pixel. Coordinates are texture pixels, not logical
  ones, so this can address detail four times finer than the game can. }
procedure PlotHi(pixels : Pointer; pitch, x, y : LongInt; colour : UInt32);
begin
  if (x >= 0) and (x < texW) and (y >= 0) and (y < texH) then
    PPixelRow(PtrUInt(pixels) + PtrUInt(y * pitch))^[x] := colour;
end;

{ A test card proving the texture really is 1280x800 and not a magnified
  320x200 image. Each figure is drawn twice: on the left at texture
  resolution, on the right in 4x4 blocks the way the game would have to draw
  it. If the two halves look the same, the extra pixels are not real. }
procedure DrawHiresTest(pixels : Pointer; pitch : LongInt);
const
  white = $FFFFFFFF;
  black = $000000FF;
  amber = $FFB000FF;
  slate = $5A6478FF;
var
  i, x, y, bx, by : LongInt;
begin
  for y := 0 to 135 do
    for x := 0 to 371 do
      PlotHi(pixels, pitch, 12 + x, 12 + y, black);

  for x := 0 to 371 do
    begin
      PlotHi(pixels, pitch, 12 + x, 12, slate);
      PlotHi(pixels, pitch, 12 + x, 147, slate);
    end;
  for y := 0 to 135 do
    begin
      PlotHi(pixels, pitch, 12, 12 + y, slate);
      PlotHi(pixels, pitch, 383, 12 + y, slate);
      PlotHi(pixels, pitch, 197, 12 + y, slate);
    end;

  { --- left: true texture resolution --- }
  for i := 0 to 99 do                        { one-pixel diagonal }
    PlotHi(pixels, pitch, 24 + i, 24 + i, white);
  for i := 0 to 79 do                        { one-on one-off comb }
    if (i mod 2) = 0 then
      for y := 0 to 39 do
        PlotHi(pixels, pitch, 100 + i, 30 + y, amber);
  for i := 0 to 79 do                        { one-pixel horizontal rules }
    if (i mod 2) = 0 then
      for x := 0 to 79 do
        PlotHi(pixels, pitch, 100 + x, 84 + i div 2 * 2, amber);

  { --- right: the same, in 4x4 blocks, as the game would draw it --- }
  for i := 0 to 24 do
    for by := 0 to 3 do
      for bx := 0 to 3 do
        PlotHi(pixels, pitch, 208 + i*4 + bx, 24 + i*4 + by, white);
  for i := 0 to 19 do
    if (i mod 2) = 0 then
      for y := 0 to 39 do
        for bx := 0 to 3 do
          PlotHi(pixels, pitch, 284 + i*4 + bx, 30 + y, amber);
  for i := 0 to 19 do
    if (i mod 2) = 0 then
      for by := 0 to 3 do
        for x := 0 to 79 do
          PlotHi(pixels, pitch, 284 + x, 84 + i*4 + by, amber);
end;

procedure Render(buffer : array of byte);

var pixels : Pointer;
  pitch : LongInt;
  srcRow, dstRow : PPixelRow;
  srcX, srcY, dstX, dstY, rep : LongInt;
  colour : UInt32;
  t0, t1, dt : UInt64;
begin
  if (timeFrames) then t0 := SDL_GetPerformanceCounter;

  if (windowResized) then
    begin
      RefreshRendering();
      windowResized := false;
    end;

  SDL_RenderClear(renderer);

  // Actual rendering
  SDL_LockSurface(originalSurface);
  Move(buffer, originalSurface^.pixels^, Sizeof(buffer));
  SDL_UnlockSurface(originalSurface);

  // Blit 8-bit surface to 32-bit surface
  SDL_BlitSurface(originalSurface, nil, displaySurface, nil);

  { Expand the logical frame into the texture, each pixel becoming a
    pixelScale x pixelScale block. Only every pixelScale'th destination row is
    built pixel by pixel; the rows between it are identical, so they are copied
    wholesale. Source and destination share a pixel format, so no conversion
    happens here. }
  if (timeFrames) then t1 := SDL_GetPerformanceCounter;

  if ((hiresBack) and (not HiresHill.BackdropReady)) or
     ((hiresFront) and (not HiresHill.ForegroundReady)) then
    begin
      DescribeTarget(hiPal, hiFmt);
      if (hiresBack) and (not HiresHill.BackdropReady) then
        HiresHill.BuildBackdrop(hiPal, hiFmt);
      if (hiresFront) and (not HiresHill.ForegroundReady) then
        HiresHill.BuildForeground(hiPal, hiFmt);
    end;

  SDL_LockTexture(displayTexture, nil, @pixels, @pitch);

  if ((hiresBack) and (HiresHill.BackdropReady)) or
     ((hiresFront) and (HiresHill.ForegroundReady)) then
    begin
      DescribeTarget(hiPal, hiFmt);
      HiresHill.Compose(pixels, pitch,
                        displaySurface^.pixels, displaySurface^.pitch,
                        hiresBack, hiresFront, hiFmt);
    end
  else
  for srcY := 0 to yRes - 1 do
    begin
      srcRow := PPixelRow(PtrUInt(displaySurface^.pixels) +
                          PtrUInt(srcY * displaySurface^.pitch));
      dstY := srcY * pixelScale;
      dstRow := PPixelRow(PtrUInt(pixels) + PtrUInt(dstY * pitch));

      dstX := 0;
      for srcX := 0 to xRes - 1 do
        begin
          colour := srcRow^[srcX];
          for rep := 1 to pixelScale do
            begin
              dstRow^[dstX] := colour;
              inc(dstX);
            end;
        end;

      { the rows between are identical, so copy rather than rebuild }
      for rep := 1 to pixelScale - 1 do
        Move(dstRow^,
             PPixelRow(PtrUInt(pixels) + PtrUInt((dstY + rep) * pitch))^,
             texW * SizeOf(UInt32));
    end;

  if (Assigned(overlayCallback)) then
    begin
      overlayPixels := pixels;
      overlayPitch := pitch;
      overlayCallback;
      overlayPixels := nil;
    end;

  if (hiresTest) then DrawHiresTest(pixels, pitch);

  SDL_UnlockTexture(displayTexture);
  if (timeFrames) then expandTicks := expandTicks + (SDL_GetPerformanceCounter - t1);

  // Render texture to display
  SDL_RenderCopy(renderer, displayTexture, nil, @renderDestRect);
  SDL_RenderPresent(renderer);

  if (timeFrames) then
    begin
      dt := SDL_GetPerformanceCounter - t0;
      renderTicks := renderTicks + dt;
      inc(renderCount);
      if (dt > renderPeak) then renderPeak := dt;
    end;
end;

procedure WaitRaster;
begin
  lastFrameCount := framecount;
  while (lastFrameCount = framecount) do
    begin
      SDL_Delay(1);
    end;
end;

function KeyPressed : boolean;

var event : TSDL_Event;
  pressed: boolean;
begin
  pressed := false;
  if (physicsTest) then begin KeyPressed := false; exit; end;

  while SDL_PollEvent(@event) = 1 do
    begin
      if ((event.type_= SDL_WINDOWEVENT) and
         (event.window.event = SDL_WINDOWEVENT_RESIZED)) then
        begin
          windowResized := true;
        end;

      if (event.type_= SDL_QUITEV) then
        begin
          if Assigned(closeCallback) then
            begin
              closeCallback;
            end;
        end;

      if event.type_= SDL_KEYDOWN then
        begin
          // Ignore modifier and status keys, since they did not trigger a keypress in DOS version.

      // F11, F12 and probably others were ignored too, but that would probably be counterintuitive.
          case event.key.keysym.sym of
            SDLK_LCTRL, SDLK_RCTRL,
            SDLK_LSHIFT, SDLK_RSHIFT,
            SDLK_LALT, SDLK_RALT,
            SDLK_LGUI, SDLK_RGUI,
            SDLK_CAPSLOCK, SDLK_SCROLLLOCK, SDLK_NUMLOCKCLEAR,
            SDLK_PRINTSCREEN, SDLK_SYSREQ, SDLK_PAUSE:
            ;
            // Keypress ignored
            else
              begin
                pressed := true;
                SDL_PushEvent(@event);
                break;
              end;
          end;
        end;
    end;
  KeyPressed := pressed
end;

procedure ToggleFullscreen;

var flags : UInt32;
begin
  windowResized := true;

  fullScreen := not fullScreen;
  if (fullScreen) then flags := SDL_WINDOW_FULLSCREEN_DESKTOP
  else flags := 0;

  SDL_SetWindowFullscreen(window, flags);
end;

procedure WaitForKeyPress(var ch1, ch2:char);

var event : TSDL_Event;
  scancode: TSDL_ScanCode;
  keyPressed: TSDL_KeyCode;
  keyMod: UInt16;
begin
  ch1 := #0;
  ch2 := #0;

  { The physics test runs with nobody at the keyboard, and the game stops for
    a keypress after every jump. Answer as though Enter had been pressed, so
    it walks through the result screens by itself. }
  if (physicsTest) then
    begin
      ch1 := #13;
      exit;
    end;
  // Setting ch2 to a correct scancode value for the key pressed can be largely ignored.
  // It is only checked by the game for special keys, where ch1 is checked or assumed to be 0.

// This also means that the game cannot differentiate between different keys producing the same character.

  while (true) do
    begin
      while SDL_PollEvent(@event) = 1 do
        begin
          if event.type_= SDL_KEYDOWN then
            begin
              scancode := event.key.keysym.scancode;
              keyPressed := event.key.keysym.sym;
              keyMod := event.key.keysym._mod;

              // SDL version specific shortcuts
              if ((keyMod and KMOD_LALT) > 0) then
                begin
                  case scancode of
                    SDL_SCANCODE_RETURN :
                                          begin
                                            toggleFullscreen;
                                            exit
                                          end;
                    SDL_SCANCODE_R :
                                     begin
                                       ResetWindowSize;
                                       exit
                                     end;
                    SDL_SCANCODE_KP_PLUS, SDL_SCANCODE_EQUALS :
                                                                begin
                                                                  windowMultiplier :=
                                                                                    windowMultiplier
                                                                                      + 1;
                                                                  ResetWindowSize;
                                                                  exit
                                                                end;
                    SDL_SCANCODE_KP_MINUS, SDL_SCANCODE_MINUS :
                                                                begin
                                                                  if (windowMultiplier > 1) then
                                                                    begin
                                                                      windowMultiplier :=
                                                                                    windowMultiplier
                                                                                          - 1;
                                                                      ResetWindowSize;
                                                                      exit
                                                                    end;
                                                                end;
                    SDL_SCANCODE_A :
                                     begin
                                       if (aspect <> aspectRes) then
                                         aspect := aspectRes
                                       else
                                         aspect := 4 / 3;
                                       ResetWindowSize;
                                       exit;
                                     end;
                  end;
                end;

              // Special cases for key combinations used throughout the game.

       // Check for Right Alt/AltGr first, since pressing it can make Left Ctrl look as pressed too.
              if ((keyMod and KMOD_MODE) > 0) then exit;
              if ((keyMod and KMOD_RALT) > 0) then exit;
              if ((keyMod and KMOD_LALT) > 0) then
                begin
                  case keyPressed of
                    SDLK_x:
                            begin
                              ch1 := #0;
                              ch2 := #45;
                              exit
                            end; {ALT-X}
                    else
                      exit
                  end;
                end;
              if ((keyMod and KMOD_CTRL) > 0) then
                begin
                  case keyPressed of
                    SDLK_c:
                            begin
                              ch1 := #3;
                              exit
                            end; {CTRL-C}
                    else
                      exit
                  end;
                end;
              if ((keyMod and KMOD_GUI) > 0) then exit;

              // Handle conversion of letters to uppercase.
              // Convert only if Caps Lock is off and Shift is pressed or vice versa.
              if (
                 ((keyMod and KMOD_SHIFT) > 0) xor ((keyMod and KMOD_CAPS) > 0)
                 ) then
                begin
                  case keypressed of
                    97..122, 224..246, 248..254: keyPressed := TSDL_KeyCode(keyPressed - 32);
                  end;
                end;

              // if modifier is Shift, convert the key pressed accordingly.
              // for special keys, standard US QWERTY layout is assumed.
              if ((keyMod and KMOD_SHIFT) > 0) then
                begin
                  case keyPressed of
                    65..90, 97..122, 190..214, 216..222, 224..246, 248..254: ;
                    // Already handled above
                    SDLK_1 : keyPressed := SDLK_EXCLAIM;
                    SDLK_2 : keyPressed := SDLK_AT;
                    SDLK_3 : keyPressed := SDLK_HASH;
                    SDLK_4 : keyPressed := SDLK_DOLLAR;
                    SDLK_5 : keyPressed := SDLK_PERCENT;
                    SDLK_6 : keyPressed := SDLK_CARET;
                    SDLK_7 : keyPressed := SDLK_AMPERSAND;
                    SDLK_8 : keyPressed := SDLK_ASTERISK;
                    SDLK_9 : keyPressed := SDLK_LEFTPAREN;
                    SDLK_0 : keyPressed := SDLK_RIGHTPAREN;
                    SDLK_MINUS : keyPressed := SDLK_UNDERSCORE;
                    SDLK_EQUALS : keyPressed := SDLK_PLUS;
                    SDLK_LEFTBRACKET : keyPressed := TSDL_KeyCode('{');
                    SDLK_RIGHTBRACKET : keyPressed := TSDL_KeyCode('}');
                    SDLK_SEMICOLON : keyPressed := SDLK_COLON;
                    SDLK_QUOTE : keyPressed := SDLK_QUOTEDBL;
                    SDLK_BACKQUOTE : keyPressed := TSDL_KeyCode('~');
                    SDLK_BACKSLASH : keyPressed := TSDL_KeyCode('|');
                    SDLK_COMMA : keyPressed := SDLK_LESS;
                    SDLK_PERIOD : keyPressed := SDLK_GREATER;
                    SDLK_SLASH : keyPressed := SDLK_QUESTION;
                    else
                      exit
                  end;
                end;

              // if NumLock modifier is not set, convert the charaters accordingly
              if ((keyMod and KMOD_NUM) = 0) then
                begin
                  case keyPressed of
                    SDLK_KP_1 : keyPressed := SDLK_END;
                    SDLK_KP_2 : keyPressed := SDLK_DOWN;
                    SDLK_KP_3 : keyPressed := SDLK_PAGEDOWN;
                    SDLK_KP_4 : keyPressed := SDLK_LEFT;
                    SDLK_KP_5 :
                                begin
                                  ch1 := #0;
                                  ch2 := #76;
                                  exit
                                end;
                    SDLK_KP_6 : keyPressed := SDLK_RIGHT;
                    SDLK_KP_7 : keyPressed := SDLK_HOME;
                    SDLK_KP_8 : keyPressed := SDLK_UP;
                    SDLK_KP_9 : keyPressed := SDLK_PAGEUP;
                    SDLK_KP_0 : keyPressed := SDLK_INSERT;
                    SDLK_KP_PERIOD : keyPressed := SDLK_DELETE;
                  end;
                end;

              // Merge keypad characters with their regular counterparts.

// It is not needed to differentiate between them, since the scancode isn't checked for normal characters.

         // Checks for Shift and Num Lock were already done, so they won't interfere with the merge.
              case keyPressed of
                SDLK_KP_DIVIDE : keyPressed := SDLK_SLASH;
                SDLK_KP_MULTIPLY : keyPressed := SDLK_ASTERISK;
                SDLK_KP_MINUS : keyPressed := SDLK_MINUS;
                SDLK_KP_PLUS : keyPressed := SDLK_PLUS;
                SDLK_KP_ENTER : keyPressed := SDLK_RETURN;
                SDLK_KP_1 : keyPressed := SDLK_1;
                SDLK_KP_2 : keyPressed := SDLK_2;
                SDLK_KP_3 : keyPressed := SDLK_3;
                SDLK_KP_4 : keyPressed := SDLK_4;
                SDLK_KP_5 : keyPressed := SDLK_5;
                SDLK_KP_6 : keyPressed := SDLK_6;
                SDLK_KP_7 : keyPressed := SDLK_7;
                SDLK_KP_8 : keyPressed := SDLK_8;
                SDLK_KP_9 : keyPressed := SDLK_9;
                SDLK_KP_0 : keyPressed := SDLK_0;
                SDLK_KP_PERIOD : keyPressed := SDLK_PERIOD;
                SDLK_KP_EQUALS : keyPressed := SDLK_EQUALS;
              end;

              case keyPressed of
                SDLK_RETURN : ch1 := #13;
                SDLK_ESCAPE : ch1 := #27;
                SDLK_BACKSPACE : ch1 := #8;
                SDLK_TAB : ch1 := #9;

                32..126 : ch1 := chr(keyPressed);

         // Special characters supported by the game, OEM 865 nordic encoding is used for ch1 values
                196 :
                      begin
                        ch1 := #142;
                        exit
                      end;
                // A with diaeresis
                197 :
                      begin
                        ch1 := #143;
                        exit
                      end;
                // A with ring above
                198 :
                      begin
                        ch1 := #146;
                        exit
                      end;
                // AE
                214 :
                      begin
                        ch1 := #153;
                        exit
                      end;
                // O with diaeresis
                216 :
                      begin
                        ch1 := #157;
                        exit
                      end;
                // O with stroke
                220 :
                      begin
                        ch1 := #154;
                        exit
                      end;
                // U with diaeresis
                223 :
                      begin
                        ch1 := #225;
                        exit
                      end;
                // sharp s

                228 :
                      begin
                        ch1 := #132;
                        ch2 := #36;
                        exit
                      end;
                // a with diaeresis
                229 :
                      begin
                        ch1 := #134;
                        ch2 := #26;
                        exit
                      end;
                // a with ring above
                230 :
                      begin
                        ch1 := #145;
                        exit
                      end;
                // ae
                246 :
                      begin
                        ch1 := #148;
                        ch2 := #39;
                        exit
                      end;
                // o with diaeresis
                248 :
                      begin
                        ch1 := #158;
                        exit
                      end;
                // o with stroke
                252 :
                      begin
                        ch1 := #129;
                        exit
                      end;
                // u with diaeresis
              end;

              case keyPressed of
                SDLK_F1 : ch2 := #59;
                SDLK_F2 : ch2 := #60;
                SDLK_F3 : ch2 := #61;
                SDLK_F4 : ch2 := #62;
                SDLK_F5 : ch2 := #63;
                SDLK_F6 : ch2 := #64;
                SDLK_F7 : ch2 := #65;
                SDLK_F8 : ch2 := #66;
                SDLK_F9 : ch2 := #67;
                SDLK_F10 : ch2 := #68;

                SDLK_LEFT : ch2 := #75;
                SDLK_RIGHT : ch2 := #77;
                SDLK_UP : ch2 := #72;
                SDLK_DOWN : ch2 := #80;

                SDLK_INSERT : ch2 := #82;
                SDLK_DELETE : ch2 := #83;
                SDLK_HOME : ch2 := #71;
                SDLK_END : ch2 := #79;
                SDLK_PAGEUP : ch2 := #73;
                SDLK_PAGEDOWN : ch2 := #81;

                SDLK_a : ch2 := #30;
                SDLK_b : ch2 := #48;
                SDLK_c : ch2 := #46;
                SDLK_d : ch2 := #32;
                SDLK_e : ch2 := #18;
                SDLK_f : ch2 := #33;
                SDLK_g : ch2 := #34;
                SDLK_h : ch2 := #35;
                SDLK_i : ch2 := #23;
                SDLK_j : ch2 := #36;
                SDLK_k : ch2 := #37;
                SDLK_l : ch2 := #38;
                SDLK_m : ch2 := #50;
                SDLK_n : ch2 := #49;
                SDLK_o : ch2 := #24;
                SDLK_p : ch2 := #25;
                SDLK_q : ch2 := #16;
                SDLK_r : ch2 := #19;
                SDLK_s : ch2 := #31;
                SDLK_t : ch2 := #20;
                SDLK_u : ch2 := #22;
                SDLK_v : ch2 := #47;
                SDLK_w : ch2 := #17;
                SDLK_x : ch2 := #45;
                SDLK_y : ch2 := #21;
                SDLK_z : ch2 := #44;
              end;
              exit;
            end;
        end;
      SDL_Delay(10);
    end;
end;

procedure Wait(ticks : integer);
begin
  SDL_Delay(Round(ticks * msPerTick));
end;

end.
