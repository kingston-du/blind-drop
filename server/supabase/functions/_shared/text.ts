// _shared/text.ts — input sanitisation. docs/14 §7.
//
// A display name is rendered as text and never as markup, so escaping is not the concern
// here. The concern is characters that change what *other* text does: a right-to-left
// override in a name reorders the guess sheet around it, and a zero-width joiner makes two
// names indistinguishable on screen. Both are real prank vectors in a group of teenagers,
// and both are cheap to remove at the door.

// C0 and C1 control characters, including newline and tab.
const CONTROL = /[\u0000-\u001F\u007F-\u009F]/gu;

// Invisibles and bidirectional overrides:
//   200B–200D  zero width space / non-joiner / joiner
//   200E–200F  left-to-right and right-to-left marks
//   202A–202E  the embedding and override block
//   2060–2064  word joiner and invisible operators
//   2066–2069  the isolate block
//   00AD       soft hyphen
//   FEFF       byte order mark / zero width no-break space
const INVISIBLE = /[\u00AD\u200B-\u200F\u202A-\u202E\u2060-\u2064\u2066-\u2069\uFEFF]/gu;

/**
 * A display name as it will be stored: NFC-normalised, stripped of controls and invisibles,
 * internal whitespace collapsed, ends trimmed.
 *
 * Returns the cleaned string, which the caller still has to length-check — an all-invisible
 * name cleans down to `""` and must be rejected, not stored (docs/04 §2: 1–24 characters).
 */
export function cleanDisplayName(raw: string): string {
  return raw
    .normalize("NFC")
    .replace(CONTROL, "")
    .replace(INVISIBLE, "")
    .replace(/\s+/gu, " ")
    .trim();
}

/** Length as a person and as Postgres both count it: code points, not UTF-16 units. */
export function charLength(value: string): number {
  return [...value].length;
}
