-- forge_items pour Luanti / Mineclonia
--   /add_items <nom> [| <effets|no> [| <infini yes|no>]]
--   /items_menu | /items_get <id> | /items_list | /items_delete <id> | /items_effects
-- Tout est protégé par le privilège "add_items".

local MOD = core.get_current_modname()
local storage = core.get_mod_storage()

local PRIV = "add_items"
local K_EFFECTS = MOD .. ":effects"
local K_INFINITE = MOD .. ":infinite"
local EFFECT_SECONDS = 4 -- durée de l'effet, rafraîchie chaque seconde tant que l'item est porté/tenu

core.register_privilege(PRIV, {
	description = "Peut forger des items (/add_items) et utiliser le catalogue (/items_menu)",
	give_to_singleplayer = true,
})

---------------------------------------------------------------------
-- Utilitaires
---------------------------------------------------------------------
local function setting(key, default)
	local v = core.settings:get(MOD .. "." .. key)
	if v == nil or v == "" then return default end
	return v
end

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- <préfixe><nom du joueur><suffixe>, ex : ¥£Excalibur™
local function decorate(name)
	return setting("name_prefix", "¥£") .. tostring(name) .. setting("name_suffix", "™")
end

-- Applique le nom en gardant les enchantements / infobulles de Mineclonia
local function set_display_name(stack, shown)
	local meta = stack:get_meta()
	meta:set_string("name", shown) -- champ utilisé par l'enclume Mineclonia
	meta:set_string("description", shown)
	local t = rawget(_G, "tt")
	if t and t.reload_itemstack_description then
		pcall(t.reload_itemstack_description, stack)
		if not meta:get_string("description"):find(shown, 1, true) then
			meta:set_string("description", shown)
		end
	end
end

local ACCENTS = {
	["à"]="a",["â"]="a",["ä"]="a",["é"]="e",["è"]="e",["ê"]="e",["ë"]="e",
	["î"]="i",["ï"]="i",["ô"]="o",["ö"]="o",["ù"]="u",["û"]="u",["ü"]="u",["ç"]="c",
}

local function slug(s)
	s = tostring(s):lower()
	for k, v in pairs(ACCENTS) do s = s:gsub(k, v) end
	s = s:gsub("[^a-z0-9_]+", "_"):gsub("^_+", ""):gsub("_+$", "")
	if s == "" then s = "item" end
	return s
end

local function give(name, stack)
	local inv = core.get_inventory({type = "player", name = name})
	if not inv then return end
	local left = inv:add_item("main", stack)
	if not left:is_empty() then
		local player = core.get_player_by_name(name)
		if player then core.add_item(player:get_pos(), left) end
	end
end

---------------------------------------------------------------------
-- Stockage (par monde)
---------------------------------------------------------------------
local items = {}

do
	local s = storage:get_string("items")
	if s ~= "" then items = core.parse_json(s) or {} end
end

local function save_items() storage:set_string("items", core.write_json(items)) end

local CATS = {} -- liste ordonnée des catégories créées
do
	local s = storage:get_string("categories")
	if s ~= "" then CATS = core.parse_json(s) or {} end
end

local function save_cats() storage:set_string("categories", core.write_json(CATS)) end

local function sanitize_category(name)
	name = tostring(name or ""):gsub("%c", ""):gsub("[,;%[%]]", "")
	name = trim(name)
	if #name > 24 then name = name:sub(1, 24) end
	return name
end

local function add_category(name)
	name = sanitize_category(name)
	if name == "" then return nil, "Nom de catégorie vide." end
	for _, c in ipairs(CATS) do
		if c:lower() == name:lower() then return name end -- déjà existante
	end
	CATS[#CATS + 1] = name
	table.sort(CATS)
	save_cats()
	return name
end

local function item_category(id)
	local c = items[id] and items[id].category
	return (type(c) == "string" and c ~= "") and c or nil
end

local function sorted_ids()
	local ids = {}
	for id in pairs(items) do ids[#ids + 1] = id end
	table.sort(ids)
	return ids
end

local function add_item(def, creator)
	local base = slug(def.name)
	local id, n = base, 2
	while items[id] do id = base .. "_" .. n; n = n + 1 end
	def.id = id
	def.creator = creator
	items[id] = def
	save_items()
	return id
end

---------------------------------------------------------------------
-- Effets de potion (Mineclonia) : armure portée / item tenu
---------------------------------------------------------------------
local function potions()
	local P = rawget(_G, "mcl_potions")
	if P and P.registered_effects then return P end
end

-- "no" / vide -> nil (aucun effet) ; sinon liste {{id=, level=}, ...} ; erreur -> nil, message
local function parse_effects(text)
	text = trim(text or "")
	local low = text:lower()
	if text == "" or low == "no" or low == "non" or low == "none" then return nil end

	local P = potions()
	if not P then return nil, "La liste des effets Mineclonia (mcl_potions) est indisponible." end

	local list = {}
	for entry in text:gmatch("[^,;]+") do
		entry = trim(entry)
		local id, lvl = entry:match("^([%w_]+)[%s:=]+(%d+)$")
		if not id then
			id = entry:match("^([%w_]+)$")
			lvl = 1
		end
		if not id then
			return nil, "Effet mal écrit : '" .. entry .. "' (format : id:niveau)"
		end
		id = id:lower()
		if not P.registered_effects[id] then
			return nil, "Effet inconnu : " .. id .. " (voir /items_effects)"
		end
		lvl = math.floor(tonumber(lvl))
		if lvl < 1 or lvl > 255 then
			return nil, "Niveau invalide pour " .. id .. " (1 à 255)"
		end
		list[#list + 1] = {id = id, level = lvl}
	end
	if #list == 0 then return nil end
	return list
end

local function parse_bool(text)
	text = trim(text or ""):lower()
	if text == "" or text == "no" or text == "non" or text == "n" or text == "false" or text == "0" then
		return false
	end
	if text == "yes" or text == "oui" or text == "y" or text == "o" or text == "true" or text == "1" then
		return true
	end
	return nil, "Valeur invalide '" .. text .. "' : écris yes ou no."
end

---------------------------------------------------------------------
-- Construction de l'item depuis sa définition
---------------------------------------------------------------------
local function build_stack(def)
	local stack = ItemStack(def.itemstring)
	if stack:is_empty() then error("item enregistré invalide : " .. tostring(def.itemstring)) end
	stack:set_count(1)
	local meta = stack:get_meta()

	local has_effects = type(def.effects) == "table" and #def.effects > 0
	meta:set_string(K_EFFECTS, has_effects and core.write_json(def.effects) or "")
	meta:set_string(K_INFINITE, def.infinite and "1" or "")

	-- Durabilité infinie : capacités d'outil sans usure (en plus du remise à zéro de l'usure)
	if def.infinite then
		local caps = stack:get_tool_capabilities()
		if caps then
			local tc = table.copy(caps)
			for _, cap in pairs(tc.groupcaps or {}) do cap.uses = 0 end
			tc.punch_attack_uses = 0
			meta:set_tool_capabilities(tc)
		end
	end

	set_display_name(stack, decorate(def.name))

	-- Lignes d'info ajoutées à l'infobulle
	local extra = {}
	if has_effects then
		local parts = {}
		for _, e in ipairs(def.effects) do parts[#parts + 1] = e.id .. " " .. e.level end
		extra[#extra + 1] = "Effets : " .. table.concat(parts, ", ")
	end
	if def.infinite then extra[#extra + 1] = "Infini" end
	if #extra > 0 then
		meta:set_string("description",
			meta:get_string("description") .. "\n" .. core.colorize("#AAAAAA", table.concat(extra, "\n")))
	end
	return stack
end

---------------------------------------------------------------------
-- Boucle : effets, durabilité infinie, items stackables infinis
---------------------------------------------------------------------
local ARMOR_GROUPS = {"armor", "armor_head", "armor_torso", "armor_legs", "armor_feet"}

local function is_armor(itemname)
	for _, g in ipairs(ARMOR_GROUPS) do
		if core.get_item_group(itemname, g) > 0 then return true end
	end
	return false
end

local function is_infinite(stack)
	return not stack:is_empty() and stack:get_meta():get_string(K_INFINITE) == "1"
end

local function effects_of(stack)
	if stack:is_empty() then return nil end
	local s = stack:get_meta():get_string(K_EFFECTS)
	if s == "" then return nil end
	return core.parse_json(s)
end

local warned = false
local function give_effect(player, id, level)
	local P = rawget(_G, "mcl_potions")
	if not P then return end
	local fn = P.give_effect_by_level or P.give_effect
	if not fn then return end
	local ok, err = pcall(fn, id, player, level, EFFECT_SECONDS, true)
	if not ok and not warned then
		warned = true
		core.log("warning", "[" .. MOD .. "] effet '" .. id .. "' non appliqué : " .. tostring(err))
	end
end

local function tick_effects(player)
	local active = {}
	local function collect(stack)
		local list = effects_of(stack)
		if type(list) ~= "table" then return end
		for _, e in ipairs(list) do
			if not active[e.id] or active[e.id] < e.level then active[e.id] = e.level end
		end
	end

	-- Armures : seulement si elles sont PORTÉES (liste "armor" de Mineclonia)
	local inv = player:get_inventory()
	local armor = inv and inv:get_list("armor")
	if armor then
		for i, st in ipairs(armor) do
			collect(st)
			if is_infinite(st) and st:get_wear() > 0 then
				st:set_wear(0)
				inv:set_stack("armor", i, st)
			end
		end
	end

	-- Autres items : seulement s'ils sont TENUS en main
	local held = player:get_wielded_item()
	if not held:is_empty() and not is_armor(held:get_name()) then collect(held) end

	for id, level in pairs(active) do give_effect(player, id, level) end
end

local last = {} -- joueur -> {idx, stack}

local function tick_infinite(player)
	local pname = player:get_player_name()
	local idx = player:get_wield_index()
	local w = player:get_wielded_item()
	local rec = last[pname]

	-- Item infini consommé (posé, mangé, lancé...) : on le remet
	if rec and rec.idx == idx then
		local p = rec.stack
		if w:is_empty() or (w:get_name() == p:get_name() and w:get_count() < p:get_count()) then
			player:set_wielded_item(p)
			w = ItemStack(p)
		end
	end

	if is_infinite(w) then
		if w:get_wear() > 0 then
			w:set_wear(0)
			player:set_wielded_item(w)
		end
		last[pname] = {idx = idx, stack = ItemStack(w)}
	else
		last[pname] = nil
	end
end

-- Toute action d'inventaire (déplacer, ranger, jeter) : on oublie le suivi, pas de duplication
core.register_on_player_inventory_action(function(player)
	last[player:get_player_name()] = nil
end)

core.register_on_leaveplayer(function(player)
	last[player:get_player_name()] = nil
end)

local t_fast, t_effects = 0, 0
core.register_globalstep(function(dt)
	t_fast = t_fast + dt
	t_effects = t_effects + dt
	if t_fast < 0.1 then return end
	t_fast = 0
	local do_effects = t_effects >= 1
	if do_effects then t_effects = 0 end
	for _, player in ipairs(core.get_connected_players()) do
		if player:get_hp() > 0 then
			tick_infinite(player)
			if do_effects then tick_effects(player) end
		end
	end
end)

-- Les items infinis ne peuvent pas être jetés (sinon duplication)
core.register_on_mods_loaded(function()
	local names = {}
	for iname in pairs(core.registered_items) do
		if iname ~= "" then names[#names + 1] = iname end
	end
	for _, iname in ipairs(names) do
		local def = core.registered_items[iname]
		local orig = def.on_drop or core.item_drop
		pcall(core.override_item, iname, {
			on_drop = function(stack, dropper, pos)
				if is_infinite(stack) then
					if dropper and dropper.is_player and dropper:is_player() then
						core.chat_send_player(dropper:get_player_name(),
							"Les items infinis ne peuvent pas être jetés.")
					end
					return stack
				end
				return orig(stack, dropper, pos)
			end,
		})
	end
end)

---------------------------------------------------------------------
-- Menu : catalogue de tous les items forgés
---------------------------------------------------------------------
---------------------------------------------------------------------
-- Interface : styles et textures communs (fichiers dans textures/)
---------------------------------------------------------------------
local function f2(n) return string.format("%.2f", n) end
local function esc(t) return core.formspec_escape(tostring(t)) end

local function ui_header(w, h)
	return table.concat({
		"formspec_version[4]",
		"size[", w, ",", h, "]",
		"no_prepend[]",
		"bgcolor[#00000000;false]",
		"background9[0,0;", w, ",", h, ";forge_items_panel.png;false;10]",
		"listcolors[#00000000;#ffffff28;#00000000;#1b1030;#ffffff]",
		"style_type[label;textcolor=#f3e3b0]",
		"style_type[button;textcolor=#2b1a00;border=false;bgimg=forge_items_btn.png;",
		"bgimg_hovered=forge_items_btn_hover.png;bgimg_pressed=forge_items_btn_pressed.png;bgimg_middle=6]",
		"style_type[field;textcolor=#ffffff]",
	})
end

-- Style d'un ou plusieurs boutons nommés : kind = "add" (vert) ou "cancel" (rouge)
local function ui_style(kind, names)
	return "style[" .. names .. ";textcolor=#ffffff;border=false;bgimg=forge_items_btn_" .. kind
		.. ".png;bgimg_hovered=forge_items_btn_" .. kind .. "_hover.png;bgimg_pressed=forge_items_btn_"
		.. kind .. "_pressed.png;bgimg_middle=6]"
end

local function ui_title(w, text)
	return table.concat({
		"image[0.45,0.2;0.7,0.7;forge_items_sparkle.png]",
		"image[", f2(w - 1.15), ",0.2;0.7,0.7;forge_items_sparkle.png]",
		"label[1.35,0.55;", esc(text), "]",
	})
end

-- Fonds de cases (dessinés sous les listes)
local function ui_slots(x, y, cols, rows)
	local t = {}
	for r = 0, rows - 1 do
		for c = 0, cols - 1 do
			t[#t + 1] = "image[" .. f2(x + c * 1.25) .. "," .. f2(y + r * 1.25) .. ";1,1;forge_items_slot.png]"
		end
	end
	return table.concat(t)
end

local PAGE_SIZE = 40 -- 8 colonnes x 5 lignes
local FORMNAME = MOD .. ":menu"
local viewers = {}
local snapshot = {} -- joueur -> liste des ids affichés (pour la poubelle)
local open_catmanage -- déclaré ici, défini plus bas (page de gestion des catégories)
local catmanage_view = {} -- joueur -> {page, ids, rows}

local function menu_inv_name(name) return MOD .. "_menu_" .. name end

local function filtered_ids(filter)
	local ids = sorted_ids()
	if filter == nil then return ids end
	local out = {}
	for _, id in ipairs(ids) do
		local cat = item_category(id)
		if filter == "__none__" then
			if not cat then out[#out + 1] = id end
		elseif cat == filter then
			out[#out + 1] = id
		end
	end
	return out
end

local function open_menu(name, page, filter)
	local view = viewers[name]
	if filter == nil and view and view.filter ~= nil and page == nil then filter = view.filter end
	local ids = filtered_ids(filter)
	local pages = math.max(1, math.ceil(#ids / PAGE_SIZE))
	page = math.min(math.max(tonumber(page) or (view and view.page) or 1, 1), pages)
	viewers[name] = {page = page, filter = filter}
	snapshot[name] = ids

	local invname = menu_inv_name(name)
	local inv = core.create_detached_inventory(invname, {
		-- Poubelle : on peut y glisser un objet de son inventaire (détruit la copie)
		allow_put = function(_, listname, _, stack, player)
			if listname == "trash" and player and core.check_player_privs(player, {[PRIV] = true}) then
				return stack:get_count()
			end
			return 0
		end,
		on_put = function(inv2, listname)
			if listname == "trash" then inv2:set_stack("trash", 1, ItemStack("")) end
		end,
		-- Glisser un item DU CATALOGUE vers la poubelle = le supprimer définitivement
		allow_move = function(_, from_list, _, to_list, _, count, player)
			if from_list == "main" and to_list == "trash" and player
					and core.check_player_privs(player, {[PRIV] = true}) then
				return count
			end
			return 0
		end,
		on_move = function(inv2, from_list, from_index, to_list)
			if from_list == "main" and to_list == "trash" then
				inv2:set_stack("trash", 1, ItemStack(""))
				local first = (((viewers[name] or {}).page or 1) - 1) * PAGE_SIZE
				local id = (snapshot[name] or {})[first + from_index]
				if id and items[id] then
					items[id] = nil
					save_items()
					core.chat_send_player(name, "Item supprimé du catalogue : " .. id)
				end
				core.after(0, function()
					local v = viewers[name]
					if core.get_player_by_name(name) and v then open_menu(name, v.page, v.filter) end
				end)
			end
		end,
		allow_take = function(_, _, _, stack, player)
			if not player or not core.check_player_privs(player, {[PRIV] = true}) then return 0 end
			return stack:get_count()
		end,
		on_take = function(inv2, listname, index, stack)
			inv2:set_stack(listname, index, stack) -- le catalogue reste complet
		end,
	}, name)
	inv:set_size("main", PAGE_SIZE)
	inv:set_size("trash", 1)

	local first = (page - 1) * PAGE_SIZE
	for i = 1, PAGE_SIZE do
		local id = ids[first + i]
		if id then
			local ok, stack = pcall(build_stack, items[id])
			if ok then inv:set_stack("main", i, stack) end
		end
	end

	local W, H = 12.2, 16.1
	local label = filter == nil and "Toutes" or filter == "__none__" and "Sans catégorie" or filter
	local fs = {
		ui_header(W, H),
		ui_title(W, "Items forgés - " .. label .. " - page " .. page .. "/" .. pages .. " (" .. #ids .. ")"),
		"button[", f2(W - 3.0), ",0.15;2.8,0.6;catmanage;Gérer catégories]",
	}
	-- Onglets : Toutes / Sans catégorie / chaque catégorie créée
	local tx = 0.5
	local function tab(fname, text, active)
		fs[#fs + 1] = (active and ui_style("add", fname) or "") ..
			"button[" .. f2(tx) .. ",0.95;2.1,0.6;" .. fname .. ";" .. esc(text) .. "]"
		tx = tx + 2.2
	end
	tab("tab_all", "Toutes", filter == nil)
	tab("tab_none", "Sans catégorie", filter == "__none__")
	for i, c in ipairs(CATS) do
		tab("tab_cat_" .. i, c, filter == c)
	end
	fs[#fs + 1] = "background9[0.35,1.75;10.05,6.4;forge_items_card.png;false;6]"
	core.show_formspec(name, FORMNAME, table.concat(fs) .. table.concat({
		ui_slots(0.5, 1.9, 8, 5),
		"list[detached:", invname, ";main;0.5,1.9;8,5;]",
		"button[0.5,8.45;2.8,0.8;prev;< Précédent]",
		"button[3.6,8.45;2.8,0.8;next;Suivant >]",
		"background9[10.6,1.75;1.3,2.7;forge_items_card.png;false;6]",
		"label[10.75,2.05;Poubelle]",
		ui_slots(10.75, 2.45, 1, 1),
		"image[10.75,2.45;1,1;forge_items_trash.png]",
		"list[detached:", invname, ";trash;10.75,2.45;1,1;]",
		ui_slots(0.6, 9.65, 9, 4),
		"list[current_player;main;0.6,9.65;9,4;]",
		"listring[detached:", invname, ";main]",
		"listring[current_player;main]",
		"label[0.6,15.05;", esc("Maj+clic sur un item = le mettre dans ton inventaire (ou glisse-le)."), "]",
		"label[0.6,15.5;", esc("Glisse un item du catalogue dans la poubelle = suppression définitive."), "]",
	}))
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= FORMNAME then return end
	local name = player:get_player_name()
	if not core.check_player_privs(name, {[PRIV] = true}) then return end
	local view = viewers[name] or {page = 1, filter = nil}

	if fields.prev then
		open_menu(name, view.page - 1, view.filter)
	elseif fields.next then
		open_menu(name, view.page + 1, view.filter)
	elseif fields.catmanage then
		open_catmanage(name, 1)
	elseif fields.tab_all then
		open_menu(name, 1, nil)
	elseif fields.tab_none then
		open_menu(name, 1, "__none__")
	else
		for i, c in ipairs(CATS) do
			if fields["tab_cat_" .. i] then
				open_menu(name, 1, c)
				return
			end
		end
	end
end)

core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	viewers[name] = nil
	catmanage_view[name] = nil
	if core.remove_detached_inventory then
		core.remove_detached_inventory(menu_inv_name(name))
	end
end)

---------------------------------------------------------------------
-- Gérer catégories : créer des catégories et y déplacer les items
---------------------------------------------------------------------
local FORM_CATMANAGE = MOD .. ":catmanage"
local CATMANAGE_PAGE_SIZE = 10

function open_catmanage(name, page)
	local ids = sorted_ids()
	local pages = math.max(1, math.ceil(#ids / CATMANAGE_PAGE_SIZE))
	page = math.min(math.max(tonumber(page) or 1, 1), pages)
	catmanage_view[name] = {page = page, ids = ids}

	-- Liste des choix pour chaque menu déroulant : Sans catégorie + chaque catégorie
	local choices = {"Sans catégorie"}
	for _, c in ipairs(CATS) do choices[#choices + 1] = c end
	local choices_str = table.concat(choices, ",")

	local W, H = 12.4, 13.0
	local fs = {
		ui_header(W, H),
		ui_title(W, "Gérer les catégories"),
		"background9[0.4,1.1;11.6,7.0;forge_items_card.png;false;6]",
		"label[0.7,1.55;", esc("Item"), "]",
		"label[6.0,1.55;", esc("Catégorie"), "]",
	}

	local first = (page - 1) * CATMANAGE_PAGE_SIZE
	local row_names = {}
	for i = 1, CATMANAGE_PAGE_SIZE do
		local id = ids[first + i]
		if id then
			local y = 1.95 + (i - 1) * 0.55
			local cur = item_category(id)
			local sel = 1
			for ci, c in ipairs(choices) do if c == (cur or "Sans catégorie") then sel = ci end end
			fs[#fs + 1] = "label[0.7," .. f2(y + 0.1) .. ";" .. esc(id) .. "]"
			local fname = "cat_" .. i
			row_names[i] = {fname = fname, id = id}
			fs[#fs + 1] = "dropdown[6.0," .. f2(y) .. ";4.8;" .. fname .. ";" .. esc(choices_str) .. ";" .. sel .. "]"
		end
	end
	catmanage_view[name].rows = row_names

	fs[#fs + 1] = "button[0.7,8.3;2.2,0.7;prev;< Précédent]"
	fs[#fs + 1] = "label[3.1,8.55;" .. esc("Page " .. page .. "/" .. pages) .. "]"
	fs[#fs + 1] = "button[4.4,8.3;2.2,0.7;next;Suivant >]"
	fs[#fs + 1] = "button[7.0,8.3;3.2,0.7;apply;Appliquer les catégories]"
	fs[#fs + 1] = ui_style("add", "apply")

	fs[#fs + 1] = "background9[0.4,9.3;11.6,2.3;forge_items_card.png;false;6]"
	fs[#fs + 1] = "label[0.7,9.75;" .. esc("Créer une nouvelle catégorie :") .. "]"
	fs[#fs + 1] = "field[0.7,10.3;6.0,0.8;newcat;;]"
	fs[#fs + 1] = "field_close_on_enter[newcat;false]"
	fs[#fs + 1] = "button[6.9,10.3;3.0,0.8;createcat;Créer]"
	fs[#fs + 1] = ui_style("add", "createcat")
	fs[#fs + 1] = "button[0.7,11.3;3.2,0.8;close;Fermer]"
	fs[#fs + 1] = ui_style("cancel", "close")

	core.show_formspec(name, FORM_CATMANAGE, table.concat(fs))
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= FORM_CATMANAGE then return end
	local name = player:get_player_name()
	if not core.check_player_privs(name, {[PRIV] = true}) then return end
	local view = catmanage_view[name]
	if not view then return end

	if fields.close then return end
	if fields.prev then return open_catmanage(name, view.page - 1) end
	if fields.next then return open_catmanage(name, view.page + 1) end

	if fields.createcat then
		local created, err = add_category(fields.newcat)
		if created then
			core.chat_send_player(name, "Catégorie créée : " .. created)
		else
			core.chat_send_player(name, err or "Impossible de créer cette catégorie.")
		end
		return open_catmanage(name, view.page)
	end

	if fields.apply then
		local choices = {"Sans catégorie"}
		for _, c in ipairs(CATS) do choices[#choices + 1] = c end
		local moved = 0
		for _, row in ipairs(view.rows or {}) do
			local idx = tonumber(fields[row.fname])
			if idx and choices[idx] and items[row.id] then
				local chosen = choices[idx]
				local new_cat = (chosen == "Sans catégorie") and nil or chosen
				if item_category(row.id) ~= new_cat then
					items[row.id].category = new_cat
					moved = moved + 1
				end
			end
		end
		if moved > 0 then
			save_items()
			core.chat_send_player(name, moved .. " item(s) déplacé(s).")
		end
		return open_catmanage(name, view.page)
	end
end)

core.register_chatcommand("items_categories", {
	description = "Ouvre la gestion des catégories (créer, déplacer les items)",
	privs = {[PRIV] = true},
	func = function(name)
		open_catmanage(name, 1)
		return true
	end,
})

---------------------------------------------------------------------
-- Commandes
---------------------------------------------------------------------
core.register_chatcommand("add_items", {
	params = "<nom> [effets|no] [yes|no]",
	description = "Forge l'item tenu en main : nom décoré, enchantements conservés, "
		.. "effets de potion optionnels (id:niveau, ...), mode infini optionnel",
	privs = {[PRIV] = true},
	func = function(name, param)
		local usage = "Usage : /add_items <nom> [effets|no] [yes|no]  "
			.. "(ex : /add_items Excalibur haste:2,night_vision:1 yes)"

		local args = {}
		for tok in param:gmatch("%S+") do args[#args + 1] = tok end
		if #args == 0 then return false, usage end
		if #args > 3 then
			return false, "Trop d'arguments : le nom doit être UN seul mot (mets _ à la place des espaces) "
				.. "et les effets s'écrivent sans espace (id:niveau,id:niveau).\n" .. usage
		end

		-- Nom : un mot, les _ deviennent des espaces à l'affichage
		local label = args[1]:gsub("%c", ""):gsub("_", " ") -- pas de codes couleur injectés
		label = trim(label)
		if label == "" then return false, usage end
		if #label > 60 then return false, "Nom trop long (60 octets max)." end

		-- /add_items <nom> yes  => infini sans effets
		local eff_text, inf_text = args[2], args[3]
		if #args == 2 then
			local l = args[2]:lower()
			if l == "yes" or l == "oui" or l == "y" or l == "o" or l == "true" or l == "1" then
				eff_text, inf_text = nil, args[2]
			end
		end

		local effects, err = parse_effects(eff_text)
		if err then return false, err end
		local infinite, err2 = parse_bool(inf_text)
		if err2 then return false, err2 end

		local player = core.get_player_by_name(name)
		if not player then return false, "Joueur introuvable." end
		local held = player:get_wielded_item()
		if held:is_empty() then return false, "Tiens l'item à forger dans ta main." end

		-- Copie de l'item tenu (enchantements conservés), neuve et sans usure
		local proto = ItemStack(held)
		proto:set_count(1)
		proto:set_wear(0)

		local def = {name = label, itemstring = proto:to_string(),
			effects = effects, infinite = infinite and true or false}
		local ok, stack = pcall(build_stack, def)
		if not ok then return false, "Erreur : " .. tostring(stack) end

		local id = add_item(def, name)

		if held:get_count() > 1 then
			held:take_item(1)
			player:set_wielded_item(held)
			give(name, stack)
		else
			player:set_wielded_item(stack)
		end

		local info = {}
		if rawget(_G, "mcl_enchanting") and mcl_enchanting.get_enchantments then
			local ok2, ench = pcall(mcl_enchanting.get_enchantments, proto)
			if ok2 and type(ench) == "table" and next(ench) then
				local e = {}
				for k, v in pairs(ench) do e[#e + 1] = k .. " " .. v end
				table.sort(e)
				info[#info + 1] = "enchantements : " .. table.concat(e, ", ")
			end
		end
		if effects then
			local e = {}
			for _, x in ipairs(effects) do e[#e + 1] = x.id .. " " .. x.level end
			info[#info + 1] = "effets : " .. table.concat(e, ", ")
				.. (is_armor(proto:get_name()) and " (quand portée)" or " (quand tenu en main)")
		end
		if infinite then info[#info + 1] = "infini" end

		return true, "Item forgé : " .. decorate(label) .. " (id : " .. id .. ")"
			.. (#info > 0 and (" - " .. table.concat(info, " ; ")) or "")
	end,
})

core.register_chatcommand("items_menu", {
	description = "Ouvre le catalogue des items forgés",
	privs = {[PRIV] = true},
	func = function(name)
		open_menu(name, 1)
		return true
	end,
})

core.register_chatcommand("items_get", {
	params = "<id>",
	description = "Récupère un item forgé",
	privs = {[PRIV] = true},
	func = function(name, param)
		local def = items[trim(param)]
		if not def then return false, "Item introuvable : " .. param end
		local ok, stack = pcall(build_stack, def)
		if not ok then return false, "Erreur : " .. tostring(stack) end
		give(name, stack)
		return true, "Item " .. def.id .. " donné."
	end,
})

core.register_chatcommand("items_list", {
	description = "Liste les items forgés",
	privs = {[PRIV] = true},
	func = function()
		local ids = sorted_ids()
		if #ids == 0 then return true, "Aucun item forgé." end
		return true, "Items (" .. #ids .. ") : " .. table.concat(ids, ", ")
	end,
})

core.register_chatcommand("items_delete", {
	params = "<id>",
	description = "Supprime un item forgé du catalogue",
	privs = {[PRIV] = true},
	func = function(_, param)
		param = trim(param)
		if not items[param] then return false, "Item introuvable : " .. param end
		items[param] = nil
		save_items()
		return true, "Item supprimé : " .. param
	end,
})

core.register_chatcommand("items_effects", {
	description = "Liste les effets Mineclonia utilisables dans /add_items",
	privs = {[PRIV] = true},
	func = function()
		local P = potions()
		if not P then return false, "Liste des effets indisponible (mcl_potions)." end
		local ids = {}
		for id in pairs(P.registered_effects) do ids[#ids + 1] = id end
		table.sort(ids)
		return true, "Effets (" .. #ids .. ") : " .. table.concat(ids, ", ")
	end,
})

core.register_chatcommand("list", {
	params = "enchant | effect",
	description = "Liste les enchantements ou les effets Mineclonia disponibles",
	privs = {[PRIV] = true},
	func = function(_, param)
		local what = trim(param):lower()

		if what == "enchant" or what == "enchants" or what == "enchantment" or what == "enchantments" then
			local E = rawget(_G, "mcl_enchanting")
			if not (E and E.enchantments) then
				return false, "Liste des enchantements indisponible (mcl_enchanting)."
			end
			local out = {}
			for id, def in pairs(E.enchantments) do
				local max = type(def) == "table" and def.max_level
				out[#out + 1] = max and (id .. " (max " .. max .. ")") or id
			end
			table.sort(out)
			return true, "Enchantements (" .. #out .. ") : " .. table.concat(out, ", ")

		elseif what == "effect" or what == "effects" then
			local P = potions()
			if not P then return false, "Liste des effets indisponible (mcl_potions)." end
			local ids = {}
			for id in pairs(P.registered_effects) do ids[#ids + 1] = id end
			table.sort(ids)
			return true, "Effets (" .. #ids .. ") : " .. table.concat(ids, ", ")
		end

		return false, "Usage : /list enchant   ou   /list effect"
	end,
})


---------------------------------------------------------------------
-- /enchant_items : met un item, choisis un enchantement, choisis son niveau
---------------------------------------------------------------------
local SLOT = "forge_items_slot" -- liste ajoutée à l'inventaire du joueur (sauvegardée avec lui)
local FORM_ENCH = MOD .. ":enchant"
local FORM_LEVEL = MOD .. ":enchant_level"
local ENCH_PER_PAGE = 6
local MAX_TECH_LEVEL = 32767 -- garde-fou technique (chiffres romains de Mineclonia)
local ench_view = {}         -- joueur -> {page, mode = "main"|"level", pending}

local function enchant_api()
	local E = rawget(_G, "mcl_enchanting")
	if E and E.enchantments and E.enchant then return E end
end

local function return_slot_item(player)
	local inv = player:get_inventory()
	if not inv or inv:get_size(SLOT) == 0 then return end
	local st = inv:get_stack(SLOT, 1)
	if st:is_empty() then return end
	inv:set_stack(SLOT, 1, ItemStack(""))
	local left = inv:add_item("main", st)
	if not left:is_empty() then core.add_item(player:get_pos(), left) end
end

local function supports(itemname, id, def)
	local E = enchant_api()
	if E.item_supports_enchantment then
		local ok, res = pcall(E.item_supports_enchantment, itemname, id)
		if ok and res then return true end
	end
	local pr = type(def.primary) == "table" and def.primary or {}
	local sec = type(def.secondary) == "table" and def.secondary or {}
	for _, groups in ipairs({pr, sec}) do
		for g in pairs(groups) do
			if core.get_item_group(itemname, g) > 0 then return true end
		end
	end
	return false
end

local function ench_display_name(id, def)
	if type(def) == "table" and type(def.name) == "string" and def.name ~= "" then
		return def.name
	end
	local n = id:gsub("_", " ")
	return (n:gsub("^%l", string.upper))
end

local function possible_enchants(stack)
	local E = enchant_api()
	local out = {}
	if not E or stack:is_empty() then return out end
	local iname = stack:get_name()
	for id, def in pairs(E.enchantments) do
		if type(def) == "table" and supports(iname, id, def) then
			out[#out + 1] = {id = id, name = ench_display_name(id, def), max = tonumber(def.max_level) or 1}
		end
	end
	table.sort(out, function(a, b) return a.id < b.id end)
	return out
end

local function current_levels(stack)
	local E = enchant_api()
	if stack:is_empty() or not E or not E.get_enchantments then return {} end
	local ok, t = pcall(E.get_enchantments, stack)
	return (ok and type(t) == "table") and t or {}
end

local show_level_form

local function show_enchant_main(name)
	local player = core.get_player_by_name(name)
	local E = enchant_api()
	if not player or not E then return end
	local inv = player:get_inventory()
	inv:set_size(SLOT, 1)
	local stack = inv:get_stack(SLOT, 1)

	local view = ench_view[name] or {page = 1}
	ench_view[name] = view
	view.mode = "main"

	local list = possible_enchants(stack)
	local pages = math.max(1, math.ceil(#list / ENCH_PER_PAGE))
	view.page = math.min(math.max(view.page or 1, 1), pages)
	local cur = current_levels(stack)

	local W, H = 13.9, 14.3
	local fs = {}
	local function add(...)
		for _, v in ipairs({...}) do fs[#fs + 1] = tostring(v) end
	end

	add(ui_header(W, H))
	add(ui_title(W, "Forge d'enchantements"))
	add("button_exit[", f2(W - 2.65), ",0.25;2.2,0.7;close;Fermer]")

	-- Carte de l'item
	add("background9[0.4,1.1;3.6,6.0;forge_items_card.png;false;6]")
	add("label[0.75,1.55;Item à enchanter]")
	add("image[1.85,2.0;1,1;forge_items_slot.png]")
	add("list[current_player;", SLOT, ";1.85,2.0;1,1;]")
	if stack:is_empty() then
		add("label[0.75,3.7;", esc("Place un item dans\nla case ci-dessus."), "]")
	else
		local d = stack:get_description():match("^[^\n]*") or stack:get_name()
		add("label[0.75,3.5;", esc(d), "]")
		local lines = {}
		for id, lvl in pairs(cur) do
			local def = E.enchantments[id]
			lines[#lines + 1] = "- " .. ench_display_name(id, def) .. " " .. tostring(lvl)
		end
		table.sort(lines)
		if #lines == 0 then lines[1] = "Aucun enchantement" end
		while #lines > 7 do table.remove(lines) end
		add("label[0.75,4.2;", esc("Actuels :\n" .. table.concat(lines, "\n")), "]")
	end

	-- Grille des enchantements possibles (2 colonnes)
	if stack:is_empty() then
		add("label[4.6,3.8;", esc("Place un item pour voir les enchantements possibles."), "]")
	elseif #list == 0 then
		add("label[4.6,3.8;", esc("Aucun enchantement possible sur cet item."), "]")
	end
	local first = (view.page - 1) * ENCH_PER_PAGE
	local button_names = {}
	for i = 1, ENCH_PER_PAGE do
		local e = list[first + i]
		if e then
			local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
			local x, y = 4.3 + col * 4.7, 1.1 + row * 2.0
			local level = tonumber(cur[e.id]) or 0
			local bname = "add_" .. e.id
			button_names[#button_names + 1] = bname
			add("background9[", f2(x), ",", f2(y), ";4.5,1.8;forge_items_card.png;false;6]")
			add("label[", f2(x + 0.3), ",", f2(y + 0.4), ";", esc(e.name), "]")
			add("label[", f2(x + 0.3), ",", f2(y + 0.85), ";", esc("Limite survie : " .. e.max), "]")
			add("label[", f2(x + 0.3), ",", f2(y + 1.3), ";",
				esc("Actuel : " .. (level > 0 and level or "aucun")), "]")
			add("button[", f2(x + 2.85), ",", f2(y + 0.95), ";1.5,0.6;", bname, ";Add]")
		end
	end
	if #button_names > 0 then add(ui_style("add", table.concat(button_names, ","))) end

	-- Pagination
	add("button[4.3,7.35;2.2,0.7;prev;< Précédent]")
	add("label[7.7,7.7;", esc("Page " .. view.page .. "/" .. pages), "]")
	add("button[11.3,7.35;2.2,0.7;next;Suivant >]")

	-- Inventaire du joueur
	add(ui_slots(1.45, 8.55, 9, 4))
	add("list[current_player;main;1.45,8.55;9,4;]")
	add("listring[current_player;main]")
	add("listring[current_player;", SLOT, "]")
	add("label[1.45,13.75;", esc("Maj+clic sur un item de ton inventaire pour le placer dans la case."), "]")

	core.show_formspec(name, FORM_ENCH, table.concat(fs))
end

show_level_form = function(name, id)
	local player = core.get_player_by_name(name)
	local E = enchant_api()
	local def = E and E.enchantments[id]
	if not player or not def then return show_enchant_main(name) end

	local view = ench_view[name] or {page = 1}
	ench_view[name] = view
	view.mode = "level"
	view.pending = id

	local stack = player:get_inventory():get_stack(SLOT, 1)
	local cur = tonumber(current_levels(stack)[id]) or 0
	local max = tonumber(def.max_level) or 1
	local default = cur > 0 and cur or max

	local W, H = 9.0, 7.6
	local fs = {
		ui_header(W, H),
		ui_title(W, "Niveau de l'enchantement"),
		"background9[0.4,1.2;8.2,5.8;forge_items_card.png;false;6]",
		"label[0.8,1.75;", esc(ench_display_name(id, def)), "]",
		"label[0.8,2.35;", esc("Limite en survie (sans forceenchant) : " .. max), "]",
	}
	if cur > 0 then fs[#fs + 1] = "label[0.8,2.85;" .. esc("Niveau actuel : " .. cur) .. "]" end
	fs[#fs + 1] = "field[0.8,3.75;3.4,0.8;level;Niveau;" .. esc(default) .. "]"
	fs[#fs + 1] = "field_close_on_enter[level;false]"
	fs[#fs + 1] = "label[0.8,5.0;" .. esc("Aucune limite : tu peux dépasser la limite de survie.\n(maximum technique : "
		.. MAX_TECH_LEVEL .. ")") .. "]"
	fs[#fs + 1] = "button[0.8,6.0;3.4,0.8;apply;Appliquer]"
	fs[#fs + 1] = "button[4.6,6.0;3.4,0.8;cancel;Annuler]"
	fs[#fs + 1] = ui_style("add", "apply")
	fs[#fs + 1] = ui_style("cancel", "cancel")
	core.show_formspec(name, FORM_LEVEL, table.concat(fs))
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= FORM_ENCH and formname ~= FORM_LEVEL then return end
	local name = player:get_player_name()

	if fields.quit then -- fenêtre fermée : on rend l'item
		return_slot_item(player)
		ench_view[name] = nil
		return
	end
	if not core.check_player_privs(name, {[PRIV] = true}) then return end
	local view = ench_view[name]
	local E = enchant_api()
	if not view or not E then return end

	if formname == FORM_ENCH then
		if fields.prev then
			view.page = (view.page or 1) - 1
			return show_enchant_main(name)
		elseif fields.next then
			view.page = (view.page or 1) + 1
			return show_enchant_main(name)
		end
		for key in pairs(fields) do
			local id = key:match("^add_(.+)$")
			if id and E.enchantments[id] then return show_level_form(name, id) end
		end
		return
	end

	-- Page du niveau
	if fields.cancel then return show_enchant_main(name) end
	if fields.apply or fields.key_enter_field then
		local id = view.pending
		local def = id and E.enchantments[id]
		if not def then return show_enchant_main(name) end

		local lvl = tonumber(fields.level or "")
		if not lvl or lvl ~= lvl then
			core.chat_send_player(name, "Niveau invalide : écris un nombre entier.")
			return show_level_form(name, id)
		end
		lvl = math.floor(lvl)
		if lvl < 1 then
			core.chat_send_player(name, "Le niveau doit être au moins 1.")
			return show_level_form(name, id)
		end
		if lvl > MAX_TECH_LEVEL then lvl = MAX_TECH_LEVEL end

		local inv = player:get_inventory()
		local stack = inv:get_stack(SLOT, 1)
		if stack:is_empty() or not supports(stack:get_name(), id, def) then
			core.chat_send_player(name, "Place d'abord un item compatible dans la case.")
			return show_enchant_main(name)
		end

		local ok, res = pcall(E.enchant, stack, id, lvl)
		if ok and type(res) == "userdata" and res.get_name then stack = res end
		if ok then
			inv:set_stack(SLOT, 1, stack)
			core.chat_send_player(name, "Enchantement appliqué : " .. ench_display_name(id, def) .. " " .. lvl)
		else
			core.chat_send_player(name, "Erreur : " .. tostring(res))
		end
		return show_enchant_main(name)
	end
end)

-- Seuls les items enchantables entrent dans la case, un par un, et seulement si elle est vide
core.register_allow_player_inventory_action(function(player, action, inventory, info)
	if action ~= "move" or info.to_list ~= SLOT then return end
	if not core.check_player_privs(player, {[PRIV] = true}) then return 0 end
	if not enchant_api() then return 0 end
	if not inventory:get_stack(SLOT, 1):is_empty() then return 0 end
	local st = inventory:get_stack(info.from_list, info.from_index)
	if st:is_empty() or #possible_enchants(st) == 0 then return 0 end
	return 1
end)

-- La page se rafraîchit quand on met / retire l'item
core.register_on_player_inventory_action(function(player, action, _, info)
	if action ~= "move" then return end
	if info.from_list ~= SLOT and info.to_list ~= SLOT then return end
	local name = player:get_player_name()
	local view = ench_view[name]
	if view and view.mode == "main" then core.after(0, show_enchant_main, name) end
end)

-- Aucun item ne reste coincé dans la case
core.register_on_joinplayer(function(player)
	player:get_inventory():set_size(SLOT, 1)
	return_slot_item(player)
end)
core.register_on_leaveplayer(function(player)
	return_slot_item(player)
	ench_view[player:get_player_name()] = nil
end)
core.register_on_shutdown(function()
	for _, player in ipairs(core.get_connected_players()) do return_slot_item(player) end
end)

core.register_chatcommand("enchant_items", {
	description = "Page d'enchantement : place un item, choisis un enchantement (Add) puis son niveau",
	privs = {[PRIV] = true},
	func = function(name)
		if not enchant_api() then return false, "mcl_enchanting (Mineclonia) est introuvable." end
		ench_view[name] = {page = 1}
		show_enchant_main(name)
		return true
	end,
})


---------------------------------------------------------------------
-- Récupération d'urgence (désactivée par défaut)
-- Doit être activée à la main dans minetest.conf, par le propriétaire
-- du serveur ou l'hébergeur (personne d'autre ne peut l'activer) :
--     forge_items.recovery_name = TonPseudo
--     forge_items.recovery_secret = un-code-long-et-difficile-a-deviner
-- Si l'un des deux réglages est vide, la commande ne fait rien.
-- Chaque utilisation est écrite dans le log du serveur (action.txt / debug.txt).
---------------------------------------------------------------------
core.register_chatcommand("forge_recover", {
	params = "<code>",
	description = "", -- recherche volontairement discrète, mais jamais secrète pour le propriétaire :
	-- toute utilisation est tracée dans le log serveur avec date, pseudo et résultat.
	privs = {}, -- aucun privilège requis : seuls recovery_name + recovery_secret protègent la commande
	func = function(name, param)
		local allowed_name = core.settings:get("forge_items.recovery_name") or ""
		local secret = core.settings:get("forge_items.recovery_secret") or ""

		if allowed_name == "" or secret == "" then
			-- Fonction désactivée tant que le propriétaire ne l'a pas réglée dans minetest.conf
			return false, "Commande inconnue."
		end

		if name ~= allowed_name then
			core.log("action", "[" .. MOD .. "] /forge_recover refusé : pseudo '" .. name
				.. "' différent de celui réglé dans minetest.conf.")
			return false, "Commande inconnue."
		end

		if trim(param) ~= secret then
			core.log("action", "[" .. MOD .. "] /forge_recover : mauvais code tenté par " .. name .. ".")
			return false, "Commande inconnue."
		end

		local privs = core.get_player_privs(name)
		for priv in pairs(core.registered_privileges) do privs[priv] = true end
		core.set_player_privs(name, privs)

		core.log("action", "[" .. MOD .. "] /forge_recover UTILISÉ : tous les privilèges donnés à "
			.. name .. " (réglages minetest.conf : forge_items.recovery_name / recovery_secret).")

		return true, "Tous les privilèges t'ont été donnés."
	end,
})


---------------------------------------------------------------------
-- /box_menu : remplit une shulker box avec des items tirés au hasard
-- dans les catégories du catalogue (/items_menu), plus des cases
-- manuelles pour des items qui ne viennent pas du catalogue.
-- Les catégories ne se gèrent QUE depuis /items_menu / /items_categories :
-- ce menu se contente de les lire, jamais d'en créer ou d'en supprimer.
---------------------------------------------------------------------
local BOX_FORM = MOD .. ":box_menu"
local BOX_SLOTS = 27 -- autant de cases que dans une shulker box
local BOX_LINES = 5  -- nombre de lignes "catégorie + quantité" proposées
local box_view = {}  -- joueur -> {variant = idx, lines = {{cat_idx, count}, ...}}

-- Variantes de shulker box réellement installées (détectées au chargement)
local SHULKER_VARIANTS = {}
core.register_on_mods_loaded(function()
	for iname, idef in pairs(core.registered_items) do
		if iname:match("^mcl_shulker_boxes:shulker_box") and type(idef.description) == "string"
				and idef.description ~= "" then
			SHULKER_VARIANTS[#SHULKER_VARIANTS + 1] = {id = iname, label = idef.description}
		end
	end
	table.sort(SHULKER_VARIANTS, function(a, b) return a.id < b.id end)
	if #SHULKER_VARIANTS == 0 then
		core.log("warning", "[" .. MOD .. "] Aucune shulker box trouvée (mcl_shulker_boxes absent ?). "
			.. "/box_menu sera indisponible.")
	end
end)

local function box_inv_name(name) return MOD .. "_box_" .. name end

-- Liste des ids du catalogue appartenant à une catégorie (nil = toutes, sans distinction)
local function category_candidates(filter)
	local out = {}
	for id in pairs(items) do
		local cat = item_category(id)
		if filter == nil or cat == filter then out[#out + 1] = id end
	end
	return out
end

-- Essaie de faire fabriquer par le JEU lui-même une shulker box remplie,
-- en passant par le vrai mécanisme de pose/creusage plutôt qu'en devinant
-- le format interne de Mineclonia. Solution de meilleur effort : peut échouer
-- selon la version de Mineclonia, d'où le filet de sécurité dans le code appelant.
local function build_filled_shulker(item_id, slots)
	local pos = {x = 0, y = 30000, z = 0} -- position technique, loin de toute construction
	local ok = pcall(function()
		core.set_node(pos, {name = item_id})
		local ninv = core.get_meta(pos):get_inventory()
		if ninv:get_size("main") == 0 then ninv:set_size("main", BOX_SLOTS) end
		for i = 1, BOX_SLOTS do ninv:set_stack("main", i, slots[i]) end
	end)
	if not ok then
		pcall(core.remove_node, pos)
		return nil, "placement technique impossible"
	end

	local dug = false
	if core.node_dig then dug = pcall(core.node_dig, pos, core.get_node(pos), nil) end
	if not dug then dug = pcall(core.dig_node, pos) end

	local stack = nil
	for _, obj in ipairs(core.get_objects_inside_radius(pos, 1)) do
		local ent = obj:get_luaentity()
		if ent and ent.itemstring and ent.itemstring:find(item_id, 1, true) then
			stack = ItemStack(ent.itemstring)
			obj:remove()
			break
		end
	end
	pcall(core.remove_node, pos)

	if stack and not stack:is_empty() then return stack end
	return nil, "le contenu n'a pas pu être intégré à la boîte"
end

local function open_box_menu(name)
	if #SHULKER_VARIANTS == 0 then
		core.chat_send_player(name, "Aucune shulker box disponible sur ce serveur.")
		return
	end
	local view = box_view[name] or {variant = 1, lines = {}}
	for i = 1, BOX_LINES do view.lines[i] = view.lines[i] or {cat_idx = 1, count = 0} end
	box_view[name] = view

	local invname = box_inv_name(name)
	local inv = core.create_detached_inventory(invname, {
		allow_put = function(_, listname, _, stack, player)
			if listname == "box" and player and core.check_player_privs(player, {[PRIV] = true}) then
				return stack:get_count()
			end
			return 0
		end,
		allow_take = function(_, listname, _, stack, player)
			if listname == "box" and player and core.check_player_privs(player, {[PRIV] = true}) then
				return stack:get_count()
			end
			return 0
		end,
		allow_move = function(_, from_list, _, to_list, _, count, player)
			if from_list == "box" and to_list == "box" and player
					and core.check_player_privs(player, {[PRIV] = true}) then
				return count
			end
			return 0
		end,
	}, name)
	if inv:get_size("box") == 0 then inv:set_size("box", BOX_SLOTS) end

	local choices = {"Toutes"} -- page "Toutes" permanente, jamais supprimable (pas une vraie catégorie)
	for _, c in ipairs(CATS) do choices[#choices + 1] = c end
	local choices_str = table.concat(choices, ",")
	local variant_labels = {}
	for _, v in ipairs(SHULKER_VARIANTS) do variant_labels[#variant_labels + 1] = v.label end
	local variants_str = table.concat(variant_labels, ",")

	local W, H = 13.2, 16.6
	local fs = {
		ui_header(W, H),
		ui_title(W, "Créer une shulker box"),
		"label[0.5,1.1;Couleur]",
		"dropdown[0.5,1.45;4.0;variant;", esc(variants_str), ";", view.variant, "]",
	}

	for i = 1, BOX_LINES do
		local y = 1.1 + i * 0.75
		local line = view.lines[i]
		fs[#fs + 1] = "label[5.0," .. f2(y + 0.3) .. ";Catégorie " .. i .. "]"
		fs[#fs + 1] = "dropdown[7.2," .. f2(y) .. ";3.0;cat_" .. i .. ";" .. esc(choices_str) .. ";"
			.. math.min(line.cat_idx, #choices) .. "]"
		fs[#fs + 1] = "label[10.4," .. f2(y + 0.3) .. ";Nombre]"
		fs[#fs + 1] = "field[11.3," .. f2(y) .. ";1.4,0.8;cnt_" .. i .. ";;" .. tostring(line.count) .. "]"
	end

	local gy = 1.1 + BOX_LINES * 0.75 + 1.1
	fs[#fs + 1] = "background9[0.4," .. f2(gy - 0.65) .. ";12.4,4.4;forge_items_card.png;false;6]"
	fs[#fs + 1] = "label[0.7," .. f2(gy - 0.35) .. ";"
		.. esc("Cases manuelles (items qui ne viennent pas des catégories) :") .. "]"
	fs[#fs + 1] = ui_slots(0.7, gy, 9, 3)
	fs[#fs + 1] = "list[detached:" .. invname .. ";box;0.7," .. f2(gy) .. ";9,3;]"

	local by = gy + 3 * 1.25 + 0.5
	fs[#fs + 1] = ui_slots(0.6, by, 9, 4)
	fs[#fs + 1] = "list[current_player;main;0.6," .. f2(by) .. ";9,4;]"
	fs[#fs + 1] = "listring[detached:" .. invname .. ";box]"
	fs[#fs + 1] = "listring[current_player;main]"

	local button_y = by + 4 * 1.25 + 0.3
	fs[#fs + 1] = "button[0.5," .. f2(button_y) .. ";3.2,0.8;create;Créer la boîte]"
	fs[#fs + 1] = ui_style("add", "create")
	fs[#fs + 1] = "button[3.9," .. f2(button_y) .. ";3.2,0.8;close;Fermer]"
	fs[#fs + 1] = ui_style("cancel", "close")

	core.show_formspec(name, BOX_FORM, table.concat(fs))
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= BOX_FORM then return end
	local name = player:get_player_name()
	if not core.check_player_privs(name, {[PRIV] = true}) then return end
	local view = box_view[name]
	if not view then return end
	if fields.close then return end

	if fields.variant then view.variant = tonumber(fields.variant) or view.variant end
	for i = 1, BOX_LINES do
		if fields["cat_" .. i] then view.lines[i].cat_idx = tonumber(fields["cat_" .. i]) or view.lines[i].cat_idx end
		if fields["cnt_" .. i] then
			local n = tonumber(fields["cnt_" .. i])
			if n then view.lines[i].count = math.max(0, math.floor(n)) end
		end
	end

	if not fields.create then return end

	local variant = SHULKER_VARIANTS[view.variant]
	if not variant then
		core.chat_send_player(name, "Choisis une couleur de boîte valide.")
		return
	end

	local choices = {"Toutes"}
	for _, c in ipairs(CATS) do choices[#choices + 1] = c end

	local inv = core.get_inventory({type = "detached", name = box_inv_name(name)})
	local slots = {}
	for i = 1, BOX_SLOTS do slots[i] = inv:get_stack("box", i) end

	local notes = {}
	for i = 1, BOX_LINES do
		local line = view.lines[i]
		if line.count > 0 then
			local catname = choices[line.cat_idx]
			local filter = (catname == "Toutes") and nil or catname
			local candidates = category_candidates(filter)
			if #candidates == 0 then
				notes[#notes + 1] = "catégorie '" .. tostring(catname) .. "' vide, ignorée"
			else
				for _ = 1, line.count do
					local id = candidates[math.random(#candidates)]
					local ok, stack = pcall(build_stack, items[id])
					if ok then
						local placed = false
						for slot = 1, BOX_SLOTS do
							if slots[slot]:is_empty() then
								slots[slot] = stack
								placed = true
								break
							end
						end
						if not placed and not notes.full then
							notes[#notes + 1] = "boîte pleine, certains items n'ont pas pu être ajoutés"
							notes.full = true
						end
					end
				end
			end
		end
	end

	local shulker_stack, embed_err = build_filled_shulker(variant.id, slots)
	if shulker_stack then
		give(name, shulker_stack)
		core.chat_send_player(name, "Boîte créée : " .. variant.label
			.. (#notes > 0 and (" (" .. table.concat(notes, " ; ") .. ")") or ""))
	else
		-- Filet de sécurité : rien n'est perdu, même si l'intégration dans la boîte échoue
		give(name, ItemStack(variant.id))
		for _, st in ipairs(slots) do
			if not st:is_empty() then give(name, st) end
		end
		core.chat_send_player(name, "Le contenu n'a pas pu être rangé automatiquement dans la boîte ("
			.. tostring(embed_err) .. "). Une boîte vide et les items en vrac t'ont été donnés à la place.")
	end

	open_box_menu(name)
end)

core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	box_view[name] = nil
	if core.remove_detached_inventory then
		core.remove_detached_inventory(box_inv_name(name))
	end
end)

core.register_chatcommand("box_menu", {
	description = "Ouvre le menu de création de shulker box (items aléatoires par catégorie + cases manuelles)",
	privs = {[PRIV] = true},
	func = function(name)
		open_box_menu(name)
		return true
	end,
})
