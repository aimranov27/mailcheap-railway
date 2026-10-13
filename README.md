# Mailcheap on Railway

Run [Mailcheap](https://github.com/marclou/mailcheap), Marc Lou's self-hosted newsletter app, on Railway with MongoDB. Write an issue, send it to your list through Amazon SES, and publish it on the web. SES costs about $0.10 per 1,000 emails.

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/TEMPLATE_CODE?utm_medium=integration&utm_source=template&utm_campaign=mailcheap)

## What you get

- Mailcheap built from upstream source, pinned to a tested commit.
- MongoDB on a private network with its own volume.
- A generated admin password and session secret. The dashboard is locked from the first boot.
- Image uploads in the editor without Vercel Blob. Images are saved on the service volume and served from your app's domain.
- Daily checks for upstream changes. Each one is built and smoke-tested before it reaches you.

## After deploying

1. Open the Mailcheap service's public URL and go to `/login`.
2. Log in with `ADMIN_EMAIL` and `ADMIN_PASSWORD` from the service's **Variables** tab. The password was generated for you.
3. Create a newsletter. Turn on **Archive** to get a public page with a signup form at `/archive/<slug>`.

You can collect subscribers right away. Sending needs Amazon SES and Upstash QStash:

4. Set up SES as described in [Mailcheap's README](https://github.com/marclou/mailcheap#3-amazon-ses): verify a sending domain, create a configuration set, an SNS topic and an IAM user. Use `https://<your-domain>/api/webhooks/ses` as the SNS endpoint.
5. Fill in the `SES_*` variables.
6. Create a free [Upstash QStash](https://console.upstash.com/qstash) account and fill in the three `QSTASH_*` variables. QStash calls your app to send each batch of 50 emails and to run scheduled sends.
7. Set `SENDING_ENABLED` to `true`. Railway redeploys the service.

If you move the app to your own domain, update `APP_URL` before your first send. Links in sent emails and uploaded images use it, and old emails keep pointing at the old URL.

## Variables

| Variable | Default | Purpose |
|---|---|---|
| `ADMIN_EMAIL` | you fill it in | Dashboard login. Test emails and alerts go here |
| `ADMIN_PASSWORD` | generated | Dashboard password, 12 or more characters |
| `SESSION_SECRET` | generated | Signs sessions and every link in your emails. Don't change it after your first send |
| `MONGODB_URI` | MongoDB service | Connection string with the `mailcheap` database |
| `APP_URL` | `https://${{RAILWAY_PUBLIC_DOMAIN}}` | Public URL used in email links and image URLs |
| `SENDING_ENABLED` | `false` | Nothing is sent unless this is `true` |
| `SES_REGION` | `us-east-1` | Your SES region |
| `SES_ACCESS_KEY_ID`, `SES_SECRET_ACCESS_KEY` | empty | IAM user keys for SES |
| `SES_CONFIGURATION_SET` | empty | Configuration set that publishes events to SNS |
| `SES_SNS_TOPIC_ARN` | empty | SNS topic Mailcheap accepts at `/api/webhooks/ses` |
| `QSTASH_TOKEN`, `QSTASH_CURRENT_SIGNING_KEY`, `QSTASH_NEXT_SIGNING_KEY` | empty | Needed to send campaigns and schedule them |
| `ALERT_FROM` | empty | Optional. From address for alert emails, on your verified domain |

Mailcheap also reads `SEND_RATE_PER_SECOND`, `ARCHIVE_HOSTS`, `QSTASH_URL` and `UPSTASH_REDIS_REST_URL`/`UPSTASH_REDIS_REST_TOKEN`. Add them if you need them. Upstash Redis is not needed on a single Railway service: rate limits are counted in memory.

Changing `ADMIN_EMAIL` or `ADMIN_PASSWORD` signs out every session. Public networking should point at port `8080`, the port Railway gives the service by default.

Welcome and confirmation emails go out through SES directly. Test emails do too. Only campaign sends and scheduling need QStash.

## Storage

- MongoDB keeps contacts, campaigns and stats on its volume at `/data/db`.
- Mailcheap's volume is mounted at `/data`. Uploaded images live in `/data/uploads` and are served at `APP_URL/uploads/...`. Emails you send link to these files, so keep the volume.

## How uploads work without Vercel Blob

Upstream Mailcheap stores editor images in Vercel Blob. This template applies a small patch at build time (`patches/`):

- `lib/blob.js` saves each image to the volume with a random suffix and returns its URL on your domain.
- `app/uploads/[...path]/route.js` serves those files publicly with a one-year cache header.
- `proxy.js` gets one line so `/uploads/` is reachable without a login, like Blob's public CDN.

The build checks that upstream code still matches before patching and stops if it doesn't, so a breaking upstream change is never deployed.

## Updates

Mailcheap has no releases, so the template follows the `main` branch. A GitHub Action checks it once a day. When there is a new commit, the template builds it and runs the smoke test (`scripts/smoke-test.sh`). Only commits that pass are merged. Failures open an issue instead.

When a bump lands, Railway shows an **update available** notice in your project. Updates are opt-in: apply them when it suits you. Your volumes are kept.

## Local testing

`scripts/smoke-test.sh` builds the image and starts it with MongoDB from `docker-compose.yml`. It checks that the dashboard needs a login, that login and the main pages work, that a reader can subscribe from the public archive, that uploads work, that sending without SES credentials fails without crashing, and that data survives a restart.

## License

The files in this repository are MIT licensed. Mailcheap is [MIT](https://github.com/marclou/mailcheap/blob/main/LICENSE), made by [Marc Lou](https://x.com/marclou). It is built from source with the upload patch described above.
