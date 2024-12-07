# LaTeX Plugin for Micro

This repository contains a plugin
for the [micro](https://github.com/zyedidia/micro) editor
that makes it easier to write LaTeX files.

## Functionality

**This package is under development. Everything can change at any time.**

At present, this plugin provides the following functionality.
Most of them work only in buffers whose filetype is `tex`.

### Keybindings

- Greek letters are bound to keys like `Alt-a` for `\alpha` or `Alt-L` for `\Lambda`.
  The modifier can be configured, see below.
-  Entering `"` inserts  ``` `` ``` or `''`, depending on the context.
- Autoclosing of brackets is extended to `\(...\)`, `\[...\]` and `$...$`.

### Autocompletion

- When you press `TAB` at the end of the argument to `\ref{}`, it is autocompleted
  based on the labels defined in the file (with `\label{}`).
  This also works for some other macros besides `\ref`, see below.
- When you press `TAB` at the end of the argument to `\cite{}`, it is autocompleted
  based on the bibliographic references defined in the file (with `\bibitem{}`).
  If you use define databases via `\bibliography`, then the completion is instead based
  on the references defined in the databases.
  This also works for some other macros besides `\cite` and `\bibliography`, see below.

### Compilation

- The LaTeX file can be compiled with `latexmk` and afterwards viewed.
- If an error occurs, then the output of `latexmk` will be displayed, and the cursor
  will be placed on the line of the LaTeX file where the error occurred.

### New micro commands

- `insert text`: inserts `text` at the current cursor position.
  This can be used for binding keys like
  ```
  bind F1 "command:insert '\\section'"
  ```
  (At present, the `insert` command is defined in the custom version of micro
  used by this plugin, see the installation instructions below.)
- `latex_insert_env env`: inserts
  ```
  \begin{env}
  
  \end{env}
  ```
   at the current cursor position and places the cursor inside the environment
- `latex_change_env env`: changes the currently active environment at the cursor position to `env`
- `latex_compile`: saves and compiles the current buffer with `latexmk`. The output is determined by `latex.mode`
- `latex_log`: opens the log buffer with the output of `latexmk`
- `latex_view`: opens the compiled file for the current buffer in a viewer

### New Lua functions

- `latex.insert_env(bp, env)`: analogous to the command `latex_insert_env`
- `latex.insert_env_prompt(bp)`: prompts for an environment and inserts it at the current cursor position
- `latex.change_env(bp, env)`: analogous to the command `latex_change_env`
- `latex.change_env_prompt(bp)`: prompts for an environment and changes the current environment to it
- `latex.compile(bp)`: analogous to the command `latex_compile`
- `latex.log(bp)`: analogous to the command `latex_log`
- `latex.view(bp)`: analogous to the command `latex_view`

## Installation

**NOTE:**
At present, this plugin requires some special functionality not included
in the official version of micro. It only runs with the `m3/latex` branch
of the fork [matthias314/micro](https://github.com/matthias314/micro).

Create a directory `~/.config/micro/plug/latex` and store the file `latex.lua` there.
Alternatively, clone this repository into such a directory,
```
git clone https://github.com/matthias314/micro-latex-plugin.git ~/.config/micro/plug/latex
```

To compile LaTeX files, [`latexmk`](https://ctan.org/pkg/latexmk/) is required.
You also need to define viewers for PDF and PostScript, see below.

## Configuration

### Global options

- `latex.smartbraces`: if `true` (default), insert `{}` after `^` and `_`
- `latex.smartquotes`: if `true` (default), change `"` to ``` `` ``` and `''`.
- `latex.keymod`: the modifier or key used for keybindings,
  for example `Alt` (default), `Alt` (modifier) or `<Shift-F2>` (key, with `<` and `>`)
- `latex.refmacros`: the list of macros that trigger autocompletion of labels.
  Default value is `{"ref", "eqref", "cref", "Cref"}`.
- `latex.citemacros`: the list of macro that trigger autocompletion of bibliographic references.
  Default value is `{"cite", "textcite", "parencite"}`.
- `latex.bibmacros`: the list of macro names that define databases with bibliographic references.
  Default value is `{"addbibresource", "addglobalbib", "addsectionbib", "bibliography"}`.
- `latex.dviviewer`: the program used for viewing DVI files. Default value is `xdvi`.
- `latex.psviewer`: the program used for viewing PostScript files. No default value.
- `latex.pdfviewer`: the program used for viewing PDF files. No default value.

### Buffer-local options

- `latex.mode`: the mode that determines the `latexmk` compilation target.
  Can be `pdf` (default), `pdfdvi`, `ps` or `dvi`, among others. 
