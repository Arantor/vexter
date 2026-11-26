# TFMX implementation evidence

TFMX support uses only material supplied directly by the user. No external
format research or third-party player dependency was used.

The initial specification is Jonathan H. Pickard's *THE TFMX PROFESSIONAL 2.0
SONG FILE FORMAT*, supplied on 2026-11-25 from
`ftp.modland.com/pub/documents/format_documentation/The Final Musicsystem eXtended Professional v2.0 (.mdat, .smpl).txt`.
Its supplied file SHA-256 is
`9c3968e5322dfb91a2af84ef35ddc4471efbcdf55276c2cd6fd2818561c03c45`.
The original document remains intact in the user's local `tfmx` folder.

The user subsequently supplied the TFMX_v1.6 editor distribution from
`ftp.undergrund.net/users/hitchhikr/old/tools/TFMX_v1.6` on the same date.
Its readme describes a modified 1.6 editor with Pro and seven-voice extensions.
The primary behavioral reference is `source/rout.tfmx7v_sid.s`, SHA-256
`b1f470ea36de07da6bc6063bc9e99d18f64ed376ba83ec58501dfd1e166d5e3c`.
The editor source `source/tfmxed6.s` is also present, SHA-256
`511f63e67b670acd6c935db70c64cf6976a755937fd050dc45ea0a8451212c70`.
These references are not copied into the implementation or distributed as test
fixtures. The Nim parser and interpreter independently express their behavior.

The player's INITDATA establishes unpacked track/pattern/macro offsets
0x800/0x400/0x600, correcting the supplied text. Synthesizer precedes Sequencer
in IRQIN: macros/effects run on CIA ticks, and pattern execution has a separate
countdown divider. SetCIATempo hardcodes the NTSC numerator 1790456/BPM; tempos below
32 fall back to 125 BPM. Replay uses the corresponding PAL CIA reload plus
one count, consistent with its PAL sample clock and nominal 24 ticks per beat.
Mixing the NTSC numerator with a PAL clock caused about 0.9% timing drift. NoteTable supplies the 64 periods, including repeated
upper entries. The Professional MacDoNote applies a period multiplier for detuning. MacSetVol takes its value from the last byte, which
also differs from the text. Macro 0x1B, 0x1E and 0x20 dispatch to MacNull in this
player. These choices describe this reference version, not every historical
TFMX player.

The five original local MDAT/SMPL pairs are Grand Monster Slam title/ingame,
R-Type title, and Adventures of Quik and Silva title/ingame. Their acquisition
and redistribution rights have not been independently established; they remain
user-local compatibility inputs, hashed in `tfmx-corpus.sha256`. Four use the unpacked layout; Quik and Silva
ingame uses explicit relocated tables. Automated corpus runs establish bounded
execution and non-silent PCM, not audible fidelity. The user subsequently
supplied five stereo 44,100 Hz, 16-bit UADE WAV references beside the MDAT
files. They are hashed in `tfmx-corpus.sha256`. Loop caps and trailing audio
mean their complete durations are not exact song-length controls. The UADE
invocation, selected player and filter settings were not supplied.
`tests/test_tfmx.nim` uses original synthetic data and checks signed PCM,
stereo routing, macro-before-pattern scheduling, DMA repeat-register changes,
companion resolution, WAV export, malformed control flow and duration bounds.

## Classic effects and comparison controls

The supplied distribution also contains `routines/rout.tfmx.obj_v1.0p`, SHA-256
`eb4b42d11151381f98b860cda0f3f2298ac87fee812f35cb97cd8e832f12a8a3`.
Inspection of this local 68000 object establishes older effects which differ
from the Professional source: at file offset 0x0DA0 vibrato adds a signed
triangle accumulator to the base period, and at 0x0DDE portamento subtracts
or adds the configured step, clamping at the target. At 0x0AE8 note detuning
adds offsets in period units. The classic vibrato setup at 0x0B4E clears the
speed's low bit before initializing its triangle counter. These are behavioral
facts recovered from the supplied object; no player code is embedded or run.

The R-Type opening reference independently confirms classic portamento:
matching short waveform fragments to the original sample bank gives periods
about 676, 656, 636, 596, 536 and 476 at reference times 0.102, 0.202, 0.302,
0.502, 0.802 and 1.102 seconds. This is a four-unit step per 50 Hz tick, rather
than a four-in-256 proportional change. Classic additive vibrato also produces
the stronger pitch modulation used by Grand Monster Slam's bell sound.

`renderTfmx` defaults to `temClassic`; callers can explicitly select
`temProfessional` for proportional detuning, vibrato and portamento. The
header's word at offset 10 is the editor's compression setting, not a reliable
effect-version flag, so replay does not guess effect semantics from it.
The GUI currently uses the classic default. `applyFilter=false` allows isolated
PCM/effect tests without output filtering, retaining mixer oversampling.

Macro wait deferral and effect startup are separate state. DMAon stores its
flag in the effect state: zero skips the first effect tick, positive runs, and
negative suppresses ongoing effects. A new note clears effect startup but does
not clear macro wait deferral. Master fading continues on ticks where voice
effects are skipped. These distinctions were lost in the original preview.

Local comparison used short-window spectra and five-second RMS-envelope
correlations, excluding UADE loop/end caps and normalizing gain. In the two
reported title tracks, median relative spectral differences over 2–20 seconds
fell from roughly 7–10 dB in the 6–10 kHz bands to roughly 1 dB. At 10, 30,
60 and 100 seconds, the envelope alignment remains about 40 ms apart, instead
of drifting to roughly 0.9 seconds at 100 seconds. There are still startup,
phase, stereo-separation, gain and hardware-model differences; these metrics
are evidence of improvement rather than a bit-exact playback claim.

Synthetic tests now also cover classic versus Professional pitch effects,
DMA effect flags and fixed-filter attenuation using independently predictable
square-wave periods. The reference WAVs remain user-local comparison material.

## Current limitations

This is a bounded four-voice preview with four-times oversampling of held
sample values, a fixed stereo layout and fixed headroom. A persistent one-pole
4.5 kHz low-pass runs at the oversampled rate before averaging each output
frame. This approximates the reference recordings' fixed treble attenuation;
it is not a cycle-accurate Paula or analogue-circuit model. Sample start/length
registers are separate from the currently playing span and reload on sample
boundaries, but hardware DMA start latency and bus behavior are approximated.
Seven-voice and SID sample-manipulation commands fail explicitly on execution.

Each preview stops at the first subsong end or after 300 seconds; musical loops
can reach the duration limit. Instruction and track-command budgets reject
runaway control flow. Invalid program pointers are rejected when reached.
Missing companions still allow structural inspection and raw MDAT export.
Opening an SMPL file alone is not supported: it has no standalone magic.

Slot zero is always retained when structurally valid. Other 0/0 song-table
entries are omitted as conventional unused slots, and reversed ranges are
omitted. A genuine secondary one-position song at trackstep zero is therefore
not exposed; conversely, stale nonzero editor slots may appear as subsongs.
The native macro streams are not projected into the MOD-style tracker archetype
and there is no tracker JSON or individually inferred instrument extraction.
The original music and sample data remain separately BIN-exportable.
