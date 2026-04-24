# pi-apps-games

Static landing page showcasing hand-picked games from [pi-apps.io](https://pi-apps.io/)
repackaged as native `.deb` files for Raspberry Pi.

Deployed on **GitHub Pages** — no build step, no frameworks, pure vanilla HTML/CSS/JS.

---

## Repository structure

```
pi-apps-games/
├── index.html                     # Main landing page
├── assets/
│   ├── css/main.css               # Styles (raspberry/dark palette)
│   ├── js/main.js                 # Copy-to-clipboard
│   └── img/                       # Game screenshots (.gitkeep)
└── packages/
    ├── arm64/                     # 64-bit architecture (Pi 4/5, Zero 2 W 64-bit)
    │   └── {game}/
    │       ├── bookworm/          # Debian 12 / current Raspberry Pi OS
    │       │   ├── .gitkeep
    │       │   └── {game}_{ver}_arm64.deb
    │       └── trixie/            # Debian 13
    │           └── .gitkeep
    └── armhf/                     # 32-bit architecture (Pi 3, legacy Zero)
        └── {game}/
            ├── bookworm/
            │   └── .gitkeep
            └── trixie/
                └── .gitkeep
```

### Naming convention

```
{name}_{version}_{arch}.deb
```

Examples:
- `supertuxkart_1.4_arm64.deb`
- `cave-story_2.6.4_armhf.deb`
- `openmsx_19.1_arm64.deb`

---

## Adding a new game

### 1. Create the folder structure

```bash
GAME=game-name

for arch in arm64 armhf; do
  for distro in bookworm trixie; do
    mkdir -p "packages/$arch/$GAME/$distro"
    touch "packages/$arch/$GAME/$distro/.gitkeep"
  done
done
```

### 2. Copy the DEB packages

```bash
cp my-game_1.0_arm64.deb packages/arm64/game-name/bookworm/
cp my-game_1.0_armhf.deb packages/armhf/game-name/bookworm/
```

If the game only supports one architecture or one Debian version,
skip the folders that don't apply (but keep the `.gitkeep` in the ones that do).

### 3. Add the card in index.html

Copy one of the existing `<article class="game-card">` blocks in `index.html`
and update: name, version, description, download paths, and compatibility badges.

---

## Deploying to GitHub Pages

### Option A — `gh-pages` branch (recommended)

```bash
git checkout --orphan gh-pages
git add .
git commit -m "deploy: initial release"
git push origin gh-pages
```

In the repo's **Settings → Pages**, select:
- Source: `Deploy from a branch`
- Branch: `gh-pages` / `/ (root)`

### Option B — `main` branch directly

In **Settings → Pages**:
- Source: `Deploy from a branch`
- Branch: `main` / `/ (root)`

The page will be available at:
```
https://{username}.github.io/{repo-name}/
```

---

## Checking your architecture on Raspberry Pi

```bash
# Check system architecture
uname -m
# aarch64 → arm64
# armv7l  → armhf

# Check Debian/Raspberry Pi OS version
cat /etc/os-release | grep VERSION_CODENAME
# bookworm → Debian 12
# trixie   → Debian 13
```

---

## Included games

| Game              | Version            | arm64 | armhf | bookworm | trixie |
|-------------------|--------------------|:-----:|:-----:|:--------:|:------:|
| SuperTuxKart      | 1.4                | ✓     | ✓     | ✓        | ✓      |
| Quake (darkplaces)| 20140513           | ✓     | ✓     | ✓        | ✓      |
| Cave Story        | NXEngine 2.6.4     | ✓     | ✓     | ✓        | ✓      |
| Chromium B.S.U.   | 0.9.16.1           | ✓     | ✓     | ✓        | ✓      |
| OpenMSX           | 19.1               | ✓     | ✓     | ✓        | ✓      |
| Minecraft Java    | mc-installer       | ✓     | —     | ✓        | ✓      |

---

## License

Landing page source code: **GPL-3.0**.
Games belong to their respective authors and retain their own licenses.
This project is not officially affiliated with [pi-apps.io](https://pi-apps.io/).
