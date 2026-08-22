# SJ3 Modernization Notes

Working notes for the graphics modernization of this SDL2 port, from a read-only
inspection pass plus build and runtime testing on Ubuntu.

Line references are navigation hints, not precise citations. The dead-code and
formatting passes moved every line in the codebase, and although the numbers
below were remapped, some are off by a few lines. Search for the quoted code
rather than trusting the number.

The long-term goal is to improve the graphics substantially while preserving the
original gameplay, jump physics, controls and hill geometry exactly.

**Status**

| | |
|---|---|
| `129de57` | inspection baseline |
| `6411942` | fix `EInvalidOp` crash on startup with hardware rendering |
| `1ad3e2d` | untrack `MOREHILL.SKI` and user-created hills/cups/replays |
| `c382e54` | this document |
| `0f96125` | untrack player state, seed it from `defaults/`, add `build.sh` |
| `877109c` | remove commented-out dead code (1038 lines) |
| `4f341d1` | add `tools/verify-codegen.sh`, drop the one compound assignment |
| `5b9c1d4` | reformat the sources with `format.sh` |

Nothing in the rendering path has been changed yet.

---|---|
| `129de57` | inspection baseline |
| `6411942` | fix `EInvalidOp` crash on startup with hardware rendering |
| `1ad3e2d` | untrack `MOREHILL.SKI` and user-created hills/cups/replays |

Nothing in the rendering path has been changed yet.

---

## 1. Building and running

No Makefile, no `.lpi`, no configure step. One compiler invocation builds the
whole game; FPC resolves the unit graph itself.

```sh
sudo apt-get install fpc libsdl2-dev
./build.sh
```

`build.sh` clones the SDL2 Pascal headers on first run, seeds any missing save
file from `defaults/`, and then runs the compiler. The underlying command is:

```sh
fpc -Mtp -Fu./Pascal-SDL-2-Headers/ SJ3.PAS
```

The headers clone lives in the working tree and is gitignored. Verified against
`fpc 3.0.4` and `SDL2 2.0.10`: builds in ~1 s, 26 713 lines, 7 warnings and
2 notes, all pre-existing and benign (uninitialised locals in `SJ3REPL`/`SJ3.PAS`,
tautological `byte < 0` comparisons in `SJ3PCX`, an unset function result at
`SJ3UNIT.PAS:1293`).

Notes:

- `-Mtp` (Turbo Pascal mode) is load-bearing: it selects TP string semantics and
  operator behaviour. Do not drop it casually.
- `-Fu` points at an **unpinned external clone**. Nothing fixes its revision,
  which makes "identical to before" harder to prove than it should be. Worth
  pinning eventually.
- `ld.bfd: warning: link.res contains output sections` is a known FPC/binutils
  artefact on Linux and does not affect the binary.
- The binary must run with the asset directory as its CWD — every filename in
  the code is unqualified and relative.

### Tooling

| | |
|---|---|
| `./SJ3 --practice` | skip the menus, jump straight in on the first hill |
| `./SJ3 --frame-time` | report average and peak Render cost against the frame budget |
| `./SJ3 --hires-test` | overlay a test card proving the texture is really 1280x800 |
| `./SJ3 --no-hires` | render the original way; also how the pixel-identity check is run |
| `./SJ3 --no-hires-text`, `--no-hires-back` | disable one high-resolution layer |
| `./tools/makefont.py` | regenerate `FONTHI.DAT`, the high-resolution font atlas |
| `./build.sh` | clone headers if missing, seed save files from `defaults/`, compile |
| `./format.sh` | reformat all sources with ptop plus a cleanup pass |
| `./tools/verify-codegen.sh` | print a hash of the emitted assembly |
| `./tools/lower-keywords.py` | lowercase reserved words, skipping strings and comments |

`verify-codegen.sh` is the safety net for mechanical work. It compiles with
`fpc -Mtp -a` and hashes the 14 emitted `.s` files; any change that is supposed
to be behaviour-preserving must leave that hash alone. The current value is

    a6a8deecb4db26339170e370cad45a256934c8f6582e90bbcb09daeb71c23e14

It held unchanged at `368f333b...` across the dead-code removal and the
reformatting, proving those passes were pure no-ops. It moved deliberately when
`--practice` was added, since that commit adds real code; it moves again for any commit that adds
code, as the two render commits did. The value above is the current baseline.

It is not a formality. During the dead-code pass it caught two adjacent comment
blocks being spliced together, which swallowed the live line between them:

    if (cjumper) then writefont(x-Maki.X,y-Maki.Y-20,'C');

That still compiled. Only the hash noticed.

**ptop caveat.** ptop cannot parse FPC's compound assignment operators - it
rewrites `+=` as `+ =`, which fails to compile - so the sources deliberately
avoid them. There was exactly one, in `SDLPort.TimerCallback`. Two cosmetic
limitations remain: one-line `begin ... end;` blocks get reflowed onto separate
lines, and where the original wrote `end else foo;` on a single line the `else`
ends up indented to the enclosing `if` rather than its own.

### The repo directory is also the save directory

Running the game rewrites data files in the working tree. `CONFIG.SKI`,
`HISCORE.SKI` and `PLAYERS.SKI` are rewritten on exit, and playing generates
`*.SJR` replays.

They cannot simply be deleted either — `FileOk` halts the game at startup if
any of them is missing:

```
- Loading ANIM.SKI, HISCORE.SKISJ3 error:  Can't find file HISCORE.SKI. ...
```

Verified per file: `CONFIG.SKI`, `HISCORE.SKI` and `PLAYERS.SKI` all halt;
`MOREHILL.SKI` is regenerated by `CheckExtraHills`.

So the live files are **gitignored**, and pristine copies are tracked in
`defaults/`. `build.sh` installs any that are missing. This keeps player state
out of version control without breaking a fresh clone, and means playing the
game no longer dirties the working tree.

To reset to a clean slate:

```sh
rm -f CONFIG.SKI HISCORE.SKI PLAYERS.SKI MOREHILL.SKI && ./build.sh
```

---

## 2. Project layout

Everything is in one flat directory: sources, assets and the game's own mutable
save files side by side.

Sources are 16 `.PAS` files — one program and 13 units, plus two single-line
include stubs. They are Latin-1/CP437 encoded with Finnish comments, so plain
`grep` treats them as binary and silently reports nothing. **Use `grep -a`.**

**Assets (read-only at runtime)**

- `FRONT1-20.PCX` — hill foreground layers, 1024x512, 8-bit PCX
- `BACK0-4.PCX` — parallax backdrops, 1024x400
- `MAIN.PCX`, `LOAD.PCX` — full-screen 320x200 images
- `ANIM.SKI` — the whole sprite atlas: font glyphs, jumper poses, skis, logos,
  UI panels, in a bespoke run-of-bytes format
- `LANGBASE.SKI` — 600 localised strings across ~25 languages
- `HILLBASE.SKI`, `GOALS.SKI`, `NAMES0-2.SKI` — hill parameters, target
  distances, jumper name sets
- `INTRO.SJR` — the attract-mode replay

**Mutable state** — `CONFIG.SKI`, `HISCORE.SKI`, `PLAYERS.SKI`, `MOREHILL.SKI`,
plus user-created `*.SJH` (hills), `*.SJC` (custom cups), `*.SJR` (replays) and
a generated `SENDME.TXT`. All line-oriented text with checksum/obfuscation
fields.

---

## 3. Unit responsibilities

| Unit | Lines | Responsibility |
|---|---:|---|
| `SJ3.PAS` | 5936 | **Program.** Global game state and every mode of play. Contains `hyppy` (763-2790) — the entire jump: inrun, takeoff, flight physics, landing, scoring, replay capture. Also the competition drivers (`cup`, `teamcup`, `newkingofthehill`, `training`), menus, config/hiscore I/O, and `MAIN`. |
| `SJ3UNIT.PAS` | 3246 | **Game-data services.** Hill records and loading (`LoadHill`, `LoadInfo`, `hillfile`), hill maker/editor, menus (`MakeMenu`), text entry (`getstr`, `getch`), key binding, the `crypt`/`uncrypt` score obfuscation, injuries, coach commentary, info screens. |
| `SJ3INFO.PAS` | 2536 | **Player and cup metadata.** Profiles (`PLAYERS.SKI`), name sets, custom-cup files (`*.SJC`), hall-of-fame tables, welcome/language screen, main-menu backdrop (`drawmainmenu`), SENDME dump. |
| `SJ3REPL.PAS` | 680 | **Replay playback.** Enumerates `*.SJR`, validates the checksum, reconstructs positions from per-frame deltas, drives the transport (play, rewind, step, five speeds). Also plays `INTRO.SJR` as attract mode. |
| `SDLPORT.PAS` | 592 | **The whole platform layer.** Window, renderer, surfaces, texture, palette upload, frame pacing, and the DOS-style keyboard emulation mapping SDL keysyms back to BIOS `ch1`/`ch2` pairs. The *only* file that knows SDL exists. |
| `SJ3GRAPH.PAS` | 579 | **2D drawing on the `Video` byte array.** `Sprite`, `DrawAnim`, `LoadAnim`, `PutPixel`, `Fillbox`, `Box`, the bitmap-font renderer (`WriteFont`/`FontLen`/`fontcolor`), the tiled menu texture (`FillArea`), `NewScreen` layouts — and `DrawScreen`, the single presentation call. |
| `SJ3LIST.PAS` | 458 | **Results tables.** Paginated, column-configurable standings used by every competition screen. |
| `SJ3PCX.PAS` | 428 | **PCX loading and the 256-colour palette.** RLE decoder writing through the hill paging system, plus every palette mutation: suit and ski colours, logo tints, menu recolouring, snow darkening, brightness shading, save/restore. |
| `SJ3HELP.PAS` | 402 | **Non-graphical helpers.** Number/string formatting, a DOS-compatible `round`, signed `nsqrt`, keyboard-buffer flushing, and the global `ch`/`ch2` key variables the whole game reads. |
| `SJ3TABLE.PAS` | 301 | **Pure lookup tables.** Body angle to sprite index, ski angle to sprite index, landing-window heights, crash risk per hill angle. No state, no I/O — the tuning constants of the jump. |
| `MAKI.PAS` | 219 | **The hill** ("maki" = hill). Owns both big byte arrays — `Graffa` (hill graphics) and `Video` (the framebuffer) — the DOS page-flip emulation, the hill profile `ProfiiliY`, per-row solid-pixel extents `LinjanPituus`, camera `X`/`Y`, and `Tulosta`, which composites hill + parallax backdrop into `Video`. |
| `SJ3LANG.PAS` | 181 | **Localisation.** Loads `LANGBASE.SKI` into 600 heap strings; `lstr(n)` is called from nearly every screen. |
| `TUULI.PAS` | 142 | **Wind** ("tuuli" = wind). A bounded random walk in `tkulma` projected through a cosine to `value`, plus the on-screen gauge and its eight placement presets. |
| `LUMI.PAS` | 134 | **Snow** ("lumi" = snow). 256 flakes in 10.10 fixed-point, sinusoidal drift, camera-parallax coupling; writes into the framebuffer only over pixels whose palette index is in the backdrop range 64-214. |
| `REGSTAT.PAS`, `REGFREE.PAS` | 1, 2 | **Registration stubs**, `{$I}`-included. They gate the `REG` conditional. |

---

## 4. Startup to a ski jump

| Where | What |
|---|---|
| `SJ3.PAS:5728` | **MAIN.** Unit `Init`s in fixed order (lang, list, unit, wind, info, snow), `randomize`, date/time, version string `3.13-SP5`. |
| `SDLPort.Init` | SDL video + timer, 640x400 resizable window, renderer, three graphics objects, the 1 ms pacing timer. Close callback registered so the window X button still saves. |
| `SJ3.PAS:5608` `alku` | **Load everything.** `ANIM.SKI` to sprite atlas; hiscores; config; profiles; name set; language; hill scan; `Maki.Alusta` allocates `Graffa` (1 049 600 B) and `Video` (64 000 B). Progress goes to the terminal, not the window. |
| `SJ3.PAS:5545` `MainMenu` | First run only: welcome/language screen, then `INTRO.SJR` as attract mode. Then the menu loop — `drawfullmain` paints `MAIN.PCX`, `MakeMenu` blocks on input. |
| `SJ3.PAS:5501` `JumpMenu` | Six entries: World Cup, Custom Cup, Four Hills, Team Cup, King of the Hill, Training. Each sets the mode flags (`wcup`, `jcup`, `koth`, `treeni`, `cupstyle`) that `hyppy` later branches on. |
| `SJ3.PAS:4477` `training` | Shortest path to a jump: `selecthill` to `jumpalku` (`LoadInfo` fills `ActHill`, resets scores) to `Tuuli.Alusta` to `hyppy(1, NumPl+1, 0)`, looping until Esc. |
| `SJ3.PAS:768` `hyppy` | **The jump.** First call per hill (`eka`) rolls snowfall and calls `LoadHill`, which shows `LOAD.PCX`, decodes `FRONTn.PCX` and `BACKn.PCX` into `Graffa`, derives the profile via `LaskeLinjat`, and verifies a checksum against `ActHill.profile`. |
| loop 1 | **Info screen.** Cycles hill record / top-5 / World Cup standings until a key. Setup menu reachable here. |
| loop 2 | **On the bar.** Wind ticks, jumper idles, traffic light blinks; AI leaves on a random roll, player on the `K[2]` key. Bails out after 700 frames. |
| loop 3 | **Inrun, takeoff, flight, landing.** One iteration = one displayed frame = 10 ms of simulated time. Ends when `Height = 0`. Every frame appends 5 bytes to the replay buffer. |
| `SJ3.PAS:2106+` | **Scoring.** Distance from `distance`/profile geometry, five judge marks, crash roll, injury, hill-record check, profile stats, then results screens and the optional replay save. |

---

## 5. The rendering path

The port kept the DOS architecture intact. **All drawing is byte writes into one
flat 64 000-byte array of palette indices, and exactly one function ships that
array to the screen.** Nothing renders through SDL primitives. This is the most
important fact for the modernization: the entire game is already funnelled
through a single seam.

### 5.1 The buffer

`MAKI.PAS:23` declares `Video : array of byte`, allocated to 64 000 in `Alusta`.
It is not private — `SJ3Graph`, `Lumi`, `SJ3PCX` and `Maki` all index it
directly, always as `Video[y*320 + x]`. Each byte is a palette index 0-255.

`SJ3PCX` also reuses the same array as a decode staging area; see §6.4.

### 5.2 Hill composition

`MAKI.PAS:83` `Tulosta` calls
`KopioiMaki(Y*XSize, Alue - (X shr 1) - (Y shr 1)*XSize)`.

For each of 200 rows and 320 columns it copies one byte from `Graffa`. Where the
column has passed `LinjanPituus[row]` — the rightmost non-zero pixel of that
hill row — it adds `delta`, which jumps into the backdrop stored at offset
`Alue` and scrolls it at **half** the camera rate. That subtraction-based offset
*is* the parallax, and it is exact integer arithmetic tied to 1024 and 512.

### 5.3 Sprites, snow, text

- `SJ3GRAPH.PAS:182` `Sprite` — width and height come from a 4-byte header
  inside the sprite; index 0 is transparent; clipped only on the right
  (`X+xindex < 320`), never on the left or bottom.
- `SJ3GRAPH.PAS:204` `DrawAnim` — applies the per-sprite hotspot from `AnimP`,
  then rejects the whole sprite unless `0 <= x < 320` and `0 <= y < 200-ysize`.
  Sprites pop rather than clip at screen edges; that is original behaviour.
- `SJ3GRAPH.PAS:235` `LoadAnim` — reads `ANIM.SKI`; after sprite 83 it
  synthesises 12 vertically mirrored ski sprites.
- `LUMI.PAS:38` `Update` — 10.10 fixed-point flakes, guarded by the magic bound
  `offset < 63679` and by the backdrop palette window 64-214, so snow falls
  behind the hill without any depth test.
- `SJ3GRAPH.PAS:342` `DoFont` — text is sprites. Glyphs are atlas entries 1-60,
  and `fontcolor` permanently rewrites those sprites' pixel bytes.
- `SJ3GRAPH.PAS:447` `FillArea` — the tiled 19x13 pattern behind menu panels,
  keyed off palette indices 243-245.

### 5.4 Palette

`SJ3PCX` keeps the master palette as 6-bit VGA values (0-63), the format PCX
files store and the format every recolour routine assumes. `AsetaPaletti` pushes
it to `SDLPort.SetPalette`, which does `value shl 2` per channel and calls
`SDL_SetPaletteColors` on the 8-bit surface.

Palette changes are therefore **deferred** — they take effect on the next frame
that calls `AsetaPaletti`, exactly like a VGA DAC write.

> `shl 2` maps 6-bit 63 to 252, not 255, so the palette is very slightly dark.
> Real VGA hardware behaved this way too. **Leave it alone for milestone 1** —
> changing it would break pixel-identity with the current baseline. Revisit only
> as a deliberate, separately-flagged colour decision.

### 5.5 Presentation

`SJ3GRAPH.PAS:43` is the entire public presentation API:

```pascal
Procedure DrawScreen;
begin
 SdlPort.WaitRaster;      { block until the next 70 Hz tick }
 SdlPort.Render(Video);   { push 64 000 bytes to the screen }
end;
```

Called from roughly a hundred sites. `DrawHillScreen` is `Maki.Tulosta` +
`DrawScreen`.

### 5.6 `SDLPort.Render`

`SDLPORT.PAS:249`. Four hops per frame:

1. `Move(buffer, originalSurface^.pixels^, Sizeof(buffer))` — a raw 64 000-byte
   memcpy into the 8-bit surface. `SizeOf` on an open-array parameter returns
   the true runtime size in FPC (confirmed: 64 000). This works only because
   320 is 4-byte aligned, so SDL's surface pitch equals 320 with no padding.
2. `SDL_BlitSurface` — 8-bit indexed to 32-bit, applying the palette.
3. `SDL_LockTexture` + `SDL_ConvertPixels` to an `SDL_PIXELFORMAT_RGBA8888`
   streaming texture.
4. `SDL_RenderCopy(renderer, displayTexture, nil, @renderDestRect)` +
   `SDL_RenderPresent`.

### 5.7 Texture creation and final scaling

All three graphics objects are created once in `Init` at 320x200: an 8-bit
surface, a 32-bit surface, and a streaming RGBA8888 texture. Scaling happens
entirely in the last `SDL_RenderCopy`, via `renderDestRect`.

`SDLPORT.PAS:108` `GetRenderRect` letterboxes: it queries
`SDL_GetRendererOutputSize` and fits a rect of ratio `aspect` — `1.6` by
default, `4/3` after Alt+A — centred in the window. It is recomputed only when
`windowResized` is set, which `KeyPressed` sets on `SDL_WINDOWEVENT_RESIZED`.

**Three things the current code gets right by accident:**

- **Filtering.** No `SDL_HINT_RENDER_SCALE_QUALITY` is ever set, so SDL's
  default of nearest-neighbour applies. Proven empirically: a captured 640x400
  window downsampled to 320x200 and back up is pixel-identical to the capture,
  and the frame contains only 205 distinct colours. Correct today, but
  undeclared — any environment that sets that hint globally would silently blur
  the game.
- **Integer scale.** Default `windowMultiplier = 2` gives a 640x400 window whose
  ratio is exactly 1.6, so `GetRenderRect` happens to return a full-window rect
  and the scale is exactly 2x. Resize by a single pixel and it stops being
  integral — some source pixels become 3 screen pixels wide, their neighbours 4.
- **Letterbox colour.** `SDL_RenderClear` is called without ever setting a draw
  colour, so the bars are whatever SDL's default happens to be.

---

## 6. Hard-coded assumptions

Grouped by what they actually mean — several look like the same constant and
are not.

### 6.1 `320` — the framebuffer stride

| Location | Form | Note |
|---|---|---|
| `SDLPORT.PAS:30` | `xRes = 320` | The only named constant. Everything else is a literal. |
| `SJ3GRAPH.PAS:197` | `Video[X+xindex+(Y+yindex)*320]` | Sprite blit. |
| `SJ3GRAPH.PAS:317, 333` | `video[(y1*320)+x1]` | `PutPixel`, `GetPixel`. |
| `SJ3GRAPH.PAS:473-484` | `(temp1*320)+temp2`, `mod 320`, `div 320` | `FillArea` derives tile phase from the linear offset — stride and layout are entangled. |
| `SJ3GRAPH.PAS:503` | `video[xx + yy shl 8 + yy shl 6]` | **Disguised.** 256+64 = 320. A stride change that misses this silently corrupts every filled box. |
| `MAKI.PAS:66` | `for x_index := 0 to (320 - 1)` | Hill composite width. |
| `LUMI.PAS:55, 66, 67` | `(Y shr 10)*320`, `offset+320` | Snowflake plotting, including the 2x2 flake's second row. |
| `LUMI.PAS:91` | `random(320) shl 10` | Spawn width. |

### 6.2 `200` — the framebuffer height

- `SDLPORT.PAS:31` — `yRes = 200`
- `MAKI.PAS:61` — `for y_index := 0 to (200 - 1)`, hill composite height
- `SJ3GRAPH.PAS:222` — `y < 200-ysize`, the sprite reject test
- `SJ3GRAPH.PAS:313` — `y >= 0 and y < 200`, `PutPixel` clip
- `LUMI.PAS:92` — `random(200) shl 10`, snow spawn height
- `SJ3UNIT.PAS:583`, `SJ3INFO.PAS:2407` — `320*200` as the PCX pixel count for
  `LOAD.PCX` and `MAIN.PCX`

Also note **319 and 199** as inclusive clip bounds: 18 occurrences in
`SJ3GRAPH.PAS` alone (every `NewScreen` layout) and about 20 more across
`SJ3UNIT`, `SJ3INFO`, `SJ3REPL`, `SJ3LIST`, `SJ3.PAS`. These are layout
coordinates, not stride — for milestone 1 they stay exactly as they are.

### 6.3 `64000` — the buffer size

- `MAKI.PAS:181` — `setLength(Video, 64000)`, the only live one
- Implicitly, `SizeOf(buffer)` in `SDLPORT.PAS:264` and `length(video)` in
  `WriteVideo`
- `LUMI.PAS:56` — `offset < 63679`, **the magic number**. It is
  64000 - 320 - 1, the last offset at which a 2x2 flake can write
  `offset+320+1` without running off the end. It reads as arbitrary and will not
  survive a naive resize.
- Dead references: `SJ3REPL.PAS:504, 533, 534, 674` and `SJ3GRAPH.PAS:81` are
  all inside comments — DOS `mem[seg:ofs]` code that no longer compiles.

### 6.4 `1024 x 512` — the hill graphics

This is a **separate coordinate system** from the screen, and it is the world
space the physics runs in.

| Location | Form | Meaning |
|---|---|---|
| `MAKI.PAS:7-11` | `XSize=1024; YSize=512; Alue=XSize*YSize; Sivuja=16; SivuKoko=Alue div Sivuja` | 524 288-byte hill plane, split into 16 pages of 32 768 — the DOS VGA page-flip emulation, preserved. |
| `MAKI.PAS:180` | `setLength(Graffa, Alue*2+1024)` | 1 049 600 B: foreground at 0, backdrop at `Alue`. |
| `MAKI.PAS:17-18` | `LinjanPituus[0..511]`, `ProfiiliY[0..1300]` | Row extents sized to `YSize`; the profile is over-allocated to 1300 and padded past 1024 in `LaskeLinjat`. |
| `SJ3UNIT.PAS:610` | `LataaPCX('FRONT...', 1024*512, 0, 0)` | Foreground, pages 0-15. |
| `SJ3UNIT.PAS:623` | `LataaPCX('BACK...', 1024*400, Maki.Sivuja, ...)` | **400, not 512.** The backdrop is shorter and starts at page 16. |
| `SJ3UNIT.PAS:1122` | `1024*512` | Same load inside the hill maker. |
| `SJ3PCX.PAS:340` | `if (x<0) then x := 1024+x` | Backdrop horizontal mirror wrap. |
| `SJ3.PAS:1297` | `until (x > 1024)` | Marker-placement scan across the hill. |
| `SJ3.PAS:1997-2003` | `x>=160 .. x<864`, `y>=100 .. y<412`, `Maki.X>704`, `Maki.Y>312` | Camera limits — 1024-320 = 704 and 512-200 = 312. **These couple world size to screen size** and are the one place the two systems meet. |

> **The coupling that will surprise you.** `LataaPCX` (`SJ3PCX.PAS:332`) decodes
> *through* `Video`: it fills `Video[0..SivuKoko-1]`, calls
> `PaivitaKirjoitusSivu` to flush 32 768 bytes into `Graffa`, then wraps and
> repeats. So the 320x200 framebuffer is also the PCX scratch page, and
> full-screen images like `MAIN.PCX` are loaded into `Graffa` pages 0-1 and
> copied back with `WriteVideo`. This works only because
> 64 000 <= 2 x 32 768. **Any change to the size of `Video` silently breaks PCX
> loading**, in a way that will look like a graphics-corruption bug.

---

## 7. Subsystem map

### 7.1 Jump physics

All of it is inline in `hyppy`, `SJ3.PAS:1663-2090`. There is no physics unit.
State: `distance` (from takeoff), `posY` (absolute height), `dropY` (drop below
the takeoff edge), `height` (clearance above the hill), `px`/`py` (velocity),
`lift` (glide), `t` (time), `bodyAngle`, `skiAngle`, and `skiSwing` (the
ski-swing state machine, 1-6).

These twelve confusable locals were renamed from Finnish; the rest of the
codebase is still Finnish. `laskuri` was left alone deliberately - it is reused
inside `hyppy` for three unrelated counters, so any specific English name would
misdescribe two of them.

- **Integration** — `1666` `distance := distance + (px*0.01)`; `1784` `t := t + 0.01`;
  `1816` `posY := posY + (t*t*lift) - ((py-8)/100)`. Fixed 10 ms step, one step per
  rendered frame.
- **Drag and wind** — `1774-1777`, the tuned `px`/`lift` update using
  `nsqrt(4*wind+245)`.
- **Inrun acceleration** — `1958` `px := px * pxk` with `pxk = 1.016`, clamped
  to `maxspeed` (`ActHill.vxfinal`, +/-(startgate-15) in training).
- **Takeoff** — `1967-1992`: `takeoff` counts frames since the jump key;
  16 is perfect; early/late sets `skiSwing` and penalises `lift`.
- **Gusts** — `1783-1813`, probability from `Tuuli.windy` and `Tuuli.voim`.
- **Scoring and crash risk** — `2091-2187`, with the tables in `SJ3TABLE.PAS`.
- **AI** — `1712-1762`: `skill`/`reflex` derived from the jumper index,
  synthesising key events rather than bypassing the input path.

### 7.2 Hill collision and profile

- `MAKI.PAS:109` `LaskeLinjat` — scans the 1024x512 foreground once per hill
  load. Builds `LinjanPituus` (rightmost solid pixel per row), then
  `ProfiiliY[x]` (first solid row per column), finds the takeoff edge `KeulaX`
  by looking for a >3-pixel drop, and burns the K-point/HS markers into `Graffa`
  as palette indices 238/239.
- `MAKI.PAS:97` `Profiili(x)` — the terrain query, guarded to `0 < x < 1300`.
- `SJ3.PAS:831` `MakiKulma(x)` — local slope as a finite difference over samples
  at x-5..x+9, zeroed in a 15-pixel window before `KeulaX`.
- **Ground contact** — `SJ3.PAS:1907` `height := Profiili(x) - round(posY)`, and
  landing when `Height = 0` (`1920`). Collision is a per-column height test against a
  bitmap-derived profile, nothing more.
- **Integrity check** — `SJ3UNIT.PAS:613-619` hashes `Profiili` over 1024
  columns and compares against `ActHill.profile`. Change the profile derivation
  in any way and every stock hill fails this check.

### 7.3 Frame timing

- `SDLPORT.PAS:85` `TimerCallback` — an `SDL_AddTimer` at 1 ms; accumulates
  elapsed time and increments `frameCount` once per 14 ms
  (`1000 div targetFrames`, `targetFrames = 70`). Effective rate ~71.4 Hz.
- `SDLPORT.PAS:286` `WaitRaster` — spins on `SDL_Delay(1)` until `frameCount`
  changes. Named for the VGA vertical retrace it replaces.
- `SDLPORT.PAS:701` `Wait` — `msPerTick = 1000/18.2065`, the IBM PC PIT tick,
  for legacy `Wait(n)` callers.

> **Timing is gameplay.** The simulation advances exactly one 10 ms step per
> rendered frame. No decoupling, no delta time, no accumulator. Changing the
> frame rate changes the physics — and would invalidate every stored replay,
> which is a byte stream of per-frame deltas.

### 7.4 Player input

- `SDLPORT.PAS:295` `KeyPressed` — drains the SDL queue, ignores modifier and
  lock keys to match DOS behaviour, and *re-pushes* the triggering event so the
  following `WaitForKeyPress` can consume it.
- `SDLPORT.PAS:357` `WaitForKeyPress` — 250 lines translating SDL keysyms into
  BIOS `ch1`/`ch2`: Shift/CapsLock case folding, US-QWERTY shifted punctuation,
  NumLock-off keypad remapping, keypad/main merging, CP865 Nordic characters,
  F-keys and cursor keys as scancodes. Also owns the port's own shortcuts
  (Alt+Enter, Alt+/-, Alt+R, Alt+A), handled *before* the game sees the key.
- `SJ3HELP.PAS:5` — the global `ch`, `ch2` that the whole game reads.
- `SJ3UNIT.PAS:1859` `kword` — packs the pair into a word for comparison against
  bindings `K[1..5]` (jump, forward/left, back/right, telemark, both feet),
  configured in `ConfigureKeys` and stored in `CONFIG.SKI`.

### 7.5 Replays and saved data

- **Capture** — `SJ3.PAS:2046-2053`, inside the draw block: 5 bytes per frame
  into `RD[0..4, 0..1000]` — dx+128, dy+128, jumper sprite, ski sprite,
  wind+128. Capped at 1001 frames. Only recorded when `draw` is true.
- **Write** — `SJ3.PAS:1059` `writereplay` — a text header (start position, turn
  count, hill id and file, profile hash, snow amount, distance, flight window,
  marker positions, suit/ski colours, author, name, timestamp, mode), then a
  checksum `xor 3675433`, then `'*'`, then 5x1001 raw bytes.
- **Playback** — `SJ3REPL.PAS:36` `playreplay` — integrates the deltas back into
  absolute positions, replays sprite indices verbatim. **Replays store sprite
  indices, not physics.** That is why sprite numbering in `ANIM.SKI` is part of
  the save format.
- **Other saves** — `WriteConfig`/`ReadConfig` (`SJ3.PAS:144, 368`),
  `WriteRecords`/`ReadRecords` (`89, 284`), profiles (`SJ3INFO.PAS:1123, 1210`),
  extra-hill records (`SJ3UNIT.PAS:2130, 2142`). All obfuscated by
  `crypt`/`valuestr` (`SJ3UNIT.PAS:2578+`). The README states config files are
  interchangeable with the DOS original.

---

## 8. What must not change

**Frozen during graphics modernization:**

- `SJ3TABLE.PAS` — pure tuning tables; any edit changes how jumps score.
- `SJ3.PAS` 763-2790 (`hyppy`) — physics, input handling, replay capture.
- `TUULI.PAS` — the wind random walk feeds the physics; even reordering its
  `random()` calls changes outcomes.
- `MAKI.PAS` 92-188 (`Profiili`, `LaskeLinjat`) — the hill profile and the
  checksum every stock hill is validated against.
- `SJ3REPL.PAS` and `SJ3.PAS:1059` (`writereplay`) plus the `RD[]` writes —
  replay format compatibility.
- Save/load: `WriteConfig`, `ReadConfig`, `WriteRecords`, `ReadRecords`,
  `crypt`/`uncrypt`/`valuestr`, profile I/O.
- All `.PCX`, `.SKI`, `.SJR` assets — art replacement is a later milestone with
  its own compatibility story.

**Handle with care** — graphics code that carries gameplay or format weight:

- `SDLPORT.PAS` `TimerCallback`, `WaitRaster`, `targetFrames` — timing is
  physics.
- `SDLPORT.PAS` `WaitForKeyPress`, `KeyPressed` — input semantics.
- `MAKI.PAS` `Video` length, `SivuKoko`, `PaivitaKirjoitusSivu` — the PCX loader
  depends on these.
- `SJ3GRAPH.PAS` `Fillbox`'s `shl 8 + shl 6` — disguised stride.

**Fair game for milestone 1:** `SDLPORT.PAS` — window creation, renderer flags,
`GetRenderRect`, `ResetWindowSize`, `windowMultiplier`, `Render`'s SDL calls,
and SDL hints. The entire scaling change belongs there.

---

## 9. Dead code

The commented-out code is gone, removed in `877109c`: 1038 lines across 13
units. Superseded implementations (an earlier `LaskeLinjat`, `HillEditor`,
`startsuit`, a syntactically broken `KorostaTeksti`), DOS-era leftovers
(`mem[seg:ofs]` blits, `Intr($16)` and inline-assembler `ReadKey` variants,
`Port[$3c8]` DAC writes, COMSPEC file deletion), debug scaffolding, stale
sound-card configuration I/O, and dead declarations.

Prose comments were kept, Finnish included. Three things were kept
deliberately:

- the physics tuning history in `hyppy`, marked `{ orig. }`, `{ "alkup." }` and
  `{ vanha }`, which records the constants the live formulas replaced;
- the alternative FIS scoring formula, a documented design alternative;
- explanations that only existed inside dead code. In `LUMI` the commented-out
  constants were the sole documentation of `PerusG`, `GVaihtelu` and
  `SivuLiike`, so those notes moved onto the live declarations.

### Still live, still unreachable

Removing the commented-out callers left a few routines with no callers at all.
They are real code, not comments, so they were left alone - deleting them is a
separate decision.

| Symbol | Note |
|---|---|
| `Balk` | Empty stub in the port; every call site was commented out. |
| `GetPixel`, `PutGPixel` | Implemented, never called. |
| `NumofAnims` | Exported; its only call site was commented out. |
| `HillEditor` | 66 lines, superseded by `HillMaker`. |
| `AsetaMoodi` | Empty no-op still called ~12 times - vestigial VGA mode switching. |
| `Lopeta` | Empty; called once. |
| `HexW` | Local hex formatter, no callers. |
| `pluspossibility` | Its only caller was a commented-out line in `SJ3LIST`. |

### Still-live DOS dependencies

`SJ3HELP`, `SJ3UNIT` and `SJ3.PAS` still `uses crt, dos`. FPC provides both, and
the game genuinely calls `sound`/`NoSound` in `beep`, plus
`textcolor`/`window`/`clrscr` for terminal output on the way out, and
`Crt.KeyPressed` in the exit wait loop.

Under SDL the PC-speaker calls are no-ops - **the game currently has no audio at
all.** Worth a later milestone; out of scope for graphics.

### A pre-existing bug, noticed but not fixed

`lopputext` picks its parting quote with `case random(40)`, which yields 0..39,
so the branch numbered 40 can never be selected. Fixing it changes behaviour, so
it belongs in its own commit.

## 10. Milestone 1 — 1280x800 with exact 4x4 pixel blocks

| Requirement | How it is met |
|---|---|
| Logical resolution stays exactly 320x200 | Untouched. `xRes`/`yRes`, all three SDL graphics objects and the 64 000-byte buffer are unchanged. |
| World/gameplay coordinates unchanged | Nothing outside `SDLPORT.PAS` is modified. |
| Every old pixel is an exact 4x4 block | Snap the destination rect to an integer factor, then make that factor 4 at the default window size. |
| Output 1280x800 | 320x4 = 1280, 200x4 = 800. |
| Visually identical to the original | Verified by pixel comparison against golden frames. |
| No interpolation or smoothing | Already true by SDL default; make it explicit and driver-independent. |
| Physics, timing, controls, hills, replays, saves unchanged | None of those files are in the diff. `targetFrames` stays 70, the 10 ms step stays coupled to the frame, key translation untouched, no file format read or written differently. |

### Verification method

```sh
# capture the running window (baseline: 640x400 at 2x)
import -window root shot.png
convert shot.png -crop 640x400+X+Y +repage win.png

# the scaling must be an exact integer replication
convert win.png -sample 320x200 -sample 640x400 rt.png
compare -metric AE win.png rt.png null:      # must print 0

# after the change, at 4x, the same test against the golden frame
convert win_1280x800.png -sample 320x200 +repage got.png
compare -metric AE golden_320x200.png got.png null:   # must print 0
```

`-sample` does point sampling with no filtering, so a zero absolute error proves
the on-screen image is an exact block replication of a 320x200 frame. On the
current build this test already passes at 2x.

> **One decision worth making explicitly.** The DOS original ran on a 4:3
> display, so its 320x200 pixels were *non-square* (1:1.2). The port defaults to
> square pixels and offers 4:3 behind Alt+A. 1280x800 is square-pixel and
> geometrically identical to the current default, so nothing changes — but
> "visually identical to the original" is true against **this port's default**,
> not against a period-correct CRT. Period-correct aspect is fundamentally
> incompatible with exact integer pixel blocks and would need its own milestone.

---

## 11. Proposed commit sequence

Each commit builds and runs on its own.

**Done**

1. ~~Mask FP exceptions before `SDL_Init`~~ — `6411942`
2. ~~Untrack files the game rewrites~~ — `1ad3e2d`, `0f96125`
3. ~~Add a codegen verification harness~~ — `4f341d1`
4. ~~Remove commented-out dead code~~ — `877109c`
5. ~~Reformat the sources~~ — `5b9c1d4`

**Remaining**

6. **Pin the SDL2 headers.** Partly done - `build.sh` wraps the compile and
   fetches the headers, but it still clones `Pascal-SDL-2-Headers` at whatever `HEAD` happens to be. Vendor it as
   a submodule at a fixed commit, or check in the files actually needed, and
   update the CI workflow to match. An unpinned third-party clone in the build
   path makes "visually identical to before" unprovable.
7. **Add a frame-capture and pixel-compare harness.** A script that launches the
   game, drives a fixed key sequence, captures the window with `import`, and
   compares against golden PNGs with `compare -metric AE`. Cover at least: main
   menu, hill-select, the info screen, mid-flight, and the results table. This
   is what makes "visually identical" checkable rather than eyeballed.

   Input can be injected with XTEST (`python-xlib`), which drives the real SDL
   event path, so a scripted run reaches the same frame every time. Note that
   `defaults/CONFIG.SKI` has `languagenumber = 255`, which sends a fresh run
   through the welcome screen and the `INTRO.SJR` attract mode before the main
   menu — the harness has to either click through that or start from a config
   with a language already chosen.

   Default key bindings (`CONFIG.SKI` lines 33-37, matching `DefaultKeys`):
   Up = take off, Right = leave the bar / lean forward, Left = lean back,
   T = telemark, R = both feet.

**Milestone 1**

8. ~~**Declare nearest-neighbour scaling explicitly.**~~ Done.
   `SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, '0')` before creating the
   renderer. No visible change — turns an accidental default into a guarantee.
9. ~~**Set an explicit clear colour for the letterbox.**~~ Done.
   `SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255)` before `SDL_RenderClear`.
10. **Snap the destination rect to an integer scale factor.** Rework
   `GetRenderRect` so that in square-pixel mode it computes
   `scale := min(outW div 320, outH div 200)`, clamps to at least 1, and centres
   a `320*scale x 200*scale` rect. Every source pixel becomes an exact
   `scale x scale` block at any window size, with letterboxing absorbing the
   remainder. Keep the existing fractional path for the Alt+A 4:3 mode.
11. **Default to a 4x window (1280x800).** `windowMultiplier := 4`, with a guard
   that steps down if the display cannot hold it.
12. **Handle HiDPI and size-changed events correctly.** Also listen for
   `SDL_WINDOWEVENT_SIZE_CHANGED`, not only `RESIZED` (the former fires for
   programmatic resizes, which is what Alt+/- does), and rely on
   `SDL_GetRendererOutputSize` rather than window size so a HiDPI backing scale
   does not produce a fractional factor.

**After the milestone is verified green**

13. **Name the framebuffer geometry constants.** Introduce `ScreenW = 320`,
    `ScreenH = 200`, `ScreenBytes = ScreenW*ScreenH` in `Maki` and replace the
    literal stride arithmetic in `SJ3GRAPH`, `LUMI` and `MAKI` — including the
    `shl 8 + shl 6` in `Fillbox` and the `63679` in `LUMI`, which becomes
    `ScreenBytes - ScreenW - 1`. Strictly a no-op refactor, verified by the
    harness from step 7. Leave layout coordinates (319, 199, panel positions) as
    literals — they are content, not geometry.

---

## 12. The high-resolution backdrop

The backdrop is resampled to `pixelScale` resolution and
samples it per texture pixel, instead of expanding it into blocks like
everything else. It is the first layer to get real detail, chosen because
`LaskeLinjat` never reads it: the backdrop is purely decorative, so smoothing
it cannot affect the hill profile, the profile checksum, or the physics.

The foreground is a different problem. It is both the art and the collision
surface, and a naive smooth upscale blurs the snow-against-sky silhouette,
which is the visual ground line. Doing it properly means smoothing the interior
while rebuilding the edge from the original transparency mask - scriptable, but
not done here.

### How overlays survive

`Maki.Tulosta` now copies the freshly composited frame into `VideoBase`.
Anything that differs from it later is something the game drew - sprites, snow,
text - and is expanded into blocks as before. Only untouched backdrop pixels
are replaced by resampled ones. No game code changed.

### Limitations

Worth knowing before relying on this.

- **Memory.** The resampled backdrop is 4096x1600 in finished colours, about
  25 MB, rebuilt whenever the hill changes.
- **Cost is unmeasured.** The layered path cannot use the row-copy shortcut the
  plain expansion relies on, because pixels differ within a 4x4 block, so it is
  certainly slower. How much slower has not been measured - run
  `--hires-back --frame-time` and compare against `--frame-time` alone.
- **Layering.** `SDLPort` now `uses Maki` so it can read the camera, the row
  extents and the frame snapshot. That is the platform layer reaching into game
  state, and should be tidied if this becomes permanent.
- **Overlay detection is a heuristic.** A pixel the game draws that happens to
  equal the backdrop pixel underneath it is not detected. It would be the same
  colour either way, so it is invisible in practice, but it is a comparison of
  values rather than a record of what was drawn.
- **Colours, not indices.** Palette indices cannot be interpolated, so the
  resampled backdrop holds finished colours. That is safe only because the
  range it uses, 64..214, is modified just once per hill by `SavytaPaletti`.
  It is rebuilt whenever those entries change - which is also the fix for a bug
  found here: `LoadHill` leaves the previous hill's palette in place until the
  game calls `AsetaPaletti`, which happens after the first frame is drawn, so
  keying the rebuild off the hill alone resampled through the wrong palette.
  If anything ever animates that range per frame, the backdrop would rebuild
  every frame and the game would crawl.
- **Smoothing is a taste decision.** Bilinear resampling softens art that was
  drawn pixel by pixel. It suits these backdrops, which are painterly already,
  but it is not automatically the right answer for every asset.

## 13. High-resolution text

Text is drawn from `FONTHI.DAT`, a font baked to texture resolution
by `tools/makefont.py`, instead of expanding the original glyphs into blocks.

The original font could not simply be sharpened. Its glyphs are six pixels
tall, and upscaling cannot invent detail that was never there - an EPX pass was
tried first and gained almost nothing, because the letterforms are almost
entirely axis-aligned strokes and EPX only rounds diagonal corners. Getting
genuinely crisp text meant new glyph data.

Advance widths still come from the original glyphs in `ANIM.SKI`, so `FontLen`,
right-aligned text and every existing screen position are unchanged. Only the
shapes drawn inside those advances differ.

`WriteFont` queues glyphs rather than drawing them, and `SDLPort` runs the queue
through an overlay callback after the frame has been expanded, while the
texture is still locked. That is also the general mechanism for drawing
anything at texture resolution: `PlotHiIndex` writes a palette colour,
`PlotHiBlend` mixes one in by coverage.

Regenerate the atlas after changing the typeface or `pixelScale`:

```sh
python3 tools/makefont.py
```

The generator needs Pillow, but only when run; the game just loads the result.
If `FONTHI.DAT` is missing or was built for a different scale, the game says so
and falls back to drawing text the original way.

### The queue has to outlive the frame

Text is queued rather than drawn, and the obvious implementation - clear the
queue once it has been rendered - is wrong. `givech` spins on `DrawScreen` to
blink its cursor without rewriting anything, so every frame after the first
came out with no text at all; the main menu rendered completely blank. It was
invisible in practice mode only because the jump loop happens to rewrite its
text every frame.

So the queue is cleared when the frame is genuinely rebuilt, not when it is
drawn: `Maki.Tulosta` bumps `FrameSerial` for hill frames, and a full-screen
`Fillbox` or `WriteVideo` clears it for menus. That also lets `givech` append a
character to text that is already on screen, which is what it expects to do.

### The outline is reproduced

The original font is two-tone: a body colour plus a dark outline in palette
index 242, which is what keeps the HUD legible over a bright sky. The atlas
stores both as separate coverage channels - the generator dilates the glyph and
keeps what falls outside it - and the runtime draws outline first, body over.

### It is a different typeface

Not the original at higher resolution. `FONTHI.DAT` is currently DejaVu Sans
Bold, a modern grotesque, where the original is a condensed pixel face. That
was the unavoidable consequence of needing real glyph data. If the original
identity matters more than sharpness, the alternative is to redraw the 59
glyphs by hand at `pixelScale` - the one option here that needs drawing effort.

## 14. Open questions for milestone 2

**Where does higher-resolution art live?** The current architecture gives one
lever: the `Video` buffer's dimensions. Raising them means raising the hill
plane too (`Graffa`, `LinjanPituus`, `ProfiiliY`, the camera clamps), which
means regenerating every hill profile — and every stock hill's stored profile
checksum, plus every existing replay. That is a save-format break and needs to
be a deliberate, announced decision rather than a side effect.

**Or does new art render *over* the 320x200 layer?** The alternative is to keep
the simulation and its buffer exactly as they are and add a higher-resolution
presentation layer — sprites and hill art drawn at native resolution into a
second, larger target, driven by the same world coordinates. It preserves every
format and every physics guarantee, at the cost of maintaining two drawing
paths. Given how much of this codebase's value is in its exact, tuned behaviour,
this is probably the direction to explore first.
