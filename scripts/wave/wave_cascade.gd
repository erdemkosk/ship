@tool
class_name WaveCascade extends Resource
## One octave of the wave spectrum, simulated as its own FFT tile.
##
## A single FFT tile cannot hold an ocean: make it long enough for 200 m swell
## and its grid is too coarse for the chop; make it fine enough for the chop and
## it tiles visibly every few metres. Cascades split the spectrum into bands and
## give each one a tile sized for its own band. `tile_length` is therefore both
## the longest wave this cascade can carry AND its repeat period.

## Metres covered by one tile. Also the longest wavelength this cascade holds.
@export var tile_length := 256.0
## Displacement contribution. The band limit already keeps cascades from
## double-counting; this is for art direction on top of it.
@export_range(0.0, 2.0) var displacement_scale := 1.0
@export_range(0.0, 2.0) var normal_scale := 1.0

@export var wind_speed := 14.0
@export_range(-360.0, 360.0) var wind_direction := 0.0
## Distance from shore, in kilometres. Short fetch = steeper, shorter seas.
@export var fetch_length := 120.0
@export_range(0.0, 2.0) var swell := 0.8
## How tightly waves cluster around the wind direction. 0 = tight, 1 = isotropic.
@export_range(0.0, 1.0) var spread := 0.2
## Attenuation of the high-frequency tail.
@export_range(0.0, 1.0) var detail := 1.0

## How steep the surface must fold before foam accumulates.
@export_range(0.0, 2.0) var whitecap := 0.5
@export_range(0.0, 10.0) var foam_amount := 5.0

## Band this cascade owns, in rad/m. Filled in by WaveGenerator from the tile
## lengths of the whole set — do not set by hand.
var k_min := 0.0
var k_max := 0.0
## Spectral gain that pulls the whole cascade set onto a target significant wave
## height. JONSWAP's alpha is a linear scale on the spectrum, so one number here
## is a physical amplitude multiplier, not a fudge. Set by WaveGenerator.
var alpha_gain := 1.0

var spectrum_seed := Vector2i.ZERO
var should_generate_spectrum := true
var time := 0.0
var foam_grow_rate := 0.0
var foam_decay_rate := 0.0


func mark_dirty() -> void:
	should_generate_spectrum = true
