# Cogito Roadmap

## Design Principles

Cognitive engagement has four levels: Decoding, Comprehension, Reasoning, and Metacognition. Most readers spend most of their time at the bottom, looking up what a word means, parsing a sentence, getting past the surface. The goal is to move up.

Good AI reading tools should pull the reader toward Reasoning and Metacognition, not replace the thinking. An AI that hands you the answer keeps you at Decoding. An AI that gives you just enough to keep going lets you do the harder work yourself.

Every feature in Cogito should ask: does this help the reader think, or does it think for them?

Joshi and Vogel (CHI 2026) studied AI margin notes in document readers across three experiments. Their results:

Notes adjacent to the text outperformed side panels and modal dialogs. The reader's eye stays on the page. This is why translation cards appear in the Cornell panel next to the selected word, not in a toolbar.

Users who triggered note generation themselves reported higher psychological ownership than users who received auto-generated notes. Comprehension was identical; ownership was not. Cogito features require a deliberate action from the reader.

Definitions, summaries, and recall questions each serve a different cognitive function. A translation is a definition (Decoding). A step-by-step figure animation sits closer to Comprehension. Asking the reader to connect a concept to something earlier in the chapter reaches Reasoning. Features should follow that progression, not collapse into a single "ask AI" interaction.

Fill-in-the-blank prompts outperformed plain definitions for long-term retention. A future feature could follow a translation with a question: how does this term connect to what you read on the previous page? That shift moves the interaction from Decoding to Reasoning without much overhead.

Less AI involvement increases ownership without hurting comprehension. Keep AI present when called, invisible otherwise.

— Joshi, N. & Vogel, D. (2025). Designing and Evaluating AI Margin Notes in Document Reader Software. ACM CHI 2026. https://arxiv.org/abs/2509.09840

Fu et al. (2025) tracked 15 undergraduates using AI while reading over eight weeks, 838 prompts across 239 sessions. The cognitive level breakdown: 59.6% Comprehension, 29.8% Reasoning, 8.5% Metacognition, 2.1% Decoding. Readers don't get stuck at Decoding; they get stuck at Comprehension.

Most sessions contained exactly three prompts, the assignment minimum. Under time pressure, students defaulted to the lowest-effort path regardless of their stated intentions. They knew active prompting was better and still didn't do it. The researchers called this the intention-behavior gap.

Students also used AI-generated summaries to decide which sections were worth reading at all, effectively outsourcing the reading itself. The tool stopped supporting reading and started replacing it.

Comprehension is the floor, not the goal. A word translation or a concept summary keeps the reader there. Making passive use frictionless guarantees passive use; if asking "what does this mean?" is as easy as asking "how does this connect to X?", readers will always ask the first question.

— Fu, Y., Wester, J., Van Berkel, N., & Hiniker, A. (2025). Self-Regulated Reading with AI Support: An Eight-Week Study with Students. https://arxiv.org/abs/2602.09907

## Animate Figure

Textbook figures are static. A reader encounters a diagram of a neural network or a circuit and has to mentally reconstruct the process it represents from a frozen snapshot. Most readers just move on.

The idea: a button near a figure lets the reader animate it. Click it, and the figure comes alive in place. The static image gives way to an animation that walks through the concept step by step. No separate window, no context switch. The diagram just moves.

Each step highlights a region, shows flow between elements, and pairs with a short explanation. The reader controls the pace: play, pause, step forward, step back, reset. When done, the original figure returns and they keep reading.
