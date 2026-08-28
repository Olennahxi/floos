Fonts are not shipped with this addon.

Tahoma, Tahoma Bold, Segoe UI, Consolas and Verdana are Microsoft fonts.
Redistributing them is not permitted, so they are not in the download.

You do not need to do anything: on Windows the addon loads them straight
from C:\Windows\Fonts, which you already have. Every font in the Fonts
dropdown will just work.

If you are on a setup without those fonts, pick "Agave" in
/floos -> General -> Font. That is Ashita's built-in font and needs no files.

To bundle your own instead, drop a .ttf in this folder using one of these
names and it will be preferred over the system copy:

    tahomabd.ttf    Tahoma Bold (Default)
    tahoma.ttf      Tahoma
    segoeui.ttf     Segoe UI
    consola.ttf     Consolas
    verdana.ttf     Verdana
