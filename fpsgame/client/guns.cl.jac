"""Weapon display names + blurbs, indexed by the sim's GUN_* ids.

They live in cl{} because str does not cross the wasm boundary cheaply: the
sim exports the weapon id only, and the UI maps it to text.
"""

glob:pub GUN_NAMES: list[str] = ["Pistol", "Rifle", "Shotgun", "SMG", "Sniper"],
     GUN_BLURBS: list[str] = [
         "Slow, accurate, 12 rounds.",
         "The all-rounder. 30 rounds, no spread.",
         "8 pellets per shot, brutal up close, short range.",
         "Fastest fire rate, 35 rounds, sprays.",
         "One shot one kill. 5 rounds, slow."
     ],
     # right-click scope style per gun id. "reddot" = small centre dot,
     # "sniper" = full circular scope overlay, "none" = no ADS optic (shotgun).
     # pistol + shotgun have no optic; rifle/smg red-dot, sniper full scope
     GUN_SCOPES: list[str] = ["none", "reddot", "none", "reddot", "sniper"];
