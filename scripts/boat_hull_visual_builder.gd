class_name BoatHullVisualBuilder
extends RefCounted
## Builds the hull courses, bow, deck plating, bulwarks and transom.


func build(keel: Material, hull: Material, boot: Material, deck: Material,
		paint_dark: Material, trim: Material, metal: Material,
		sea_ladder_x: float, box_callback: Callable, cyl_callback: Callable,
		prism_callback: Callable, nameboard_callback: Callable,
		side_bulwark_callback: Callable) -> void:
	# --- hull ---------------------------------------------------------------
	box_callback.call(Vector3(1.7, 0.30, 9.5), Vector3(0.0, -0.68, 0.75), Vector3.ZERO, keel)
	box_callback.call(Vector3(3.73, 0.55, 9.8), Vector3(0.0, -0.42, 0.75), Vector3.ZERO, hull)
	box_callback.call(Vector3(4.08, 0.80, 9.8), Vector3(0.0, 0.05, 0.75), Vector3.ZERO, hull)
	# Flared topsides, tilted out a few degrees so she is not a shoebox.
	box_callback.call(Vector3(0.20, 1.05, 9.7), Vector3(-2.08, 0.22, 0.75), Vector3(0.0, 0.0, 7.0), hull)
	box_callback.call(Vector3(0.20, 1.05, 9.7), Vector3(2.08, 0.22, 0.75), Vector3(0.0, 0.0, -7.0), hull)
	# Boot top: the paint line at the waterline, the thing that says "this floats
	# here" more than any other detail on a working boat.
	box_callback.call(Vector3(4.14, 0.16, 9.82), Vector3(0.0, -0.06, 0.75), Vector3.ZERO, boot)
	# Bow: a real one. The old bow was three planks — two flat panels and a
	# vertical post — which from ahead read as exactly that. Now the hull's own
	# layers each run forward into a plan-view wedge (same widths, same colours,
	# so every seam lines through), the whole entry tapers to a raked stem, and
	# the deck closes the top with a triangle. Boxes end square; bows do not.
	# Each wedge BUTTS its hull course instead of lapping it. Overlapping them
	# put two coplanar faces in the same millimetre over a 25 cm band, which is
	# exactly the flicker across the bow: the depth test cannot choose, so it
	# chooses differently every frame. Aft edge of each prism = forward edge of
	# the box it continues (hull courses end at z -4.15, the boot top at -4.16).
	prism_callback.call(3.73, 0.85, 0.55, Vector3(0.0, -0.42, -4.575), hull)
	prism_callback.call(4.08, 1.00, 0.80, Vector3(0.0, 0.05, -4.650), hull)
	prism_callback.call(4.145, 1.02, 0.16, Vector3(0.0, -0.06, -4.670), boot)
	# The band between sheer and deck edge, fairing the flared topsides in.
	# Sheer band. Its top is held 1 cm BELOW the deck plane on purpose: flush
	# with it, the band and the foredeck triangle shared a surface and fought.
	prism_callback.call(4.10, 0.85, 0.19, Vector3(0.0, 0.525, -4.525), hull)
	# Foredeck triangle: same thickness as the main deck, so its top lands on
	# the same 0.63 plane and the bow is walked onto, not stepped down into.
	# Aft edge butts the main deck's forward edge at z -3.95 exactly.
	prism_callback.call(3.92, 1.00, 0.14, Vector3(0.0, 0.56, -4.45), deck)
	# Raked stem: foot at the keel, head leaning forward over the water.
	box_callback.call(Vector3(0.16, 1.85, 0.30), Vector3(0.0, 0.32, -4.93), Vector3(-19.0, 0.0, 0.0), keel)
	# Bulwarks converge on the stem head. Geometry, not eyeballing: each runs
	# from the side bulwark's forward end (x 1.98, z -3.90) to the apex
	# (0, -5.05) — that is a 60-degree sweep over 2.32 m, and nothing shallower
	# MEETS the sides; the first pass used 33 degrees from x 0.97 and the rails
	# hung in the air a half-metre inboard of the bulwarks they pretended to
	# continue.
	box_callback.call(Vector3(0.12, 0.50, 2.32), Vector3(-0.99, 0.86, -4.475), Vector3(0.0, -60.0, 0.0), paint_dark)
	box_callback.call(Vector3(0.12, 0.50, 2.32), Vector3(0.99, 0.86, -4.475), Vector3(0.0, 60.0, 0.0), paint_dark)
	# Stem-head block closing the vee where the two rails meet.
	box_callback.call(Vector3(0.20, 0.50, 0.24), Vector3(0.0, 0.86, -5.00), Vector3.ZERO, paint_dark)
	# Rubbing strake: same 60-degree run, one course down and a hand outboard.
	# It used to close at 66 degrees so it would meet the stem — that put the
	# two planks in a wedge, the top rail angling off the one below it.
	box_callback.call(Vector3(0.10, 0.14, 2.32), Vector3(-1.04, 0.52, -4.56), Vector3(0.0, -60.0, 0.0), trim)
	box_callback.call(Vector3(0.10, 0.14, 2.32), Vector3(1.04, 0.52, -4.56), Vector3(0.0, 60.0, 0.0), trim)
	# Transom, raked.
	box_callback.call(Vector3(4.03, 1.25, 0.22), Vector3(0.0, 0.18, 5.70), Vector3(-9.0, 0.0, 0.0), hull)
	nameboard_callback.call()
	# Rubbing strake all round.
	box_callback.call(Vector3(4.26, 0.14, 9.85), Vector3(0.0, 0.52, 0.75), Vector3.ZERO, trim)

	# --- deck and bulwarks --------------------------------------------------
	# Deck, in four pieces because there is a HOLE in it. A spurling pipe needs
	# an actual opening — faking one with a dark disc leaves the deck's own top
	# face visible down the bore, which is worse than no pipe. So the plating is
	# laid round the hole: forward of it, a band either side of it, and the long
	# run aft. Hole is 0.24 square at (0, -3.02), just abaft the windlass.
	box_callback.call(Vector3(3.88, 0.14, 0.81), Vector3(0.0, 0.56, -3.545), Vector3.ZERO, deck)
	box_callback.call(Vector3(1.82, 0.14, 0.24), Vector3(-1.03, 0.56, -3.02), Vector3.ZERO, deck)
	box_callback.call(Vector3(1.82, 0.14, 0.24), Vector3(1.03, 0.56, -3.02), Vector3.ZERO, deck)
	box_callback.call(Vector3(3.88, 0.14, 8.45), Vector3(0.0, 0.56, 1.325), Vector3.ZERO, deck)
	# Bulwarks in two courses so the scuppers are holes, not painted-on rust.
	# Upper rail runs through; the lower course breaks at four stations a side.
	side_bulwark_callback.call(-1.98, 5.0, paint_dark)
	side_bulwark_callback.call(1.98, -5.0, paint_dark)
	box_callback.call(Vector3(3.98, 0.10, 0.14), Vector3(0.0, 1.13, -3.95), Vector3.ZERO, trim)
	# Transom cap, one run. The ladder hangs OUTBOARD and you step over the
	# cap; cutting a gate in it left a hole you looked through at the sea,
	# with the grab iron hanging in the gap.
	box_callback.call(Vector3(3.98, 0.10, 0.14), Vector3(0.0, 1.13, 5.58), Vector3.ZERO, trim)
	# Hull course dies around y 0.80. Close the well up to the cap so there
	# is no slot of daylight under the rail.
	box_callback.call(Vector3(3.98, 0.36, 0.12), Vector3(0.0, 0.94, 5.64), Vector3(-9.0, 0.0, 0.0), paint_dark)
	# Posts on the cap where the ladder comes aboard.
	cyl_callback.call(0.032, 0.032, 0.28, Vector3(sea_ladder_x - 0.16, 1.32, 5.58), Vector3.ZERO, metal)
	cyl_callback.call(0.032, 0.032, 0.28, Vector3(sea_ladder_x + 0.16, 1.32, 5.58), Vector3.ZERO, metal)
	# Foredeck left clear. There was a cargo hatch and a crate of gear lying on
	# it — a metre-and-a-bit slab of planking in the middle of the working deck
	# and a dark box beside it, both of them just something to trip over. The
	# windlass and the mast are the only things out here that do a job.

