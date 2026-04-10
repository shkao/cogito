# Cogito Roadmap

## Design Principles

Cognitive engagement has four levels: Decoding, Comprehension, Reasoning, and Metacognition. Most readers spend most of their time at the bottom — looking up what a word means, parsing a sentence, getting past the surface. The goal is to move up.

Good AI reading tools should pull the reader toward Reasoning and Metacognition, not replace the thinking. An AI that hands you the answer keeps you at Decoding. An AI that gives you just enough to keep going — a translation, a definition, a visual explanation of a concept — lets you do the harder work yourself.

Every feature in Cogito should ask: does this help the reader think, or does it think for them?

Joshi and Vogel (CHI 2026) studied AI margin notes in document readers across three experiments and found results that reinforce this directly. A few findings worth internalizing:

**Margin placement over separate panels.** Notes positioned spatially adjacent to the referenced text outperformed side panels and modal dialogs. The reader's eye stays on the page. This is why translation cards appear in the Cornell panel next to the selected word, not in a toolbar or floating window.

**Manual trigger over automation.** Users who initiated note generation themselves — by selecting text — reported higher psychological ownership and satisfaction than users who received auto-generated notes. Comprehension was the same either way, but ownership was not. Cogito features should require deliberate action from the reader.

**Structured note types over free-form.** Definitions, summaries, and recall questions each serve a different cognitive function. A translation is a definition (Decoding). A step-by-step figure animation is closer to Comprehension. The next tier — asking the reader to connect a concept to something else in the chapter — starts to reach Reasoning. Features should be designed with this ladder in mind, not collapsed into a single "ask AI" interaction.

**Active recall over passive delivery.** Fill-in-the-blank and generative prompts outperformed plain definitions for long-term retention. A future Cogito feature could follow a definition with a question: "how does this term connect to what you read on the previous page?" That small shift moves the interaction from Decoding to Reasoning.

The automation paradox — less AI involvement increases ownership without hurting comprehension — is the clearest design constraint in the paper. It gives a principled reason to keep AI in the background: present when called, invisible otherwise.

— Joshi, N. & Vogel, D. (2025). Designing and Evaluating AI Margin Notes in Document Reader Software. ACM CHI 2026. https://arxiv.org/abs/2509.09840

## Animate Figure

Textbook figures are static. A reader encounters a diagram of a neural network, a cell cycle, a circuit, and has to mentally reconstruct the process it represents from a frozen snapshot. Most readers just move on.

The idea: a button near a figure lets the reader animate it. Click it, and the figure comes alive in place -- the static image gives way to an animation that walks through the concept step by step. No separate window, no context switch. The diagram just moves.

Each step highlights a region, shows flow between elements, and pairs with a short explanation. The reader controls the pace: play, pause, step forward, step back, reset. When done, the original figure returns and they keep reading.
