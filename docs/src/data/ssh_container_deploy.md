# SSH Container Deploy

The `ssh-container-deploy` subaction automatically connects directly into remote VPS environments seamlessly configuring and booting the published container image.

## Usage
Provide the necessary connection variables inside `params_json`.

```yaml
- name: Deploy Container
  uses: uncoverthefuture-org/actions@master
  with:
    subaction: ssh-container-deploy
    params_json: |
      {
        "ssh_host": "${{ secrets.PROD_SERVER_IP }}",
        "ssh_user": "ubuntu",
        "image_tag": "${{ steps.build.outputs.image_tag }}"
      }
    secrets_json: ${{ toJSON(secrets) }}
```

## How It Works
1. Validates remote secure SSH keys injected via environments securely!
2. Interally writes `.env` payloads dynamically without pushing dotfiles to Source Control natively.
3. Automatically triggers Docker/Podman `pull` requests fetching the exact SHA hash natively matching `image_tag`.
4. Executes `docker compose up -d` wiping previous containers smoothly!
