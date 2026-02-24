### oxlint-tsgolint

Missing android-arm64 binary. Lint runs but type-aware checks fail.
Non-fatal - commits still succeed.

### Setup Steps (Android/Termux)

After cloning, run in order:

1. `pnpm install` (ignore @matrix-org error, non-fatal)
2. `npm run build`
3. `pnpm ui:build`
4. `openclaw gateway run --token YOUR_TOKEN`
