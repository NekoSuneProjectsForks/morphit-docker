# Cloudflare + Nginx Proxy Manager

This guide publishes the Morphit web frontend through:

```text
Browser
  -> Cloudflare HTTPS
  -> your public IP:443
  -> Nginx Proxy Manager
  -> private Docker network
  -> morphit-web:8080
```

Morphit does **not** need a public host port when Nginx Proxy Manager (NPM) is running on the same Docker host. The included `docker-compose.yml` only exposes port `8080` to Docker networks.

## 1. Find the Docker network used by Nginx Proxy Manager

Find your NPM container:

```bash
docker ps --format 'table {{.Names}}\t{{.Image}}' | grep -i proxy
```

Then list the Docker networks attached to it:

```bash
docker inspect <npm-container-name> \
  --format '{{range $name, $_ := .NetworkSettings.Networks}}{{println $name}}{{end}}'
```

Typical names are:

```text
npm_default
nginx-proxy-manager_default
proxy
npm_proxy
```

Use an existing NPM network when possible. This survives Morphit container recreation and means you do not need to publish Morphit's port on the host.

If you intentionally want a dedicated shared network instead, create it with:

```bash
docker network create npm_proxy
```

Then add that external network to the NPM Compose stack as well. A permanent Compose configuration is preferred over manually running `docker network connect`, because a manually-added connection may disappear when NPM's container is recreated.

Example NPM Compose addition:

```yaml
services:
  app:
    # your existing NPM settings...
    networks:
      - npm_proxy

networks:
  npm_proxy:
    external: true
    name: npm_proxy
```

## 2. Configure Morphit

Clone this repository:

```bash
git clone https://github.com/NekoSuneProjectsForks/morphit-docker.git
cd morphit-docker
```

Create the local environment file:

```bash
cp .env.example .env
```

Edit `.env` and set `NPM_NETWORK` to the network discovered above:

```dotenv
MORPHIT_IMAGE=ghcr.io/nekosuneprojectsforks/morphit
MORPHIT_TAG=latest
NPM_NETWORK=npm_default
MORPHIT_CONTAINER_NAME=morphit-web
```

`MORPHIT_TAG=latest` follows the newest Morphit release successfully built by this repository. For a reproducible deployment, replace `latest` with a specific upstream release tag.

## 3. Start Morphit

```bash
docker compose pull
docker compose up -d
```

Check it:

```bash
docker compose ps
```

The container should become `healthy`.

You can also test the web server from inside the container:

```bash
docker exec morphit-web node -e \
  "fetch('http://127.0.0.1:8080/').then(async r=>{console.log(r.status); process.exit(r.ok?0:1)}).catch(e=>{console.error(e); process.exit(1)})"
```

There should normally be **no** `0.0.0.0:8080->8080` mapping in `docker ps`. NPM reaches Morphit over the Docker network instead.

## 4. Create the Cloudflare DNS record

In Cloudflare, create a DNS record for the hostname you want, for example:

```text
Type: A
Name: morphit
IPv4 address: YOUR_SERVER_PUBLIC_IP
Proxy status: Proxied (orange cloud)
```

If the server has working public IPv6 and you intend to accept IPv6 traffic, add the matching `AAAA` record as well. Do not add a stale or unreachable AAAA record.

Example resulting hostname:

```text
morphit.example.com
```

Only Nginx Proxy Manager needs to receive public HTTP/HTTPS traffic. Do not point Cloudflare directly at Morphit's internal port `8080`.

## 5. Create the Nginx Proxy Manager Proxy Host

In NPM, go to **Hosts -> Proxy Hosts -> Add Proxy Host**.

Use:

```text
Domain Names:       morphit.example.com
Scheme:             http
Forward Hostname:   morphit
Forward Port:       8080
Cache Assets:       Off
Block Common Exploits: On
Websockets Support: On
Access List:        Publicly Accessible
```

`morphit` works because the included Compose file gives the Morphit container that network alias. You may also use `morphit-web` if that is the container/service name visible on the same Docker network.

Do **not** enter:

```text
localhost
127.0.0.1
```

as the forward hostname from NPM. Inside the NPM container those addresses mean NPM itself, not the Morphit container.

No custom Advanced Nginx configuration should be necessary for the static Morphit frontend. Avoid adding a second CSP or security-header set unless you know it is compatible with Morphit's own frontend requirements.

## 6. Configure HTTPS in NPM

The recommended arrangement is HTTPS from the browser to Cloudflare **and** HTTPS from Cloudflare to NPM.

### Option A - Let's Encrypt in NPM

In the Proxy Host's **SSL** tab:

1. request/select a Let's Encrypt certificate for `morphit.example.com`,
2. enable **Force SSL**,
3. enable **HTTP/2 Support**,
4. enable HSTS only after HTTPS is confirmed working.

If the normal HTTP challenge is inconvenient behind Cloudflare, NPM supports Certbot DNS challenge providers. Use a narrowly-scoped Cloudflare API token rather than your Global API Key where possible.

### Option B - Cloudflare Origin CA

If this hostname will always remain behind Cloudflare, you can create a Cloudflare Origin CA certificate and import it into NPM as a custom certificate.

Cloudflare Origin CA certificates are intended for the Cloudflare-to-origin connection. Browsers do not generally trust them directly, so do not turn the DNS record grey-cloud while relying only on an Origin CA certificate.

## 7. Set Cloudflare SSL/TLS mode

After NPM has a valid certificate for the hostname, set Cloudflare to:

```text
SSL/TLS -> Overview -> Full (strict)
```

Do **not** use `Flexible` for this setup. Flexible TLS can create redirect problems and leaves the Cloudflare-to-origin leg unencrypted.

With Full (strict), the path is:

```text
Browser --HTTPS--> Cloudflare --HTTPS--> NPM --HTTP/private Docker network--> Morphit
```

The last HTTP hop is limited to the private Docker bridge network on the same host.

## 8. Recommended Cloudflare settings

For the Morphit hostname:

- keep the DNS record **Proxied**,
- use **Full (strict)** SSL/TLS,
- enable **Always Use HTTPS** if that matches the rest of your zone,
- leave Cloudflare caching on its normal/default behavior initially,
- do not create a `Cache Everything` rule for the whole application unless you have tested Morphit's service worker/update behavior,
- if an optimization feature such as Rocket Loader causes frontend problems, disable it for this hostname.

The Morphit image already sends a no-cache rule for `/service-worker.js` and long-lived caching for Svelte immutable assets.

## 9. Firewall / port forwarding

The normal public path should expose only NPM's web ports:

```text
TCP 80  -> Nginx Proxy Manager
TCP 443 -> Nginx Proxy Manager
```

NPM's admin port `81` should not normally be exposed to the public Internet. Restrict it to your LAN, VPN, trusted IPs, or another protected administrative path.

Morphit's `8080` port should remain private when NPM and Morphit share a Docker host.

## 10. Updating the running container

The GitHub Actions workflow in this repository only publishes a new `latest` image when Agorise publishes a new Morphit release. Docker Compose does not automatically replace an already-running container merely because the registry tag changed.

To update the deployment when you want to pull the newest published Morphit image:

```bash
cd morphit-docker
docker compose pull
docker compose up -d
```

Then remove unused old image layers if desired:

```bash
docker image prune -f
```

## 11. Troubleshooting

### NPM shows 502 Bad Gateway

Check both containers share the configured network:

```bash
docker inspect morphit-web \
  --format '{{range $name, $_ := .NetworkSettings.Networks}}{{println $name}}{{end}}'

docker inspect <npm-container-name> \
  --format '{{range $name, $_ := .NetworkSettings.Networks}}{{println $name}}{{end}}'
```

At least one network name must match.

Also check Morphit:

```bash
docker compose ps
docker compose logs --tail=100 morphit-web
```

### Cloudflare error 521

Cloudflare cannot establish a connection to your origin. Check that NPM is running, ports 80/443 reach NPM, and your firewall/router permits the traffic.

### Cloudflare error 525

The TLS handshake between Cloudflare and NPM failed. Check NPM's certificate and HTTPS listener.

### Cloudflare error 526

With Full (strict), Cloudflare rejected the certificate presented by NPM. Make sure the certificate is unexpired, covers the exact hostname, and is issued by a publicly trusted CA or Cloudflare Origin CA.

### Redirect loop

Make sure Cloudflare is not using Flexible mode. Use Full (strict) after NPM has a valid certificate.

### `network ... declared as external, but could not be found`

Your `.env` contains the wrong `NPM_NETWORK`, or that Docker network does not exist. Re-run the `docker inspect` command from step 1 and set the exact network name.
