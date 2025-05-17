<div align="center">
  <h1>💨 landspeeder 💨</h1>
  <p>More of an X-34 than an XP-38, but it should be enough</p>
</div>

## A not at all clever or customisable shell prompt.

Not at all customisable (yet).

Supports Zsh and macOS (so far).

## How to use it:

Build it:
```
zig build
```

Add this to your `.zshrc`:
```
precmd() {
    PROMPT="$(<path-to-landspeeder>/landspeeder/zig-out/bin/landspeeder)"
}
```
