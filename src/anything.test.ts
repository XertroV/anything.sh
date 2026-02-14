import { describe, expect, it } from "bun:test";
import { getScriptCompact, getScriptFull } from "./scriptGenerator";

describe("safe mode script generation", () => {
  it("includes safe mode CLI flags in full and compact usage", () => {
    const full = getScriptFull("claude");
    const compact = getScriptCompact("claude");
    expect(full).toContain("--safe");
    expect(full).toContain("--allow-cmd <csv>");
    expect(full).toContain("--safe-yes");
    expect(full).toContain("--safe-show-code");
    expect(compact).toContain("--safe");
    expect(compact).toContain("--allow-cmd <csv>");
    expect(compact).toContain("--safe-yes");
    expect(compact).toContain("--safe-show-code");
  });

  it("wires safe-mode policy gates into both script variants", () => {
    const full = getScriptFull("claude");
    const compact = getScriptCompact("claude");
    expect(full).toContain("_safe_gate()");
    expect(full).toContain("if [[ $SAFE_MODE -eq 1 ]]; then");
    expect(full).toContain("SAFE MODE REJECTED");
    expect(compact).toContain("_safe_gate()");
    expect(compact).toContain("if [[ $SAFE_MODE -eq 1 ]]; then");
    expect(compact).toContain("SAFE MODE REJECTED");
  });

  it("uses safe provider command variant for claude in safe mode", () => {
    const full = getScriptFull("claude");
    expect(full).toContain('if [[ $SAFE_MODE -eq 1 ]]; then');
    expect(full).toContain('claude -p --model "$MODEL" <<< "$full_prompt"');
    expect(full).toContain('--dangerously-skip-permissions <<< "$full_prompt"');
  });

  it("fails fast for --agent + --safe without --safe-yes", () => {
    const full = getScriptFull("claude");
    const compact = getScriptCompact("claude");
    expect(full).toContain("--agent + --safe requires --safe-yes");
    expect(compact).toContain("--agent + --safe requires --safe-yes");
  });

  it("preserves provider-specific safe fallback warning when no safe command exists", () => {
    const full = getScriptFull("codex");
    expect(full).toContain("Safe mode has no provider-specific safe command");
    expect(full).toContain("using default CLI invocation");
  });
});
