# Operations

## Versioning strategy

`config/fcc-version.json` is the source of truth for the FCC package version. The build workflow uses:

1. The tag name for `fcc-v*` pushes, e.g. `fcc-v6.19.57` → `6.19.57`.
2. The manual `fcc_version` input when supplied.
3. `config/fcc-version.json` otherwise.

Published tags:

- `ghcr.io/soatrix/free-claude-code:<version>` — immutable release tag.
- `ghcr.io/soatrix/free-claude-code:sha-<short-sha>` — immutable commit tag; use this for deploys and rollbacks.
- `ghcr.io/soatrix/free-claude-code:latest` — mutable convenience tag.

Never delete or rewrite version or sha tags. `latest` may change at any time.

## Build a specific FCC version

```bash
make publish \
  FCC_VERSION=6.19.57 \
  IMAGE=ghcr.io/soatrix/free-claude-code:6.19.57
```

This builds locally, smoke-tests the version and default model, then pushes a multi-arch image. To build without publishing:

```bash
make build FCC_VERSION=6.19.57 IMAGE=ghcr.io/soatrix/free-claude-code:6.19.57
make smoke IMAGE=ghcr.io/soatrix/free-claude-code:6.19.57
```

For automation, run the **Build and publish FCC** workflow or push a tag:

```bash
git tag fcc-v6.19.57
git push origin fcc-v6.19.57
```

Set repository variable `DEPLOY_ON_PUBLISH=true` to deploy automatically on tag pushes.

## Roll back

1. Pick an existing immutable version or sha tag from GHCR.
2. If the EasyPanel Compose service does not accept runtime tag overrides, set `FCC_IMAGE_TAG=<tag>` in the service environment first.
3. Trigger the deploy:

   ```bash
   EASYPANEL_DEPLOY_URL=... make rollback IMAGE_TAG=sha-abc1234
   ```

   Or run **Deploy FCC to EasyPanel** with `image_tag=sha-abc1234`.

4. Verify with the commands in [EASYPANEL.md](EASYPANEL.md#6-verify-the-deployment).

Do not roll back by repointing `latest` to an older digest. Use an immutable tag instead.

## Respond to upstream FCC releases

The daily **Check upstream FCC releases** workflow compares `config/fcc-version.json` with the latest release from `Alishahryar1/free-claude-code`. If different, it opens a PR containing the new version and upstream release notes. It does not auto-merge and does not publish anything.

Review the PR for breaking changes, merge it, then run the **Build and publish FCC** workflow with blank `fcc_version` so it reads the updated config. Smoke tests must pass before publishing.

Manual check:

```bash
make check-upstream
git diff -- config/fcc-version.json
```

## Inspect logs

```bash
docker logs <fcc-container> --tail 200
docker logs <paperclip-container> --tail 200
docker exec -it <fcc-container> sh -lc 'ls -la /root/.fcc/logs'
docker exec -it <fcc-container> sh -lc 'tail -n 100 /root/.fcc/logs/*'
```

Replace `<fcc-container>` and `<paperclip-container>` with names from:

```bash
docker ps --format '{{.Names}}\t{{.Image}}'
```

If FCC is unhealthy, check that `/root/.fcc` is writable in the `fcc-config` volume and that the health endpoint responds inside the container:

```bash
docker exec -it <fcc-container> sh -lc 'curl -fsS http://127.0.0.1:8082/v1/models?view=messages'
```

## NVIDIA NIM auth or model errors

1. Confirm `NVIDIA_NIM_API_KEY` is set on the **`fcc`** service only. Check the EasyPanel env UI; never paste the key into Paperclip or agent configs.
2. Confirm `MODEL` matches an NVIDIA NIM model ID available to your key. Default: `nvidia_nim/nvidia/nemotron-3-ultra-550b-a55b`.
3. Run `docker exec -it <fcc-container> fcc-doctor` for FCC-specific diagnostics.
4. Check FCC logs for `401`, `403`, or `model not found` messages.
5. Restart only after correcting the runtime env. Do not rebuild the image to change a secret.

## Managed AI connection conflicts

Symptoms include Paperclip reporting a conflicting provider, agent-level API keys, or Claude ignoring the global base URL. Fix by:

- Keeping `CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST=1` and `ANTHROPIC_BASE_URL=http://fcc:8082` on the `paperclip` service.
- Removing `ANTHROPIC_BASE_URL`, `ANTHROPIC_API_KEY`, `NVIDIA_NIM_API_KEY`, and custom provider settings from individual agents.
- Restarting Paperclip so all `claude` processes inherit the service-level environment.

## Confirm global routing

Inside the Paperclip container, run Claude without any NVIDIA key:

```bash
docker exec -it <paperclip-container> sh -lc 'claude -p "Reply with exactly: FCC GLOBAL OK" --model claude-sonnet-4-6 --max-turns 1'
```

Expected output: `FCC GLOBAL OK`.

If this fails, verify that Paperclip can resolve `fcc` and that `http://127.0.0.1:8082` is not configured anywhere. `127.0.0.1` inside Paperclip refers to Paperclip itself, not the FCC sidecar.
