param(
	[string]$GodotBin = $env:GODOT_BIN
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($GodotBin)) {
	$command = Get-Command godot, godot4 -ErrorAction SilentlyContinue |
		Select-Object -First 1
	if ($null -eq $command) {
		throw 'Godot bulunamadı. GODOT_BIN ortam değişkenini Godot 4.7+ console executable yoluna ayarlayın.'
	}
	$GodotBin = $command.Source
}

function Invoke-GodotCheck {
	param([string[]]$Arguments)
	# Godot writes contract failures to stderr. With the script-wide Stop policy,
	# Windows PowerShell converts the first stderr line into a terminating
	# NativeCommandError before we can print the detailed contract report.
	$previousErrorAction = $ErrorActionPreference
	$ErrorActionPreference = 'Continue'
	$output = @(& $GodotBin @Arguments 2>&1)
	$ErrorActionPreference = $previousErrorAction
	$output | ForEach-Object { Write-Host $_ }
	if ($LASTEXITCODE -ne 0) {
		throw "Godot doğrulaması başarısız oldu (exit $LASTEXITCODE): $($Arguments -join ' ')"
	}
	$failureText = $output | Select-String -Pattern 'complete=false|SCRIPT ERROR|contract incomplete'
	if ($null -ne $failureText) {
		throw "Godot doğrulaması başarısız sözleşme çıktısı üretti: $($Arguments -join ' ')"
	}
}

Push-Location $projectRoot
try {
	Invoke-GodotCheck @('--headless', '--editor', '--path', '.', '--quit')
	Invoke-GodotCheck @('--headless', '--path', '.', '--script',
		'res://scripts/testing/electrical_model_test.gd')
	Invoke-GodotCheck @('--headless', '--path', '.', '--script',
		'res://scripts/testing/console_instruments_test.gd')
	Invoke-GodotCheck @('--headless', '--path', '.', '--script',
		'res://scripts/testing/electronics_controller_test.gd')
	Invoke-GodotCheck @('--headless', '--path', '.', '--script',
		'res://scripts/testing/navigation_display_controller_test.gd')
	Invoke-GodotCheck @('--headless', '--path', '.', '--script',
		'res://scripts/testing/access_controller_test.gd')
	Invoke-GodotCheck @('--headless', '--path', '.', '--script',
		'res://scripts/testing/engine_controller_test.gd')
	Invoke-GodotCheck @('--headless', '--path', '.', '--script',
		'res://scripts/testing/buoyancy_controller_test.gd')
	Invoke-GodotCheck @('--headless', '--path', '.', '--script',
		'res://scripts/testing/grounding_controller_test.gd')
	Invoke-GodotCheck @('--headless', '--path', '.', '--script',
		'res://scripts/testing/hydrodynamics_controller_test.gd')
	Invoke-GodotCheck @('--headless', '--path', '.', '--script',
		'res://scripts/testing/radio_handset_controller_test.gd')
	Invoke-GodotCheck @('--headless', '--path', '.', '--script',
		'res://scripts/testing/helm_controls_visual_builder_test.gd')
	Invoke-GodotCheck @('--headless', '--path', '.', '--script',
		'res://scripts/testing/wheelhouse_furnishings_visual_test.gd')
	Invoke-GodotCheck @('--headless', '--path', '.', '--script',
		'res://scripts/testing/switchboard_controller_test.gd')
	Invoke-GodotCheck @('--headless', '--path', '.', '--script',
		'res://scripts/testing/windlass_controller_test.gd')
	Invoke-GodotCheck @('--headless', '--path', '.', '--script',
		'res://scripts/testing/lighting_controller_test.gd')
	Invoke-GodotCheck @('--headless', '--path', '.', '--script',
		'res://scripts/testing/camera_interaction_selector_test.gd')
	Invoke-GodotCheck @('--headless', '--path', '.', '--script',
		'res://scripts/testing/camera_prompt_presenter_test.gd')
	Invoke-GodotCheck @('--headless', '--path', '.', '--script',
		'res://scripts/testing/camera_fps_locomotion_test.gd')
	Invoke-GodotCheck @('--headless', '--path', '.', '--script',
		'res://scripts/testing/camera_eye_motion_test.gd')
	Invoke-GodotCheck @('--headless', '--path', '.', '--script',
		'res://scripts/testing/deck_bag_rifle_obstruction_test.gd')
	Invoke-GodotCheck @('--headless', '--path', '.', '--script',
		'res://scripts/testing/deck_bag_rifle_reload_controller_test.gd')
	Invoke-GodotCheck @('--headless', '--path', '.', '--script',
		'res://scripts/testing/hull_visual_builder_test.gd')
	Invoke-GodotCheck @('--headless', '--path', '.', '--script',
		'res://scripts/testing/interior_environment_test.gd')
	Invoke-GodotCheck @('--headless', '--path', '.', '--script',
		'res://scripts/testing/stove_controller_test.gd')
	Invoke-GodotCheck @('--headless', '--path', '.', '--script',
		'res://scripts/testing/interaction_locator_test.gd')
	Invoke-GodotCheck @('--headless', '--path', '.', '--', '--interaction-contract-test')
	Invoke-GodotCheck @('--headless', '--path', '.', '--', '--input-interaction-test')
	Invoke-GodotCheck @('--headless', '--path', '.', '--', '--catalog-integrity-test')
	Invoke-GodotCheck @('--headless', '--path', '.', '--', '--weather-effects-test')
	Invoke-GodotCheck @('--headless', '--path', '.', '--', '--interior-visual-test')
	Invoke-GodotCheck @('--headless', '--path', '.', '--', '--deck-visual-test')
	Invoke-GodotCheck @('--headless', '--path', '.', '--', '--console-visual-test')
	Invoke-GodotCheck @('--headless', '--path', '.', '--', '--electronics-visual-test')
	Invoke-GodotCheck @('--headless', '--path', '.', '--', '--switchboard-visual-test')
	Invoke-GodotCheck @('--headless', '--path', '.', '--', '--anchor-visual-test')
	Invoke-GodotCheck @('--headless', '--path', '.', '--', '--cabin-visual-test')
	Invoke-GodotCheck @('--headless', '--path', '.', '--', '--wheelhouse-visual-test')
	Invoke-GodotCheck @('--headless', '--path', '.', '--', '--mast-visual-test')
	Invoke-GodotCheck @('--headless', '--path', '.', '--', '--companionway-visual-test')
	Invoke-GodotCheck @('--headless', '--path', '.', '--', '--bag-cycle-test')
	Invoke-GodotCheck @('--headless', '--path', '.', '--', '--bag-item-test')
	Invoke-GodotCheck @('--headless', '--path', '.', '--', '--knife-test')
	Invoke-GodotCheck @('--headless', '--path', '.', '--', '--rifle-test')
} finally {
	Pop-Location
}
