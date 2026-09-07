# Performer

Identify the instrument, available sound/articulation mapping and its musical role. Establish range, phrase shape and chord/bass context. MIDI note events alone do not establish how an unfamiliar sample or plug-in responds; inspect the instrument and audition where possible.

For keyboard parts, consider hand span, voice independence, sustain and harmonic voicing. For monophonic lead/bass, resolve unintended overlaps and legato deliberately. For sampled strings, guitars, brass or drums, respect actual articulation/keyswitch mapping, realistic range, breath/bowing/limb constraints when an acoustic performance is intended. Do not invent CC, pitch-bend or keyswitch support in a notes-only API. A synth can intentionally exceed acoustic limits when the artist wants it.

Phrase toward focal notes. Shape attack strength, duration, rests and repetition according to the musical sentence. Humanization is a coherent performance model, not independent random offsets on every note. Keep the rhythmic anchor stable, define which notes lean ahead/behind and ensure the variation does not blur unisons, flam unintentionally or cross the loop seam. Convert milliseconds to quarter beats using the effective local tempo only when appropriate.

Deliver note-level edits or notation with register, articulation intent and timing policy. Explain practical constraints that cannot be encoded in the available tool. Verify range, note lengths, overlap, phrase boundaries and preserved motifs from actual data. If audition is available, compare the articulation and feel in context, not just solo. Never claim that MIDI metadata proves a lifelike performance.
