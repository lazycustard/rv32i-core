# Performance

Where the cycles go, and what the two branch-prediction structures bought.
See the [README](../README.md) for the summary.


The core counts cycles, retired instructions, stalls, branches and taken
branches in hardware. `mcycle` and `minstret` are 64 bits because that is
what the specification says they are; they become those CSRs when Zicsr
lands.

## Branch prediction: before and after

Branches dominated the cost. Every taken branch flushed two instructions,
because the core only learned where a branch went once it reached EX. A
64-entry branch target buffer with 2-bit direction counters now guesses in
the fetch stage, and EX checks the guess.

Two structures, added in that order:

- a **64-entry BTB** with 2-bit direction counters, which remembers where
  each branch PC went last time;
- an **8-entry return address stack**, because a BTB cannot predict a
  function return. The same `ret` instruction goes back to whichever call
  site invoked it, so "where it went last time" is the wrong question. A
  call pushes the address it will come back to, and a return pops it.

| Program | No prediction | + BTB | + RAS | CPI | Total saved |
|---|---|---|---|---|---|
| `hello` | 169 | 147 | **145** | 1.42 → **1.21** | 14.2% |
| `fib` | 5,386 | 4,994 | **4,934** | 1.22 → **1.12** | 8.4% |
| `sort` | 2,656 | 2,368 | **2,314** | 1.43 → **1.24** | 12.9% |
| `primes` | 13,531 | 11,531 | **11,353** | 1.45 → **1.21** | 16.1% |

| Program | Mispredicts before | After | Control transfers | Accuracy |
|---|---|---|---|---|
| `hello` | 17 | 5 | 32 | 84% |
| `fib` | 484 | 258 | 839 | 69% |
| `sort` | 354 | 183 | 597 | 69% |
| `primes` | 2,061 | 972 | 3,599 | 73% |

The "before" column is not remembered, it is reproducible: `BP_ENABLE=0`
pins the prediction to not-taken, which is exactly what the core did before
the predictor existed.

The return stack is updated in fetch, speculatively, rather than in EX once
the instruction is known to be real — and it has to be. Unwinding a
recursion is a run of returns with an instruction or two between them, so a
second return is fetched before the first reaches EX; updating in EX leaves
it reading a stale top of stack. Moving the update to fetch removed 88
mispredictions from `primes` alone.

The cost is that a mispredicted path can push or pop entries that should
never have existed, and there is no checkpoint to restore from. That is an
accuracy loss and nothing else: EX checks every prediction, so a drifted
stack produces a slower result, never a wrong one.

```bash
BP=0 make programs     # baseline
make programs          # with prediction
```

## Where the cycles go

Every cycle is accounted for by one identity:

```
cycles = instructions + stalls + 2 x mispredictions + pipeline fill
```

| Program | Predicted | Actual |
|---|---|---|
| `hello` | 119 + 14 + 2x5 + 2 = 145 | 145 |
| `fib` | 4385 + 31 + 2x258 + 2 = 4934 | 4934 |
| `sort` | 1854 + 92 + 2x183 + 2 = 2314 | 2314 |
| `primes` | 9331 + 76 + 2x972 + 2 = 11353 | 11353 |

Exact on all four, before and after. `program_tb.v` asserts this rather than
leaving it as an observation: if the pipeline's valid bit were wrong and
flushed instructions counted as retired, the residual would go negative and
CPI would quietly look better than the core is. Forcing the valid bit high
fails all four programs with `counter accounting is impossible`.

## What the numbers say

**Stalls were never the problem.** Load-use stalls are well under 1% of
cycles, so forwarding is doing its job and there is nothing to win there.

**`fib` still gains least, and that is informative.** The return stack
fixed its returns, but 69% accuracy means what remains is conditional
branches, not returns: recursive Fibonacci turns on `n < 2`, which
alternates in a pattern a per-branch 2-bit counter cannot learn. Neither a
bigger BTB nor a deeper stack helps there. It would take a history-based
predictor, one that correlates a branch with the outcomes of recent ones —
which is where this would go next.

**The return stack's depth turned out not to matter.** Raising it from 8 to
16 and then 32 changed nothing at all, which ruled out the obvious first
theory — that `fib`'s recursion was simply deeper than the stack. The
actual limit was *when* the stack was updated, not how big it was.

