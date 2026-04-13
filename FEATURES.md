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

Sarkar (TEDAI Vienna, 2025) names this failure mode "outsourced reason" and proposes a concrete alternative: provocations. A provocation is not an answer. It raises an alternative, identifies a fallacy, or offers a counterargument. The reader can dismiss it; it is not meant to apply every time. Drosos et al. (2025) showed that provocations demonstrably restore critical thinking in AI-assisted workflows and increase outcome diversity.

The implication for Cogito: a word translation is a starting point, not a destination. After showing "感知器", the tool could follow with "this term is used differently in chapter 5, does that change your reading here?" That question moves the interaction from Comprehension to Reasoning. The reader can dismiss it and move on, or pause and think.

Sarkar's prototype has no chat interface. The AI responds to what the reader is doing, not to queries. Assistance is contextual and in-place, never a conversation the reader initiates from scratch.

Sarkar names three design principles: preserve material engagement, offer productive resistance, scaffold metacognition. The translation card covers the first. A provocation added immediately after handles the other two.

— Sarkar, A. (2025). Artificial Intelligence as a Tool for Thought. TEDAI Vienna. https://www.microsoft.com/en-us/research/wp-content/uploads/2025/11/TEDAI_2025_AI_as_Tool_for_Thought_V1.pdf

## Ask Question (RAG)

Full-text search (Cmd+F) finds exact strings. It fails when the reader has a concept in mind but not the exact wording the author used. "What is VAE?" returns nothing if the chapter says "variational autoencoder" but never abbreviates it.

Ask Question (Cmd+J) uses retrieval-augmented generation. On PDF open, every page is indexed. When the reader asks a question, BM25-lite keyword matching retrieves the top pages instantly (no LLM). The app navigates to the best page and highlights the defining mention of the query term. Then one LLM call generates a self-contained answer from the retrieved passages, streamed token-by-token into the question bar.

For "What is X?" questions, the prompt automatically expands to request ELI12-style explanations with concrete analogies. A closing metaphor in the reader's target language (configurable in Settings) reinforces the concept using everyday objects. LaTeX in the LLM output is post-processed to unicode (σ², μ, x̂).

This sits between Decoding and Comprehension. The reader still has to engage with the material once they arrive. The feature removes the friction of finding where to look, not the work of understanding what's there.

## Chapter Progress Bar

Reading a paper is easier when you know where you are in its argument. The introduction, methods, results, and discussion ask different things from the reader. Losing track of structure is one reason readers drift into passive scanning.

A persistent progress bar shows position within the current chapter or section, drawn from the document outline. Each segment corresponds to a named section. The reader sees how far into the current section they are and what comes next.

The bar does not track time or pace. It tracks structure. The goal is orientation, not performance measurement. A reader who knows they are two pages into a five-page methods section reads differently than one who has no sense of where the section ends.

## Animate Figure

Textbook figures are static. A reader encounters a diagram of a neural network or a circuit and has to mentally reconstruct the process it represents from a frozen snapshot. Most readers just move on.

The idea: a button near a figure lets the reader animate it. Click it, and the figure comes alive in place. The static image becomes an animation that walks through the concept step by step, in place, with no separate window.

Each step highlights a region, shows flow between elements, and pairs with a short explanation. The reader controls the pace: play, pause, step forward, step back, reset. When done, the original figure returns and they keep reading.

## Executable Code Blocks

Textbook code is dead on arrival. A reader encounters a k-means implementation in Chapter 10 and has to switch to a terminal, re-type or copy-paste the snippet, install the right packages, fix the inevitable extraction errors, and run it. Most readers skip this entirely. The code becomes decoration.

The idea: detect code blocks in the PDF and present them as editable, runnable cells in a panel beside the page. The reader sees the textbook on the left and the extracted code on the right, ready to execute. Click Run, see the output. Change a parameter, run again. The loop between reading and doing shrinks to zero.

This sits squarely at Reasoning. A translation tells you what a word means. An animation shows you how a process works. Running code forces you to predict what will happen, observe what actually happens, and reconcile the difference. That predict-observe-reconcile cycle is where understanding forms.

The panel appears on demand (Cmd+K). The reader triggers detection deliberately, consistent with the ownership principle from Joshi and Vogel. No code cells appear until the reader asks for them. The panel shows cells for the current chapter; switching chapters clears the workspace and starts fresh, because textbook chapters are self-contained units.

Cells share a persistent Python session within a chapter. Run `X = load_data()` in cell 1, then `model.fit(X)` in cell 3, and it works. This matches how textbook code builds incrementally. Matplotlib plots render inline as images below the cell that produced them.

Detection uses heuristic pattern matching on the raw PDF text: `>>>` prompts, `import` statements, `def`/`class` declarations, indented blocks. For ambiguous cases, the local LLM classifies whether a text region is code. The reader can also add blank cells and write their own code, turning the panel into a scratch pad for experimentation alongside the reading.

The kernel runs as a local Python subprocess with stdin/stdout JSON messaging, following the same process-spawning pattern used for video generation. No remote server, no network dependency, no Jupyter installation required. The reader's existing Python environment (numpy, pandas, sklearn, matplotlib) is all that's needed.
