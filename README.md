# 4d-plugin-capture-with-preview

The `Capture` plugin shows a live webcam preview inside a 4D form window on Windows and takes still pictures from it. On Windows it drives **DirectShow** — a capture filter graph whose video window is parented into the 4D window — enumerating the devices with `ICreateDevEnum`, rendering the preview through a `SampleGrabber`, and building a 24-bit BMP from the grabbed RGB24 frame. Snaps come back as a 4D `Picture` (BMP), the device list as an `ARRAY TEXT`.

The plugin manages one preview context per camera device; creating a preview for a device that already has one returns the existing preview id. There is no macOS implementation: the commands are Windows-only (see [Requirements & platform notes](#requirements--platform-notes)).

| Command | Returns | Purpose |
|---|---|---|
| [`CAPTURE DEVICE Get default`](#capture-device-get-default) | `Text` | Name of the first enumerated capture device |
| [`CAPTURE DEVICE LIST`](#capture-device-list) | `ARRAY TEXT` | Names of all capture devices |
| [`CAPTURE PREVIEW Create`](#capture-preview-create) | `Longint` | Create a preview for a device, returns its id |
| [`CAPTURE PREVIEW SET WINDOW`](#capture-preview-set-window) | — | Parent the preview into a 4D window |
| [`CAPTURE PREVIEW SET RECT`](#capture-preview-set-rect) | — | Position and size the preview inside the window |
| [`CAPTURE PREVIEW GET RECT`](#capture-preview-get-rect) | — | Read back the preview position and size |
| [`CAPTURE PREVIEW SET VISIBLE`](#capture-preview-set-visible) | — | Show/hide the preview (starts/stops the graph) |
| [`CAPTURE PREVIEW Get visible`](#capture-preview-get-visible) | `Longint` | Is the preview visible (`1`) or not (`0`) |
| [`CAPTURE PREVIEW SNAP`](#capture-preview-snap) | `Picture` | Take a still picture from the running preview |
| [`CAPTURE PREVIEW CLEAR`](#capture-preview-clear) | — | Release the preview and its DirectShow graph |
| [`CAPTURE PREVIEW Get window`](#capture-preview-get-window) | `Longint` | Window ref last passed to `SET WINDOW` |

**Platforms:** Windows. The `Capture.vcxproj` defines both Win32 and x64 configurations, but the release workflow builds **x64** only and ships `Contents/Windows64/Capture.4DX`. There is no macOS implementation — the macOS universal binary produced by the release workflow is a stub.

---

## Requirements & platform notes

- **Failure is silent.** No command raises a 4D error. When something is missing (no camera, a bad preview id, no grabbed frame), the command returns an empty/default value: [`CAPTURE PREVIEW Create`](#capture-preview-create) returns `0`, [`CAPTURE PREVIEW SNAP`](#capture-preview-snap) returns an empty picture, [`CAPTURE DEVICE Get default`](#capture-device-get-default) returns an empty string.
- **The preview is a native child window, not a form object.** 4D does not move, resize, clip or hide it for you. Use [`CAPTURE PREVIEW SET RECT`](#capture-preview-set-rect) when the form is resized, and call [`CAPTURE PREVIEW CLEAR`](#capture-preview-clear) when the form closes (see [`CLEAR`](#capture-preview-clear) for the teardown pattern used by the test form).
- **Coordinates are Windows-client-relative.** Rectangles passed to [`CAPTURE PREVIEW SET RECT`](#capture-preview-set-rect) are measured from the **top-left** corner of the 4D window's client area. The test form derives them from `OBJECT GET COORDINATES` on a form area, so they track the form layout in pixels.
- **The plugin needs a window parent first.** [`CAPTURE PREVIEW SET WINDOW`](#capture-preview-set-window) must be called before the preview can be shown; pass `0` to reparent to the 4D MDI window instead of a specific form window.
- **Snaps need the preview to be running.** Frames are only buffered while the preview is visible ([`CAPTURE PREVIEW SET VISIBLE`](#capture-preview-set-visible) with `1`). Calling [`CAPTURE PREVIEW SNAP`](#capture-preview-snap) on a hidden preview returns an empty picture.
- **Threads.** All commands are declared thread-safe in `manifest.json`, but the plugin initializes **COM as STA** at startup and drives DirectShow objects created on that apartment. 4D delivers plugin calls on the calling process's thread, so calling these commands from a preemptive worker can hit COM apartment-marshaling problems and unsynchronized access to the internal preview maps. Call them from a cooperative process (form events and regular methods), as the bundled test form does.
- **4D version.** Built against 4D v16+ (uses `PA_GetMainWindowHWND` from v16 onward; falls back to window-class lookup for older hosts).
- **Build & install.** The release workflow produces a `.bundle` whose `Contents/Windows64/Capture.4DX` is the Windows binary; install it in the 4D `Plugins` folder. See the original blog post for a walkthrough: [4d-plugin-capture-with-preview](https://miyako.github.io/2019/08/15/4d-plugin-capture-with-preview.html).

---

## CAPTURE DEVICE Get default

### Syntax

```4d
device := CAPTURE DEVICE Get default
```

| Parameter | Type | Description |
|---|---|---|
| Result | `Text` | Name of the first enumerated capture device, or empty if none found |

### Description

Returns the first device reported by `ICreateDevEnum` for the video input category. This is the name to pass to [`CAPTURE PREVIEW Create`](#capture-preview-create); it is not guaranteed to be the physically "default" camera.

If no capture device is present, the result is an empty string.

### Example

From the plugin's own test form (`test/Project/Sources/Forms/TEST/method.4dm`, `On Load`):

```4d
$device:=CAPTURE DEVICE Get default 
Capture:=CAPTURE PREVIEW Create ($device)
```

---

## CAPTURE DEVICE LIST

### Syntax

```4d
CAPTURE DEVICE LIST (devices)
```

| Parameter | Type | Description |
|---|---|---|
| `devices` | `ARRAY TEXT` | (out) Names of all capture devices, in enumeration order |

### Description

Fills the passed text array with the names of the available video capture devices. The array is resized to fit. Devices appear in enumeration order, which matches the order [`CAPTURE DEVICE Get default`](#capture-device-get-default) draws from (its result is the first entry).

### Example

```4d
ARRAY TEXT(devices;0)
CAPTURE DEVICE LIST (devices)
ALERT(String(Size of array(devices))+" camera(s) found")
```

---

## CAPTURE PREVIEW Create

### Syntax

```4d
preview := CAPTURE PREVIEW Create ( device )
```

| Parameter | Type | Description |
|---|---|---|
| `device` | `Text` | Name of the capture device to use (e.g. from `CAPTURE DEVICE Get default` or `CAPTURE DEVICE LIST`) |
| Result | `Longint` | Preview id, or `0` if the preview could not be created |

### Description

Builds the DirectShow filter graph for `device` (device filter, sample grabber, preview renderer) and registers a preview context. Returns a positive preview id used by every other preview command. The id starts at `1` and is reused for the same device: calling `CAPTURE PREVIEW Create` again with a device that already has a preview returns the **existing** preview id and does not build a second graph.

Because COM is initialized in the plugin's startup apartment, this command (like the others) should be called from a cooperative process (see [Threads](#requirements--platform-notes)).

On failure — device not found, or any step of the filter-graph build failing — the command releases everything it acquired and returns `0`.

### Example

From the plugin's own test form (`test/Project/Sources/Forms/TEST/method.4dm`):

```4d
$device:=CAPTURE DEVICE Get default 
Capture:=CAPTURE PREVIEW Create ($device)

If (Capture#0)
	CAPTURE PREVIEW SET WINDOW (Capture;Current form window:C827)
	OBJECT GET COORDINATES:C663(*;"PreviewArea";$left;$top;$right;$bottom)
	$width:=$right-$left
	$height:=$bottom-$top
	CAPTURE PREVIEW SET RECT (Capture;$left;$top;$width;$height)
End if 
```

---

## CAPTURE PREVIEW SET WINDOW

### Syntax

```4d
CAPTURE PREVIEW SET WINDOW ( preview ; window )
```

| Parameter | Type | Description |
|---|---|---|
| `preview` | `Longint` | Preview id from [`CAPTURE PREVIEW Create`](#capture-preview-create) |
| `window` | `Longint` | 4D window ref, or `0` for the 4D MDI window |

### Description

Parents the preview's DirectShow video window into the given 4D form window. Pass `Current form window` to embed the preview in the current form (as the test form does). Passing `0` attaches the preview to the MDI window instead — useful for a preview that outlives a specific form.

The rect must be set afterwards with [`CAPTURE PREVIEW SET RECT`](#capture-preview-set-rect); the parent window alone does not define the preview's frame.

### Example

```4d
CAPTURE PREVIEW SET WINDOW (Capture;Current form window:C827)
```

---

## CAPTURE PREVIEW SET RECT

### Syntax

```4d
CAPTURE PREVIEW SET RECT ( preview ; x ; y ; width ; height )
```

| Parameter | Type | Description |
|---|---|---|
| `preview` | `Longint` | Preview id |
| `x` | `Longint` | Left edge, in client-area coordinates |
| `y` | `Longint` | Top edge, in client-area coordinates |
| `width` | `Longint` | Width in pixels |
| `height` | `Longint` | Height in pixels |

### Description

Moves and resizes the preview window inside its parent. Coordinates are relative to the **top-left** of the parent's client area (Windows convention). Call this again after the form is resized or the layout area moves.

### Example

```4d
OBJECT GET COORDINATES:C663(*;"PreviewArea";$left;$top;$right;$bottom)
CAPTURE PREVIEW SET RECT (Capture;$left;$top;$right-$left;$bottom-$top)
```

---

## CAPTURE PREVIEW GET RECT

### Syntax

```4d
CAPTURE PREVIEW GET RECT ( preview ; x ; y ; width ; height )
```

| Parameter | Type | Description |
|---|---|---|
| `preview` | `Longint` | Preview id |
| `x` | `Longint` | (out) Left edge |
| `y` | `Longint` | (out) Top edge |
| `width` | `Longint` | (out) Width in pixels |
| `height` | `Longint` | (out) Height in pixels |

### Description

Reads back the preview's current position and size, in the same client-area coordinates used by [`CAPTURE PREVIEW SET RECT`](#capture-preview-set-rect). On an invalid preview id all four outputs are left unchanged.

### Example

```4d
CAPTURE PREVIEW GET RECT (Capture;$x;$y;$w;$h)
ALERT("Preview is at "+String($x)+","+String($y)+" size "+String($w)+"x"+String($h))
```

---

## CAPTURE PREVIEW SET VISIBLE

### Syntax

```4d
CAPTURE PREVIEW SET VISIBLE ( preview ; visible )
```

| Parameter | Type | Description |
|---|---|---|
| `preview` | `Longint` | Preview id |
| `visible` | `Longint` | `1` to show and start the preview, `0` to hide and pause it |

### Description

Shows/hides the preview window and runs/pauses the filter graph; while visible, the grabber also starts buffering frames, which is what makes [`CAPTURE PREVIEW SNAP`](#capture-preview-snap) succeed. Setting visibility to `0` pauses the graph and stops frame buffering — the preview is hidden but the context stays alive until [`CAPTURE PREVIEW CLEAR`](#capture-preview-clear).

### Example

From the plugin's own test form (`test/Project/Sources/Forms/TEST/ObjectMethods/Start.4dm` and `Stop.4dm`):

```4d
// Start
CAPTURE PREVIEW SET VISIBLE (Capture;1)
OBJECT SET ENABLED:C1123(*;"Start";False:C215)
OBJECT SET ENABLED:C1123(*;"Stop";True:C214)
OBJECT SET ENABLED:C1123(*;"Snap";True:C214)
```

```4d
// Stop
CAPTURE PREVIEW SET VISIBLE (Capture;0)
OBJECT SET ENABLED:C1123(*;"Start";True:C214)
OBJECT SET ENABLED:C1123(*;"Stop";False:C215)
OBJECT SET ENABLED:C1123(*;"Snap";False:C215)
```

---

## CAPTURE PREVIEW Get visible

### Syntax

```4d
visible := CAPTURE PREVIEW Get visible ( preview )
```

| Parameter | Type | Description |
|---|---|---|
| `preview` | `Longint` | Preview id |
| Result | `Longint` | `1` if visible, `0` if hidden (or invalid id) |

### Description

Reports whether the preview is currently visible. Returns `0` for an invalid preview id.

### Example

```4d
If (CAPTURE PREVIEW Get visible (Capture)=0)
	CAPTURE PREVIEW SET VISIBLE (Capture;1)
End if 
```

---

## CAPTURE PREVIEW SNAP

### Syntax

```4d
CAPTURE PREVIEW SNAP ( preview ; picture )
```

| Parameter | Type | Description |
|---|---|---|
| `preview` | `Longint` | Preview id |
| `picture` | `Picture` | (out) 24-bit BMP of the current frame |

### Description

Grabs the current buffered frame and returns it as a 4D `Picture` containing a 24-bit BMP. The preview must be visible (and therefore buffering) — see [Requirements](#requirements--platform-notes). If no frame is available, `picture` is left empty (no 4D error is raised).

### Example

From the plugin's own test form (`test/Project/Sources/Forms/TEST/ObjectMethods/Snap.4dm`) — the test form appends each snap into a picture array displayed in a list box:

```4d
CAPTURE PREVIEW SNAP (Capture;$picture)

APPEND TO ARRAY:C911(Column1;$picture)
```

---

## CAPTURE PREVIEW CLEAR

### Syntax

```4d
CAPTURE PREVIEW CLEAR ( preview )
```

| Parameter | Type | Description |
|---|---|---|
| `preview` | `Longint` | Preview id |

### Description

Stops and tears down the preview: releases every DirectShow interface held by the context (graph, media control, video window, device and grabber filters), removes the context from the internal maps and frees it. Idempotent — clearing an invalid or already-cleared id does nothing, so it is safe to call unconditionally.

### Example

From the plugin's own test form (`test/Project/Sources/Forms/TEST/method.4dm`, `On Unload`):

```4d
If (Capture#0)
	CAPTURE PREVIEW CLEAR (Capture)
End if 
```

---

## CAPTURE PREVIEW Get window

### Syntax

```4d
window := CAPTURE PREVIEW Get window ( preview )
```

| Parameter | Type | Description |
|---|---|---|
| `preview` | `Longint` | Preview id |
| Result | `Longint` | The window ref passed to [`CAPTURE PREVIEW SET WINDOW`](#capture-preview-set-window), or `0` |

### Description

Returns the window ref most recently passed to [`CAPTURE PREVIEW SET WINDOW`](#capture-preview-set-window). Returns `0` for an invalid preview id or before `SET WINDOW` was called.

### Example

```4d
$w := CAPTURE PREVIEW Get window (Capture)
```

---

## Error handling & troubleshooting

- **Commands fail silently.** None of the commands raise a 4D error; every failure returns an empty/default value. Check [`CAPTURE PREVIEW Create`](#capture-preview-create)'s result before using a preview: a `0` there means the device was not found or the filter graph could not be built.
- **No camera → empty everything.** With no capture device present, [`CAPTURE DEVICE Get default`](#capture-device-get-default) returns `""` and `CAPTURE DEVICE LIST` returns an empty array; `CAPTURE PREVIEW Create` then returns `0`.
- **`CAPTURE PREVIEW SNAP` returns an empty picture.** Almost always because the preview is hidden ([`CAPTURE PREVIEW SET VISIBLE`](#capture-preview-set-visible) `0` stops frame buffering) or the preview was never started. Keep the preview visible while snapping.
- **Preview doesn't move with the form.** The preview is a native child window — after resizing or moving the form, or after `OBJECT GET COORDINATES` on a new layout, re-apply [`CAPTURE PREVIEW SET RECT`](#capture-preview-set-rect).
- **Call from cooperative processes.** The plugin initializes COM in STA mode and keeps its preview maps guarded by a single mutex only on the write paths. Preemptive worker threads calling these commands may hit COM apartment-marshaling issues or race the internal maps (see [Threads](#requirements--platform-notes)). Call them from form events or standard methods.
- **Call `CAPTURE PREVIEW CLEAR` on `On Unload`.** It releases every DirectShow interface; skipping it leaks the graph until the 4D process exits. The bundled test form clears its preview on `On Unload`.

---

## Quick reference

```4d
// Open the default camera in the current form, tucked into the "PreviewArea" rectangle
$device:=CAPTURE DEVICE Get default 
Capture:=CAPTURE PREVIEW Create ($device)
CAPTURE PREVIEW SET WINDOW (Capture;Current form window:C827)
OBJECT GET COORDINATES:C663(*;"PreviewArea";$l;$t;$r;$b)
CAPTURE PREVIEW SET RECT (Capture;$l;$t;$r-$l;$b-$t)
CAPTURE PREVIEW SET VISIBLE (Capture;1)

// ...on the form's resize handler
OBJECT GET COORDINATES:C663(*;"PreviewArea";$l;$t;$r;$b)
CAPTURE PREVIEW SET RECT (Capture;$l;$t;$r-$l;$b-$t)

// Take a picture
CAPTURE PREVIEW SNAP (Capture;$picture)

// Show the list of devices
ARRAY TEXT(devices;0)
CAPTURE DEVICE LIST (devices)

// Tear down when the form closes
CAPTURE PREVIEW CLEAR (Capture)
```