--[[
* Floos - Mining constants
]]--

require('common');

local M = {};

M.PACKET_HELM = 0x36;      -- trade to a gathering point (HELM)
M.PACKET_ACTION = 0x1A;    -- client action; ActionID 0x0E = fish, 0x11 = dig
M.GYSAHL_GREENS_ID = 4545;
M.PICKAXE_ID = 605;
M.IDLE_LIMIT_SEC = 600;
M.DEFAULT_FATIGUE_CAP = 200;

--- HorizonXI has no fishing fatigue. Instead each body of water holds a stock
--- of each fish, shared by every angler, and those stocks refill at these
--- Vana'diel hours. A falling catch rate means the water is fished out, not
--- that you are tired - so the fix is to move or wait for the next restock.
M.POOL_RESTOCK_HOURS = { 0, 4, 6, 7, 17, 18, 20 };

M.PACKET_ZONE_IN = 0x0A;   -- GP_SERV_LOGIN, carries the zone's weather
M.PACKET_WEATHER = 0x57;   -- GP_SERV_WEATHER, weather change

--- Chocobo digging ranks, lowest first. Rank is the index into this list.
--- The daily item cap is 100 + rank * 10, so Amateur 100 ... Expert 200.
M.DIG_RANKS = {
    [0]  = 'Amateur',    [1] = 'Recruit',    [2] = 'Initiate',   [3]  = 'Novice',
    [4]  = 'Apprentice', [5] = 'Journeyman', [6] = 'Craftsman',  [7]  = 'Artisan',
    [8]  = 'Adept',      [9] = 'Veteran',    [10] = 'Expert',
};

--- Elemental ore gates, straight off the HorizonXI wiki's Chocobo Digging
--- page. All four must hold at once:
---   1. digging rank at least Craftsman (6)
---   2. moon waxing crescent, roughly 7% - 24%
---   3. an active weather in the area (Fog counts)
---   4. the zone is not a Rise of the Zilart area
--- The ore's element follows the Vana'diel day: Firesday gives fire ore,
--- Earthsday earth ore, and so on.
M.ORE_MIN_RANK = 6;
M.ORE_MOON_MIN = 7;
M.ORE_MOON_MAX = 24;

--- Rise of the Zilart zones, per Horizon's own expansion list, mapped to
--- standard FFXI zone ids. Only five of these are diggable at all
--- (114, 121, 123, 124, 125) but the rest are listed so the check stays
--- honest if you dig somewhere unexpected.
M.ROZ_ZONES = {
    [113] = true,  -- Cape Teriggan
    [114] = true,  -- Eastern Altepa Desert     (diggable)
    [121] = true,  -- The Sanctuary of Zi'Tah   (diggable)
    [122] = true,  -- Ro'Maeve
    [123] = true,  -- Yuhtunga Jungle           (diggable)
    [124] = true,  -- Yhoator Jungle            (diggable)
    [125] = true,  -- Western Altepa Desert     (diggable)
    [128] = true,  -- Valley of Sorrows
    [130] = true,  -- Ru'Aun Gardens
    [134] = true,  -- Dynamis - Beaucedine
    [135] = true,  -- Dynamis - Xarcabard
    [153] = true,  -- The Boyahda Tree
    [154] = true,  -- Dragon's Aery
    [159] = true,  -- Temple of Uggalepih
    [160] = true,  -- Den of Rancor
    [163] = true,  -- Sacrificial Chamber
    [168] = true,  -- Chamber of Oracles
    [170] = true,  -- Full Moon Fountain
    [173] = true,  -- Korroloka Tunnel
    [174] = true,  -- Kuftal Tunnel
    [176] = true,  -- Sea Serpent Grotto
    [177] = true,  -- Ve'Lugannon Palace
    [178] = true,  -- The Shrine of Ru'Avitau
    [179] = true,  -- Stellar Fulcrum
    [180] = true,  -- La'Loff Amphitheater
    [181] = true,  -- The Celestial Nexus
    [185] = true,  -- Dynamis - San d'Oria
    [186] = true,  -- Dynamis - Bastok
    [187] = true,  -- Dynamis - Windurst
    [201] = true,  -- Cloister of Gales
    [202] = true,  -- Cloister of Storms
    [203] = true,  -- Cloister of Frost
    [205] = true,  -- Ifrit's Cauldron
    [207] = true,  -- Cloister of Flames
    [208] = true,  -- Quicksand Caves
    [209] = true,  -- Cloister of Tremors
    [211] = true,  -- Cloister of Tides
    [212] = true,  -- Gustav Tunnel
    [213] = true,  -- Labyrinth of Onzozo
    [247] = true,  -- Rabao
    [250] = true,  -- Kazham
    [251] = true,  -- Hall of the Gods
    [252] = true,  -- Norg
};

--- Zones where chocobo digging works on HorizonXI.
M.DIG_ZONES = {
    [2]   = true,  -- Carpenters' Landing
    [4]   = true,  -- Bibiki Bay
    [100] = true,  -- West Ronfaure
    [101] = true,  -- East Ronfaure
    [102] = true,  -- La Theine Plateau
    [103] = true,  -- Valkurm Dunes
    [104] = true,  -- Jugner Forest
    [105] = true,  -- Batallia Downs
    [106] = true,  -- North Gustaberg
    [107] = true,  -- South Gustaberg
    [108] = true,  -- Konschtat Highlands
    [109] = true,  -- Pashhow Marshlands
    [110] = true,  -- Rolanberry Fields
    [114] = true,  -- Eastern Altepa Desert  (ROZ - no ore)
    [115] = true,  -- West Sarutabaruta
    [116] = true,  -- East Sarutabaruta
    [117] = true,  -- Tahrongi Canyon
    [118] = true,  -- Buburimu Peninsula
    [119] = true,  -- Meriphataud Mountains
    [120] = true,  -- Sauromugue Champaign
    [121] = true,  -- The Sanctuary of Zi'Tah (ROZ - no ore)
    [123] = true,  -- Yuhtunga Jungle         (ROZ - no ore)
    [124] = true,  -- Yhoator Jungle          (ROZ - no ore)
    [125] = true,  -- Western Altepa Desert   (ROZ - no ore)
};

--- Clamming (Bibiki Bay - Purgonorgo Isle). Nothing like the other
--- activities: no skill, no rank, no daily cap. What you have instead is a
--- bucket with a weight limit, and everything in it is lost at once if you
--- go over. So the whole job of the tracker here is to answer one question -
--- is one more dig worth the risk?
---
--- Weights in ponzes, from HorizonXI's own Clamming page. Only five values
--- exist in the pool: 3, 6, 7, 11 and 20.
M.CLAM_WEIGHTS = {
    ['bibiki slug'] = 3,
    ['handful of fish scales'] = 3,
    ['handful of pugil scales'] = 3,
    ['bibiki urchin'] = 6,
    ['broken willow fishing rod'] = 6,
    ['coral fragment'] = 6,
    ['crab shell'] = 6,
    ['high-quality crab shell'] = 6,
    ['elm log'] = 6,
    ['suit of goblin armor'] = 6,
    ['suit of goblin mail'] = 6,
    ['goblin mask'] = 6,
    ['loaf of hobgoblin bread'] = 6,
    ['hobgoblin pie'] = 6,
    ['lacquer tree log'] = 6,
    ['maple log'] = 6,
    ['nebimonite'] = 6,
    ['piece of oxblood'] = 6,
    ['clump of pamtam kelp'] = 6,
    ['petrified log'] = 6,
    ['handful of high-quality pugil scales'] = 6,
    ['seashell'] = 6,
    ['shall shell'] = 6,
    ['titanictus shell'] = 6,
    ['turtle shell'] = 6,
    ['uragnite shell'] = 6,
    ['vongola clam'] = 6,
    ['pebble'] = 7,
    ['sack of white sand'] = 7,
    ['jacknife'] = 11,
    ['tropical clam'] = 20,
};

--- 6 pz is the modal weight by a wide margin, so an item we have never seen
--- is assumed to weigh that. The panel says when it had to assume.
M.CLAM_DEFAULT_WEIGHT = 6;

--- How often each item turns up, in percent. These are HorizonXI's own
--- sampled figures (n = 5,424) from the Purgonorgo Isle clamming page - not
--- guesses, and not retail numbers. They exist so the addon can work out the
--- real chance that the NEXT dig breaks your bucket, rather than just saying
--- "careful now".
M.CLAM_ABUNDANCE = {
    ['pebble'] = 22.3,
    ['jacknife'] = 11.6,
    ['bibiki slug'] = 11.1,
    ['clump of pamtam kelp'] = 6.2,
    ['shall shell'] = 5.6,
    ['vongola clam'] = 4.9,
    ['handful of fish scales'] = 3.7,
    ['handful of pugil scales'] = 3.5,
    ['hobgoblin pie'] = 2.7,
    ['nebimonite'] = 2.3,
    ['loaf of hobgoblin bread'] = 2.3,
    ['crab shell'] = 2.3,
    ['goblin mask'] = 2.2,
    ['suit of goblin mail'] = 2.1,
    ['sack of white sand'] = 2.0,
    ['suit of goblin armor'] = 1.9,
    ['tropical clam'] = 1.9,
    ['seashell'] = 1.8,
    ['broken willow fishing rod'] = 1.8,
    ['titanictus shell'] = 1.4,
    ['maple log'] = 1.3,
    ['handful of high-quality pugil scales'] = 1.1,
    ['bibiki urchin'] = 1.0,
    ['turtle shell'] = 0.9,
    ['coral fragment'] = 0.7,
    ['uragnite shell'] = 0.3,
    ['high-quality crab shell'] = 0.3,
    ['piece of oxblood'] = 0.3,
    ['lacquer tree log'] = 0.2,
    ['elm log'] = 0.2,
    ['petrified log'] = 0.2,
};

--- Bucket sizes. You are offered the next one up by Toh Zonikki when you
--- hand in a bucket holding at least (capacity - 5) pz, and you always start
--- again at 50 - the upgrade is per kit, not a character stat.
M.CLAM_CAPACITIES = { 50, 100, 150, 200 };
M.CLAM_START_CAPACITY = 50;
M.CLAM_UPGRADE_MARGIN = 5;

--- On a 200 pz bucket something jumps in and breaks it. Reported at 10% per
--- dig, halved by the HQ swimwear body piece. It does not apply to smaller
--- buckets.
M.CLAM_INCIDENT_PCT = 10;
M.CLAM_INCIDENT_PCT_HQ = 5;
M.CLAM_INCIDENT_CAPACITY = 200;

--- A kit is 500 gil from Toh Zonikki (the first one is free).
M.CLAM_KIT_COST = 500;

--- Clamming points come back about every 10 seconds.
M.CLAM_POINT_RESPAWN = 10;

return M;
