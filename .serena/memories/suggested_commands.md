# Suggested Commands

```bash
mix setup              # Initial setup: deps + DB + assets
mix phx.server         # Start dev server (localhost:4000)
mix test               # Run all tests
mix test path/to/test.exs      # Run specific test file
mix test path/to/test.exs:42   # Run specific test by line
mix test --failed      # Re-run failed tests
mix format             # Auto-format code
mix review             # Full quality gate: compile(warnings-as-errors) + credo(strict) + sobelow + dialyzer
mix precommit          # Pre-push checks: compile + deps.unlock --unused + format + test
```
