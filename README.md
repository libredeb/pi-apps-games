# <span style="color:#c0174a">>-</span> pi-apps-games

this repository contain all needed script to build `.deb` packages of pi-apps games in automated manner.

## How to use this repo?

1. Make sure you have required tools to generate `.deb` packages:
```sh
sudo apt-get install devscripts debhelper build-essential checkinstall
```

2. Navigate to desired game from a Terminal:
```sh
cd games/YOUR_DESIRED_GAME/
```

3. Build your `.deb` package:
```sh
./build.sh
```

4. Enjoy!