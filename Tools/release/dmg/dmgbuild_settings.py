# What the .dmg holds and how its window looks (dmgbuild settings, used by Tools/release/make_dmg.sh).
#   dmgbuild -s dmgbuild_settings.py -D app=<LaneKeep.app> -D dir=<Tools/release/dmg> "LaneKeep <version>" <out>.dmg
# The window picture is background.png (1920×1200; the drawing is in the top-left 800×710, the rest is
# the same color) and background@2x.png, which dmgbuild joins into one TIFF. Its source is
# background.html; the icon positions (centers) below match the drawing there. The app is copied with
# ditto, so its signature stays intact (make_dmg.sh checks).
import os.path
import unicodedata

app = defines["app"]  # noqa: F821 (passed in by dmgbuild)
here = defines["dir"]  # noqa: F821


def on_disk(name):
    # Names on the .dmg (HFS+) are stored decomposed (NFD). The icon positions have to use the same
    # form, or Finder does not match them and the Japanese names land wherever it likes.
    return unicodedata.normalize("NFD", name)


format = "UDZO"
filesystem = "HFS+"
files = [app, os.path.join(here, "はじめに読む.txt"), os.path.join(here, "Read Me First.txt")]
# "設定を開く" is a shortcut to the old Security pane: opening it shows System Settings > Privacy &
# Security. On macOS 26.2 it scrolls to the Security section (where "Open Anyway" is) when System
# Settings is already open, and shows the top of the pane when it starts System Settings, so the
# instructions say to scroll to the bottom. A .webloc with an x-apple.systempreferences: address does
# not open on macOS 26 (-10400), so it is not used.
# Symlinks, not Finder aliases: some reports say macOS 26's Finder draws no icon for them in a .dmg
# (seen on the Mac this was made on), but the developer of DropDMG found them fine on Tahoe, and an
# alias made on one Mac may not resolve on another, which would break the drag to Applications.
symlinks = {"アプリケーション": "/Applications", "設定を開く": "/System/Library/PreferencePanes/Security.prefPane"}

background = os.path.join(here, "background.png")
# The size includes the title bar (that is how Finder reads it): the content is about 727 high on
# macOS 26 and about 732 on macOS 14 and 15, enough for everything down to the icon names (about 706,
# or 721 where Finder draws icons lower than asked). Wider or taller windows keep showing the same
# color up to 1920×1200.
window_rect = ((200, 60), (800, 760))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
arrange_by = None
label_pos = "bottom"
text_size = 13
icon_size = 80
icon_locations = {
    on_disk("LaneKeep.app"): (230, 80),
    on_disk("アプリケーション"): (570, 80),
    on_disk("設定を開く"): (414, 648),
    on_disk("はじめに読む.txt"): (84, 648),
    on_disk("Read Me First.txt"): (204, 648),
    # Visible only to people who show hidden files; parked in the empty top-right corner so that it
    # does not push the other icons around.
    ".background.tiff": (740, 40),
}
