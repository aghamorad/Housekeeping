# Housekeeping 0.28.1 — controls that answer your hand, and a Housekeeper that talks back

This release makes the app feel alive under the pointer and turns the assistant from a
canned-answer machine into a streaming, general-purpose one.

## Buttons you can feel

- Every themed button now springs on press, lifts under the pointer with a warm glow and
  a travelling light sheen, and gives a quiet trackpad tick. Disabled controls do not tick.
- Rail buttons, sidebar rows, the Dashboard action cards and the utility tiles share the
  same press travel and spring, so the whole app answers the same way.
- Everything is state-driven: a control costs nothing while the pointer is elsewhere, the
  idle guarantees are unchanged, and Reduce Motion turns the movement off.

## The Housekeeper writes while it answers

- Answers now stream in token by token for both the Apple system model and downloaded
  models. "Thinking…" appears only until the first word, then the reply fills in live.
- **Stop keeps what was written.** Stopping mid-answer saves the partial reply and marks
  it with an ellipsis instead of throwing it away.
- **Copy** on any answer, and three one-tap continuations under each reply: *Simpler*,
  *What next?*, *Example*.
- A rewritten system prompt makes the assistant warmer, more concrete and more willing to
  answer anything — not just housekeeping — while keeping the no-invented-files rule.

## Fixed: general questions were being buried in app status

A small on-device model handed a page of scan notes answers "how does the internet work?"
with remarks about the screen behind the chat panel. App context is now sent only when the
question is actually about this Mac or Housekeeping (or the chat is open about a specific
folder); general questions reach the model clean.

## Fixed: general questions were being hijacked by folder matching

"What is 17 times 23?" was answered with a list of folders named `23`. Folder evidence now
requires an explicit path, a named folder *plus* a folder noun, a distinctive name, or a
"this folder" reference with a folder on screen. A bare number or common word that happens
to match a folder name no longer turns a normal question into a filesystem question.

## Fixed: "What can you do?" invented features

That question keeps the exact list of Housekeeping's real screens; the model is instructed
not to invent tools beyond them. A small model asked what the app can do will happily
invent a password-vault feature; the app's own answer is the true one.

## Verified in this pass

- 375 safety assertions (including the new folder-hijack regression), background/MCP
  assertions, static UI audit, warnings-as-errors type check and Xcode build pass.
- Headless model probe: first token 1.7–3.3 s, complete 3.7–6.7 s on the Apple system model;
  answers reviewed for accuracy (17×23 = 391, a 120-word bill-to-law answer, tool list).
- Universal ZIP with both architectures, verified signature, source stamp and CLI on both
  slices, Bookbind runtime on both slices.
- Click-through on macOS 27.2 / M1 Pro: chat streaming, Stop keeping the partial answer,
  copy, follow-up chips, and the press/hover behaviour on the main controls.

## Limits, stated plainly

- Intel still verified through Rosetta on this Apple Silicon Mac, not physical hardware.
- The build is ad-hoc signed, not notarized.
- Apple's system model is a small on-device model; for harder reasoning the downloadable
  Qwen/Gemma options are still the better choice.
