# landspeeder
A not at all customisable or clever shell prompt for my personal use.

Add this to your .zshrc to use it:
```
precmd() {
    PROMPT="$(~/repos/landspeeder/zig-out/bin/landspeeder)"
}
```
