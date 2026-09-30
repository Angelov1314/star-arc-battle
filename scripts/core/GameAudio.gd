class_name GameAudio
extends Node

## Semantic, budgeted audio service. Call play() only after a state change succeeds.
const MAX_VOICES := 12
const MUSIC_PATHS := {"town": "res://assets/sound/original/music/town_loop.wav", "battle": "res://assets/sound/original/music/battle_loop.wav"}
const SPECS := {
	"click":["ui_click",1,0.035],"hover":["ui_hover",0,0.070],"select":["ui_select",1,0.060],"cancel":["ui_cancel",1,0.075],"error":["ui_error",2,0.140],"slider":["ui_slider",0,0.080],"equip":["equip",2,0.120],"lock":["lock",1,0.110],"unlock":["unlock",1,0.110],"craft":["craft",2,0.150],"upgrade":["upgrade",3,0.250],"socket":["socket",3,0.180],"dismantle":["dismantle",2,0.150],"reward":["reward",2,0.180],"level_up":["level_up",3,0.400],"fire":["fire",3,0.075],"explosion":["explosion",3,0.100],"damage":["damage",3,0.080],"heal":["heal",2,0.120],"turn":["turn",2,0.160],"win":["win",3,0.500],"lose":["lose",3,0.500],"step":["step",0,0.110],"charge":["charge",1,0.100],"charge_cancel":["charge_cancel",1,0.100],"power":["power",3,0.120],"warning":["warning",3,0.450],"hazard":["hazard",3,0.180],"pause":["pause",1,0.150],"resume":["resume",1,0.150],"guard":["lock",2,0.12],"stamina":["ui_select",1,0.12],"armor_break":["damage",3,0.16],"phase":["turn",2,0.18]
}
var music_volume := 0.55
var sfx_volume := 0.65
var music: AudioStreamPlayer
var music_next: AudioStreamPlayer
var voices: Array[AudioStreamPlayer] = []
var effects: Dictionary = {}
var effect_priority: Array[int] = []
var last_played: Dictionary = {}
var event_counts: Dictionary = {}
var dropped_counts: Dictionary = {}
var context := "town"
var target_context := "town"
var transition := 1.0
var paused := false
var duck_seconds := 0.0
var _shutdown := false
var _frame := -1
var _frame_plays := 0
var _audio_rng := RandomNumberGenerator.new()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	_audio_rng.seed = 0xA0D10
	music = _make_music_player(); music_next = _make_music_player()
	for i in range(MAX_VOICES):
		var voice := AudioStreamPlayer.new(); voice.bus = "SFX"; add_child(voice); voices.append(voice); effect_priority.append(-1)
	for spec in SPECS.values():
		var asset: String = spec[0]
		if not effects.has(asset): effects[asset] = load("res://assets/sound/original/sfx/%s.wav" % asset)
	_start_music(context, music); _apply_mix()

func _make_music_player() -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new(); player.bus = "Music"; add_child(player); return player

func _ensure_buses() -> void:
	for name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(name) < 0:
			AudioServer.add_bus(); AudioServer.set_bus_name(AudioServer.bus_count - 1, name)
	# Headroom lives at the bus, so event priorities remain expressive at volume 1.
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), -8.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), -12.0)

func volumes(music_value: float, sfx_value: float) -> void:
	music_volume = clampf(music_value, 0.0, 1.0); sfx_volume = clampf(sfx_value, 0.0, 1.0)
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), paused or music_volume <= 0.0)
	AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), sfx_volume <= 0.0)
	for voice in voices: voice.volume_db = _db(sfx_volume * (0.80 if paused else 1.0))
	_apply_mix()

func set_context(next_context: String) -> void:
	if next_context not in MUSIC_PATHS or next_context == target_context: return
	music_next.stop(); target_context = next_context; transition = 0.0; _start_music(next_context, music_next)
	# Audio backends may defer start by a frame; a playing stream is required during fade.
	if not music_next.playing: music_next.play()

func set_paused(value: bool) -> void:
	if paused == value: return
	paused = value
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), paused or music_volume <= 0.0)
	for player in [music, music_next]:
		if is_instance_valid(player): player.stream_paused = value
	_apply_mix()

func play(key: String) -> void:
	if _shutdown or not SPECS.has(key): return
	var spec: Array = SPECS[key]; var now := Time.get_ticks_msec() * 0.001
	if now - float(last_played.get(key, -1000.0)) < float(spec[2]): _drop(key); return
	var process_frame := Engine.get_process_frames()
	if _frame != process_frame: _frame = process_frame; _frame_plays = 0
	if _frame_plays >= 4 and int(spec[1]) < 3: _drop(key); return
	var index := _find_voice(int(spec[1]))
	if index < 0: _drop(key); return
	var stream: AudioStream = effects.get(spec[0])
	if stream == null: return
	var voice := voices[index]; voice.stream = stream; voice.pitch_scale = 1.0 + _audio_rng.randf_range(-0.025, 0.025); voice.volume_db = _db(sfx_volume * (0.80 if paused else 1.0)); voice.play()
	effect_priority[index] = int(spec[1]); last_played[key] = now; event_counts[key] = int(event_counts.get(key, 0)) + 1; _frame_plays += 1
	if key in ["fire", "explosion", "damage", "power", "hazard"]: duck_seconds = maxf(duck_seconds, 0.32)

func _find_voice(priority: int) -> int:
	for i in range(voices.size()):
		if not voices[i].playing: return i
	var candidate := -1; var weakest := priority
	for i in range(voices.size()):
		if effect_priority[i] < weakest: weakest = effect_priority[i]; candidate = i
	return candidate
func _drop(key: String) -> void: dropped_counts[key] = int(dropped_counts.get(key, 0)) + 1
func _start_music(kind: String, player: AudioStreamPlayer) -> void:
	var stream := load(MUSIC_PATHS[kind]); if stream == null: return
	# Keep the runtime contract independent of stale editor import caches.
	if stream is AudioStreamWAV:
		stream = stream.duplicate()
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.get_length() * wav.mix_rate)
	player.stream = stream
	player.play(); player.stream_paused = paused
func _process(delta: float) -> void:
	if _shutdown: return
	duck_seconds = maxf(0.0, duck_seconds - delta)
	if transition < 1.0:
		transition = minf(1.0, transition + delta / 1.2)
		if transition >= 1.0: music.stop(); var old := music; music = music_next; music_next = old; context = target_context
	_apply_mix()
func _apply_mix() -> void:
	if not is_instance_valid(music): return
	var base := music_volume * (0.0 if paused else 1.0); var duck := 0.55 if duck_seconds > 0.0 else 1.0
	if transition >= 1.0:
		music.volume_db = _db(base * duck); music_next.volume_db = _db(0.0)
	else:
		music.volume_db = _db(base * duck * (1.0 - transition)); music_next.volume_db = _db(base * duck * transition)
func _db(value: float) -> float: return -80.0 if value <= 0.0001 else linear_to_db(value)
func semantic_keys() -> PackedStringArray: return PackedStringArray(SPECS.keys())
func diagnostics() -> Dictionary:
	var active := 0
	for voice in voices:
		if voice.playing: active += 1
	return {"context":context, "target_context":target_context, "transition":transition, "events":event_counts.duplicate(), "dropped":dropped_counts.duplicate(), "active_voices":active, "voice_limit":MAX_VOICES, "voice_priorities":effect_priority.duplicate(), "paused":paused, "music_playing":is_instance_valid(music) and music.playing, "music_next_playing":is_instance_valid(music_next) and music_next.playing, "music_bus":"Music", "sfx_bus":"SFX"}
func shutdown() -> void:
	if _shutdown: return
	_shutdown = true
	for player in [music, music_next]:
		if is_instance_valid(player): player.stop(); player.stream = null
	for voice in voices:
		if is_instance_valid(voice): voice.stop(); voice.stream = null
	voices.clear(); effects.clear(); last_played.clear()
func _exit_tree() -> void: shutdown()
