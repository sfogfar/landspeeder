# landspeeder
A not at all customisable or clever shell prompt.

Supports zsh and macOS.

Build with:
```
zig build
```

Add this to your .zshrc to use it:
```
precmd() {
    PROMPT="$(<path-to-landspeeder>/landspeeder/zig-out/bin/landspeeder)"
}
```
