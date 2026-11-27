# EasyPanel deployment

This guide supports a standalone FCC App service or the combined Paperclip + FCC Compose stack. Do not create a second Paperclip instance if one is already deployed.

## Standalone FCC App (recommended for existing Paperclip)

1. In the same EasyPanel project as Paperclip, create an **App** service named `fcc`.
2. Source: GitHub, `Soatrix/FCC-Docker`, branch `main`, build path `/` (repository root). Builder: Dockerfile, path `docker/fcc/Dockerfile`. Leave the startup command unchanged (`fcc-server`). Alternatively select Docker Image and use a published `ghcr.io/soatrix/free-claude-code:<tag>`.
3. Add a persistent Volume mount at `/root/.fcc` (e.g. `fcc-config`). Use one FCC replica per config volume.
4. In the FCC service environment, set `NVIDIA_NIM_API_KEY` to your own key, `MODEL=nvidia_nim/nvidia/nemotron-3-ultra-550b-a55b` (or another supported model), and optionally `FCC_PROXY_TOKEN` to a random token (`openssl rand -hex 32`). The image binds `0.0.0.0:8082`, disables automatic browser opening, and enables API auth when the token is supplied. Never expose an unauthenticated FCC instance publicly. No domain or published port is needed for internal traffic.
5. Deploy. In the FCC console, run `curl -fsS http://127.0.0.1:8082/health`. For model discovery with auth, use `curl -fsS -H "Authorization: Bearer $FCC_PROXY_TOKEN" 'http://127.0.0.1:8082/v1/models?view=messages'`.
6. From Paperclip, use the FCC service's EasyPanel internal DNS name (typically `<project>_fcc` for an App service) and port `8082`. Verify from the Paperclip console with `curl -fsS http://<project>_fcc:8082/health`. Use the actual internal hostname displayed by EasyPanel. Set `ANTHROPIC_BASE_URL=http://<project>_fcc:8082`, `ANTHROPIC_AUTH_TOKEN` to the configured gateway token (or `fcc-local` without auth), and the Claude environment settings in the combined Compose example. Remove competing `ANTHROPIC_API_KEY` settings. Never set the NVIDIA key in Paperclip.

For a standalone Compose deployment instead, use build path `/deploy`, compose file `fcc-only.yml`, enable `.env` creation and set the same FCC variables. Verify the network reachability from Paperclip; separate Compose projects need a shared network or an appropriate internal route.

The upstream `fcc-claude` wrapper manages a local proxy and is not a remote launcher. For a separate FCC service, the Paperclip Claude Code client connects to FCC's Anthropic-compatible API using its base URL. If Paperclip uses a managed AI connection instead of host environment routing, configure that connection to use the FCC gateway and avoid mixing credentials in project `.claude/settings.json`.

## Combined Compose deployment

The combined Compose stack lives at `deploy/docker-compose.yml`.

## 1. Create the Compose service

In EasyPanel:

1. Create a new **Compose** service.
2. Select this repository and branch `main`.
3. Set the project/build path to `/deploy`.
4. Select compose file `docker-compose.yml` inside that path. If your EasyPanel version asks for a repository-relative path instead, enter `deploy/docker-compose.yml`. Do not mix the two conventions.
5. Let EasyPanel pull images from GHCR. The `fcc` image is `ghcr.io/soatrix/free-claude-code:${FCC_IMAGE_TAG:-latest}`; change the owner to your lowercase GitHub owner if different.

The compose file intentionally has no `container_name` and no `ports:` section. Never add a host port to `fcc`.

## 2. Enable `.env` creation

In the Compose service settings, enable **Create `.env` file** / **Generate `.env` from environment** (label varies by EasyPanel version). This writes the values entered in the UI into a `.env` file next to the compose file so `${VAR}` substitution works.

Do not commit a real `.env` to the repository. `deploy/.env.example` is a template only.

## 3. Fill in environment variables

Set these in the EasyPanel service environment:

| Variable | Where it is used | Notes |
| --- | --- | --- |
| `NVIDIA_NIM_API_KEY` | `fcc` only | Required. Never put this on Paperclip or agents. |
| `FCC_PROXY_TOKEN` | `fcc`, `paperclip` | Optional shared API token; generate with `openssl rand -hex 32`. |
| `PAPERCLIP_IMAGE_TAG` | `paperclip` | Optional image override; defaults to the existing pinned SHA. |
| `MODEL` | `fcc` | Defaults to `nvidia_nim/nvidia/nemotron-3-ultra-550b-a55b`. |
| `FCC_IMAGE_TAG` | `fcc` image | Use an immutable tag such as `6.19.58` or `sha-abc1234`. `latest` is mutable. |
| `PAPERCLIP_PUBLIC_URL` | `paperclip` | Required, e.g. `https://paperclip.example.com`. |
| `BETTER_AUTH_SECRET` | `paperclip` | Required; generate with `openssl rand -hex 32`. |
| `PAPERCLIP_TOOL_ACTION_SIGNING_SECRET` | `paperclip` | Required; generate with a different `openssl rand -hex 32`. |
| `PAPERCLIP_DEPLOYMENT_MODE` | `paperclip` | Defaults to `authenticated`. |
| `PAPERCLIP_DEPLOYMENT_EXPOSURE` | `paperclip` | Defaults to `public`. |

Generate secrets on the EasyPanel host or locally, then paste them into the UI:

```bash
openssl rand -hex 32
openssl rand -hex 32
```

## 4. Add the domain

Add an EasyPanel domain/route to service **`paperclip`**, internal port **3100**.

Do **not** add a domain or route to `fcc`. FCC is internal only and is reached by Paperclip at `http://fcc:8082`.

## 5. Find and copy the Deployment Trigger URL

1. Open the Compose service in EasyPanel.
2. Go to **Settings** → **Deployment Trigger URL** (also called **Deploy Hook** or **Webhook URL**).
3. Copy the entire URL, including any token in the path or query string.
4. Optionally add it as the GitHub Actions secret `EASYPANEL_DEPLOY_URL`. Without the secret, build/publish still succeeds and the deploy step is skipped.

Treat this URL as a credential. If it leaks, rotate it in EasyPanel and update the GitHub secret. The deploy scripts never print the URL or tokens.

## 6. Verify the deployment

Run these on the EasyPanel host:

```bash
docker ps --format '{{.Names}}\t{{.Image}}'
docker exec -it <paperclip-container> sh -lc 'curl -fsS http://127.0.0.1:3100/api/health'
docker exec -it <paperclip-container> sh -lc 'claude -p "Reply with exactly: FCC GLOBAL OK" --model claude-sonnet-4-6 --max-turns 1'
```

The `claude` command should print `FCC GLOBAL OK`. That proves global routing through `ANTHROPIC_BASE_URL=http://fcc:8082` works without an agent-level NVIDIA key.

Inspect FCC logs if needed:

```bash
docker logs <fcc-container> --tail 200
docker exec -it <fcc-container> sh -lc 'ls -la /root/.fcc/logs'
```

## 7. Manual deploy and rollback

From the GitHub UI, run **Deploy FCC to EasyPanel** with an immutable tag, or locally:

```bash
make deploy IMAGE_TAG=sha-abc1234
make rollback IMAGE_TAG=6.19.58
```

Set `FCC_IMAGE_TAG` in the EasyPanel environment **before** triggering a pinned deployment or rollback. The deployment webhook does not set environment variables.
