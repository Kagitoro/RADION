class_name FPSounds
extends RefCounted
## Small synthesized foley for the hand actions. Built once and cached.
## Each sound is a `gen_<name>(t, state)` sample generator rendered by `render`.

const RATE := 32000
const LENGTHS := {
	"pop": .55, "gulp": .42, "gulp_b": .42, "gulp_c": .42, "ahh": .75, "burp": 1.05, "can_open": .9, "can_crush": .45,
	"lighter_strike": .28, "flame_on": .6, "inhale": 1.1, "exhale": 1.4,
	"flick": .2, "heave": .6, "splash": .7, "heartbeat": .7,
}
static var cache := {}

static func get_sound(sound_name: String) -> AudioStreamWAV:
	if not cache.has(sound_name):
		cache[sound_name] = render(LENGTHS[sound_name],Callable(FPSounds,"gen_"+sound_name),sound_name.hash())
	return cache[sound_name]

static func render(seconds: float, generator: Callable, seed_value: int) -> AudioStreamWAV:
	var count := int(seconds*RATE)
	var data := PackedByteArray()
	data.resize(count*2)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var state := {"low":0.0,"rng":rng,"phase":0.0,"period_index":0,"jitter":0.0}
	for index in range(count):
		var value: float = generator.call(float(index)/RATE,state)
		data.encode_s16(index*2,roundi(clampf(value,-1,1)*32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	return wav

static func white(s: Dictionary) -> float:
	return (s.rng as RandomNumberGenerator).randf_range(-1.0,1.0)

static func noise(s: Dictionary, smoothing: float) -> float:
	s.low = lerpf(s.low,white(s),smoothing)
	return s.low

static func gauss(t: float, at: float, width: float) -> float:
	return exp(-pow((t-at)/width,2))

## Crown cap popping off with a short fizz.
static func gen_pop(t: float, s: Dictionary) -> float:
	var click := sin(TAU*1850*t)*exp(-t*160)*.5
	var body := sin(TAU*(420-300*t)*t)*exp(-t*45)*.35
	var fizz := white(s)*.16*smoothstep(0.0,.02,t)*exp(-t*5.0)
	return click+body+fizz

## Two-pole resonator; `key` keeps each filter's history in the state.
static func reson(s: Dictionary, key: String, x: float, freq: float, width: float) -> float:
	var r := exp(-PI*width/RATE)
	var y1: float = s.get(key+"1",0.0)
	var y2: float = s.get(key+"2",0.0)
	var y := (1.0-r)*x+2.0*r*cos(TAU*freq/RATE)*y1-r*r*y2
	s[key+"2"] = y1
	s[key+"1"] = y
	return y

## A real swallow: wet tongue click, the deep "glk" of the throat closing on
## the mouthful, then a small second gloop as it goes down.
static func swallow(t: float, s: Dictionary, pitch: float, late: float) -> float:
	var raw := white(s)
	var click := reson(s,"click",raw,1500*pitch,500)*gauss(t,.035,.008)*.55
	var glk_pitch := (210+150*exp(-(t-.07)*28))*pitch
	s.glk = float(s.get("glk",0.0))+TAU*glk_pitch/RATE
	var glk := sin(s.glk)*gauss(t,.085,.022)*.55
	var throat := reson(s,"throat",raw,380*pitch,160)*gauss(t,.09,.03)*.26
	var down_pitch := (150+70*exp(-(t-late)*20))*pitch
	s.down = float(s.get("down",0.0))+TAU*down_pitch/RATE
	var down := sin(s.down)*gauss(t,late,.03)*.3
	var liquid := reson(s,"liquid",raw,700*pitch+300*sin(t*90),260)*gauss(t,late-.03,.06)*.2
	return click+glk+throat+down+liquid

static func gen_gulp(t: float, s: Dictionary) -> float:
	return swallow(t,s,1.0,.21)

static func gen_gulp_b(t: float, s: Dictionary) -> float:
	return swallow(t,s,.9,.24)

static func gen_gulp_c(t: float, s: Dictionary) -> float:
	return swallow(t,s,1.1,.19)

## Long satisfied beer burp: a rough, jittery low glottal buzz through an
## "o-u" vowel, a little croak (every other pulse weaker) and a tail of breath.
static func gen_burp(t: float, s: Dictionary) -> float:
	var length := 1.05
	var env := smoothstep(0.0,.05,t)*(1.0-smoothstep(.55,length-.02,t))*(.85+.15*sin(TAU*4.5*t))
	var f0 := 84.0+16.0*sin(TAU*1.6*t+.6)-14.0*t+float(s.jitter)
	s.phase = float(s.phase)+f0/RATE
	var pulse := 0.0
	if float(s.phase)>=1.0:
		s.phase = float(s.phase)-1.0
		s.period_index = int(s.period_index)+1
		var rng := s.rng as RandomNumberGenerator
		s.jitter = rng.randf_range(-7.0,7.0)
		pulse = (1.0 if int(s.period_index)%2==0 else .55)*rng.randf_range(.75,1.0)
	# Glottal source: sharp pulse plus a bit of turbulence while voicing.
	var source := pulse*6.0+white(s)*.05
	var vowel_shift := smoothstep(.1,.8,t)
	var voice := reson(s,"f1",source,lerpf(520,380,vowel_shift),110)*1.0 \
		+reson(s,"f2",source,lerpf(980,760,vowel_shift),170)*.55 \
		+reson(s,"f3",source,2400,320)*.12
	var breath := reson(s,"air",white(s),900,900)*.12*smoothstep(.75,length,t)*(1.0-smoothstep(.97,length,t))
	return clampf(voice*.75*env+breath,-1.0,1.0)

## Satisfied exhale after a drink ("ahh").
static func gen_ahh(t: float, s: Dictionary) -> float:
	var env := smoothstep(0.0,.08,t)*exp(-t*3.2)
	var breath := noise(s,.35)*.55
	var voice := (sin(TAU*128*t)+.5*sin(TAU*256*t)+.25*sin(TAU*384*t))*.09*smoothstep(.05,.15,t)*exp(-t*4)
	return (breath+voice)*env

## Pull-tab crack plus a carbonated hiss.
static func gen_can_open(t: float, s: Dictionary) -> float:
	var crack := white(s)*exp(-t*90)*.8+sin(TAU*2600*t)*exp(-t*120)*.3
	var raw := white(s)
	var hiss := (raw-noise(s,.3))*.3*smoothstep(.01,.04,t)*exp(-t*3.8)
	return crack+hiss

## Aluminium can crumpled in the fist.
static func gen_can_crush(t: float, s: Dictionary) -> float:
	var crinkle := 0.0
	for burst in [.02,.07,.11,.19,.24]:
		crinkle += gauss(t,burst,.008)
	return white(s)*(crinkle*.6+.08*exp(-t*6))

## Flint wheel strike: scrape and a click.
static func gen_lighter_strike(t: float, s: Dictionary) -> float:
	var raw := white(s)
	var scrape := (raw-noise(s,.5))*gauss(t,.03,.025)*.55
	var click := sin(TAU*3200*t)*exp(-t*200)*.25
	return scrape+click

## Gas catching fire: soft whoosh.
static func gen_flame_on(t: float, s: Dictionary) -> float:
	return noise(s,.08)*smoothstep(0.0,.03,t)*exp(-t*5.0)*.9

## Long inhale with the tobacco crackle.
static func gen_inhale(t: float, s: Dictionary) -> float:
	var env := smoothstep(0.0,.2,t)*(1.0-smoothstep(.8,1.1,t))
	var air := noise(s,.25)*.22*env
	var spark := (s.rng as RandomNumberGenerator).randf()
	var crackle := (white(s)*.6 if spark>.9965 else 0.0)*env
	return air+crackle

## Slow exhale of smoke.
static func gen_exhale(t: float, s: Dictionary) -> float:
	return noise(s,.18)*smoothstep(0.0,.12,t)*exp(-t*1.8)*.5

## Cigarette flicked away.
static func gen_flick(t: float, s: Dictionary) -> float:
	return white(s)*exp(-t*60)*.4+sin(TAU*900*t)*exp(-t*80)*.15

## Low heave before vomiting.
static func gen_heave(t: float, s: Dictionary) -> float:
	var env := smoothstep(0.0,.06,t)*exp(-t*4)
	var groan := sin(TAU*(110-30*t)*t+sin(TAU*7*t)*2.0)*.3
	return (groan+noise(s,.15)*.5)*env

## Wet splatter on the floor.
static func gen_splash(t: float, s: Dictionary) -> float:
	var drops := 0.0
	for burst in [.0,.05,.09,.16,.22,.31]:
		drops += gauss(t,burst,.012)
	return noise(s,.45)*(drops*.5+.25*exp(-t*5))

## Energy rush heartbeat thump.
static func gen_heartbeat(t: float, _s: Dictionary) -> float:
	var beat := 0.0
	for at in [.0,.22]:
		var local: float = t-at
		if local>=0:
			beat += sin(TAU*55*local)*exp(-local*22)
	return beat*.8
