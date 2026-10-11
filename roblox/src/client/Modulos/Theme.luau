-- Tema do jogo web (styles.css) em valores do Roblox: cores, fontes e tamanhos.
-- 1 rem = 15 px × escala da fonte (Opções > Tamanho do texto), como `html { font-size: calc(15px * var(--fs)) }`.
local T = {}

local hex = Color3.fromHex
T.hex = hex

local BASE = {
	-- moldura (tinta)
	ink = hex("#1f1d27"), ink2 = hex("#2a2833"), ink3 = hex("#363341"),
	onInk = hex("#f3ead6"), onInkMuted = hex("#b5aec4"),
	-- superfícies (pergaminho)
	paper = hex("#f3ecdc"), paper2 = hex("#fbf7ee"), paper3 = hex("#e8dec7"),
	line = hex("#d9ccb0"), cream = hex("#f3e3c0"), text = hex("#2b2a33"), muted = hex("#645f70"),
	-- acentos
	grass = hex("#2e8b47"), gold = hex("#f2b632"), goldHi = hex("#ffd45c"), goldText = hex("#8a5d00"),
	red = hex("#b8412f"), blue = hex("#1f6fb2"), good = hex("#23803d"), bad = hex("#b8412f"), purple = hex("#7a52c4"),
	white = hex("#ffffff"), black = hex("#000000"),
}
-- body.high-contrast
local HIGH = {
	ink = hex("#000000"), ink2 = hex("#0b0b0b"), ink3 = hex("#1a1a1a"), onInk = hex("#ffffff"), onInkMuted = hex("#e6e6e6"),
	paper = hex("#ffffff"), paper2 = hex("#ffffff"), paper3 = hex("#f0f0f0"), line = hex("#000000"),
	muted = hex("#2b2a33"), text = hex("#000000"), good = hex("#0a6b23"), bad = hex("#a1150b"),
}

-- T.c.<nome> é a cor atual (muda com o alto contraste).
T.c = table.clone(BASE)

T.rarity = { comum = hex("#6f7782"), raro = hex("#2f7cc0"), epico = hex("#7a52c4"), lendario = hex("#b9820e") }

-- Cor dos ícones de recurso: no pergaminho (.c-*) e na barra escura do topo (#hud .c-*).
T.res = {
	gold = hex("#b07a00"), food = hex("#a8741d"), wood = hex("#7a4e2a"), stone = hex("#5f6b72"),
	gems = hex("#1f7fc4"), crowns = hex("#b9820e"), heart = hex("#c0392b"), def = BASE.good, scrolls = hex("#b9820e"),
}
T.resHud = {
	gold = hex("#f5c542"), food = hex("#ebb763"), wood = hex("#d9a06a"), stone = hex("#c5ced3"),
	gems = hex("#6cc4f5"), heart = hex("#ff7a6b"), crowns = hex("#b9820e"), def = BASE.good, scrolls = hex("#b9820e"),
}
-- Cores dos números flutuantes no mapa (RES_COLORS de src/ui/assets.js).
T.float = { gold = hex("#f2b632"), food = hex("#f0c27a"), wood = hex("#c8834a"), stone = hex("#d7dde0"), gems = hex("#7cc6f0") }

T.fs = 1
T.highContrast = false

function T.rem(n)
	return math.floor(15 * T.fs * n + 0.5)
end

-- Tamanho fixo em px (o que o CSS escreve em px não cresce com a fonte).
function T.px(n)
	return n
end

function T.apply(config)
	T.fs = config and config.fontScale or 1
	T.highContrast = config and config.highContrast or false
	for k, v in BASE do
		T.c[k] = v
	end
	if T.highContrast then
		for k, v in HIGH do
			T.c[k] = v
		end
	end
end

local NUNITO = "rbxasset://fonts/families/Nunito.json"
T.font = Font.new(NUNITO, Enum.FontWeight.Regular)
T.bold = Font.new(NUNITO, Enum.FontWeight.ExtraBold)
T.black = Font.new(NUNITO, Enum.FontWeight.Heavy)

-- Raios de borda (--r-sm, --r, --r-lg).
T.rSm, T.r, T.rLg = 8, 12, 16

-- Breakpoints do styles.css.
T.BP_MID = 1180
T.BP_MOBILE = 860
T.BP_SMALL = 420

return T
