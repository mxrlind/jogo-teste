-- Imagens recortadas das folhas (atlas): Assets.image("building-casa-1") devolve as props de um ImageLabel.
-- Os nomes são os de tools/atlas.py: sprites KayKit pelo nome do arquivo, "rts-u13", "blades-1".."blades-12",
-- ícones como "ico/gold" e peças de interface como "ui/grey_button00".
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Atlas = require(script.Parent.Atlas)
local Imagens = require(ReplicatedStorage:WaitForChild("Reino"):WaitForChild("Imagens"))

local A = {}

local function idOf(sheet)
	local id = Imagens.sheets[sheet]
	if not id or id == "" or id == "rbxassetid://0" then
		return nil
	end
	return id
end

A.ready = idOf("sprites-1") ~= nil

function A.has(name)
	local r = Atlas.rects[name]
	return r ~= nil and idOf(r[1]) ~= nil
end

-- Tamanho original (px) de uma imagem no atlas, ou nil.
function A.size(name)
	local r = Atlas.rects[name]
	return r and Vector2.new(r[4], r[5]) or nil
end

local cache = {}
-- Props de ImageLabel/ImageButton para mostrar `name`. Sem id enviado, devolve Image = "" (fica invisível).
function A.image(name)
	local p = cache[name]
	if p then
		return p
	end
	local r = Atlas.rects[name]
	if not r then
		return { Image = "" }
	end
	local id = idOf(r[1])
	p = {
		Image = id or "",
		ImageRectOffset = Vector2.new(r[2], r[3]),
		ImageRectSize = Vector2.new(r[4], r[5]),
	}
	cache[name] = p
	return p
end

-- Junta as props da imagem com outras props (sem alterar o cache).
function A.with(name, props)
	local out = table.clone(A.image(name))
	for k, v in props do
		out[k] = v
	end
	return out
end

-- Todos os ids de folhas (para ContentProvider:PreloadAsync na tela de carregamento).
function A.allIds()
	local out = {}
	for _, sheet in Atlas.sheets do
		local id = idOf(sheet)
		if id then
			table.insert(out, id)
		end
	end
	return out
end

function A.audioId(name)
	local id = Imagens.audio and Imagens.audio[name]
	if not id or id == "" or id == "rbxassetid://0" then
		return nil
	end
	return id
end

return A
