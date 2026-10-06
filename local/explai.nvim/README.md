# explai.nvim

Understand code without leaving Neovim: explain it, ask about it, trace who calls it and
find where things are implemented. Answers stream into a floating window attached to the
code, using GitHub Copilot (the sign-in from `copilot.lua`; no extra setup).
Neovim counterpart of the Explai VS Code extension.

| Keys | Command | |
|---|---|---|
| `<leader>ae` | `:Explai` | Explain the selection (visual) or current line |
| `<leader>aE` | `:Explai!` | Same, in more detail |
| `<leader>aq` | `:ExplaiAsk {question}` | Ask about the selection; `<Up>` recalls earlier questions |
| `<leader>ak` | `:ExplaiCallers [focus]` | How is the function at the cursor reached? |
| `<leader>ai` | `:ExplaiFind {query}` | Find where something is implemented and jump there |
| `<leader>al` | `:ExplaiLast` | Bring back the last popup (opens its file if needed) |
| | `:ExplaiModel [id]` | Pick the Copilot model (remembered) |
| | `:ExplaiClose` | Close the popup |

## The popup

- Stays open until you close it: `q`/`<Esc>` inside it, `<Esc>` in the code, or entering
  insert mode. It is attached to the line, so it scrolls with the code.
- Press the same Explain key again to jump into the popup; `<C-w>w` works too.
- Inside: `y` copy · `o` open as a Markdown split · `m` more detail · `<CR>` jump to the step
  under the cursor (callers) · `e` explain the match (find) · `q` close.
- Same code + same question + unchanged buffer = cached answer, no new request.

## Trace callers

Builds the incoming call tree from the language server (Roslyn, clangd, …), then the model
fills in what LSP misses (interfaces, events/delegates, DI) using read-only tools and checks
the call sites. Shows 1–3 paths from entry point to target. All steps also go to the
quickfix list (`]q`/`[q`). Without a language server it falls back to text search.

## Find implementation

The model searches with read-only tools (LSP workspace symbols, ripgrep, file listing,
file reading, references, call hierarchy), then jumps to the best match and highlights it.
With several matches you get a picker; all matches go to the quickfix list.

## Requirements

Neovim 0.11+, `curl`, `rg`, and a GitHub Copilot sign-in (`:Copilot auth`).
Copilot tokens are passed to curl on stdin, never on the command line.
