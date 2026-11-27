# EasyPanel deployment

This guide assumes an EasyPanel server connected to this GitHub repository. The Compose stack lives at `deploy/docker-compose.yml`.

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
| `MODEL` | `fcc` | Defaults to `nvidia_nim/nvidia/nemotron-3-ultra-550b-a55b`. |
| `FCC_IMAGE_TAG` | `fcc` image | Use an immutable tag such as `6.19.57` or `sha-abc1234`. `latest` is mutable. |
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
make rollback IMAGE_TAG=6.19.57
```

If the trigger does not override the image tag at runtime, update `FCC_IMAGE_TAG` in the EasyPanel service env first, then deploy.
