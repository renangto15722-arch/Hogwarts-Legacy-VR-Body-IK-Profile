--[[
	body.lua — Corpo VR (IK) para Hogwarts Legacy

	Corpo em primeira pessoa a partir do esqueleto do personagem, via libs/ik.lua.
	Ajustes: painel "VR Body" e painel "IK Dev Config" (data/ik_parameters.json).
	O PORQUÊ de cada decisão está no LEIAME_CORPO_VR.md; aqui, só o que o código faz.
]]--

local uevrUtils      = require("libs/uevr_utils")
local configui       = require("libs/configui")
local animation      = require("libs/animation")
local controllers    = require("libs/controllers")
local hands          = require("libs/hands")
local ik             = require("libs/ik")
local bodyYaw        = require("libs/body_yaw")
local handAnimations = require("helpers/hand_animations")
local mounts         = require("helpers/mounts")
local wandHelper     = require("helpers/wand")
require("libs/enums/unreal")

-- EVisibilityBasedAnimTickOption::AlwaysTickPoseAndRefreshBones (falta no enums da lib)
local ALWAYS_TICK_POSE_AND_REFRESH_BONES = 0

-- Painel "IK Dev Config" (ajuste fino) na UI do UEVR.
local SHOW_DEV_UI = true

-- Palpite inicial; se não existir na malha, a detecção automática corrige.
local HEAD_BONE = "Head"

-- Filhos de Pawn.Mesh que nunca entram no corpo (nome parcial, sem caixa).
local EXCLUDED_MESHES = { "preview", "shadowproxy" }

local currentRig    = nil   -- instância do rig de IK ativa
local bodyMeshes    = {}    -- cópias PoseableMesh criadas pelo IK
local meshTags      = {}    -- tags de animação encontradas na última criação
-- Quantos polls ainda devem REPOR a pose da varinha. Recriar o corpo re-registra
-- as animações de mão e a pose volta à aberta; o updateWandGrip só age na mudança
-- de estado, então sem isto a mão fica aberta segurando a varinha até você
-- guardar e sacar de novo. São vários polls porque o initHandAnimations ainda
-- está assentando quando o primeiro cai.
local wandGripPending = 0
local headBone      = HEAD_BONE -- nome real do osso da cabeça nesta malha
-- Malhas filhas (roupa, luvas...) presas a Pawn.Mesh na última criação do corpo.
-- Zero = o personagem ainda estava carregando (ver `rebuildWhenCharacterLoads`).
local builtChildCount = nil
local readyRebuilds   = 0   -- quantas vezes isso já refez o corpo, com teto

-- === Log e proteção contra erro ===
-- Sem setLogToFile nada chega no log.txt, e o filtro do perfil é Error: só o que
-- sai por logMilestone aparece lá (armadilha 1). log() vai para o console.
uevrUtils.setLogToFile(true)

local function log(text, level)
	uevrUtils.print("[body] " .. text, level or LogLevel.Info)
end

local function logMilestone(text)
	uevrUtils.print("[body] " .. text, LogLevel.Error)
end

-- Cada mensagem sai uma vez só: um pcall que estoura todo frame encheria o log.
local loggedFailures = {}

local function logTickFailure(prefix, err)
	local text = prefix .. ": " .. tostring(err)
	if loggedFailures[text] then return end
	loggedFailures[text] = true
	logMilestone(text)
end

-- Protege o callback: os timers do uevr_utils rodam sem pcall (uevr_utils:1123).
local function guard(what, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then logTickFailure(what, err) end
end

local function isEnabled()
	return configui.getValue("body_enabled") == true
end

-- === Acesso às cópias do corpo ===
-- O corpo são várias malhas: tudo é escrito em TODAS. Único jeito de percorrer.

-- `method` é o nome do método exigido (nil = basta a malha ser válida).
local function forEachMesh(method, fn)
	for _, mesh in ipairs(bodyMeshes) do
		if uevrUtils.getValid(mesh) ~= nil and (method == nil or mesh[method] ~= nil) then
			fn(mesh)
		end
	end
end

-- Sem closure: roda por osso e por frame na animação das pernas.
local function setBoneOnAll(fname, transform)
	for _, mesh in ipairs(bodyMeshes) do
		if uevrUtils.getValid(mesh) ~= nil and mesh.SetBoneTransformByName ~= nil then
			mesh:SetBoneTransformByName(fname, transform, EBoneSpaces.ComponentSpace)
		end
	end
end

-- (x, y, z) em uma linha, para os logs.
local function fmt(v)
	if v == nil then return "nil" end
	return string.format("(%.1f, %.1f, %.1f)", v.X or v.x or 0, v.Y or v.y or 0, v.Z or v.z or 0)
end

-- Vetor do painel: o configui devolve X/Y/Z maiúsculo ou minúsculo.
local function vec3Of(value)
	if value == nil then return 0, 0, 0 end
	return value.x or value.X or 0, value.y or value.Y or 0, value.z or value.Z or 0
end

-- Yaw do "Mesh Rotation Offset" do rig (dono único: painel IK Dev Config).
local function rigMeshYaw()
	if currentRig ~= nil and currentRig.meshRotationOffset ~= nil then
		return currentRig.meshRotationOffset.Yaw or 0
	end
	return 0
end

-- === Malhas que formam o corpo ===

local function shortName(component)
	local fullName = component:get_full_name()
	return fullName:match("([^%.]+)$") or fullName
end

local function isExcluded(name)
	local lowerName = string.lower(name)
	for _, excluded in ipairs(EXCLUDED_MESHES) do
		if string.find(lowerName, excluded, 1, true) ~= nil then
			return true
		end
	end
	return false
end

local function isSkeletalMesh(component)
	if uevrUtils.getValid(component) == nil then return false end
	local class = uevrUtils.get_class("Class /Script/Engine.SkeletalMeshComponent")
	if class ~= nil and component.is_a ~= nil and not component:is_a(class) then
		return false
	end
	-- só interessa se realmente tem uma malha carregada (UE4 x UE5)
	return uevrUtils.getValid(component, {"SkeletalMesh"}) ~= nil
		or uevrUtils.getValid(component, {"SkeletalMeshAsset"}) ~= nil
end

-- Malha viva de origem. Montado, o pawn é a CRIATURA: tem de sair do
-- RiderCharacter, senão o corpo VR vira o bicho (armadilha 7).
local function getPlayerBodyMesh(shouldLog)
	local playerPawn = uevrUtils.getValid(pawn)
	local baseMesh = playerPawn ~= nil and uevrUtils.getValid(playerPawn, {"Mesh"}) or nil

	if playerPawn ~= nil and not mounts.isWalking() then
		local rider = uevrUtils.getValid(mounts.getMountPawn(playerPawn))
		local riderMesh = rider ~= nil and uevrUtils.getValid(rider, {"Mesh"}) or nil
		if riderMesh ~= nil and riderMesh ~= baseMesh then
			baseMesh = riderMesh
			if shouldLog then
				logMilestone("Montado: corpo criado a partir da malha do personagem, nao da criatura")
			end
		end
	end

	return baseMesh
end

-- Quantas malhas modulares estão presas ao personagem AGORA (mesmo filtro do
-- getCustomIKComponent). Numa troca de nível o personagem nasce sem nenhuma.
local function countBodyChildMeshes()
	local baseMesh = getPlayerBodyMesh(false)
	if baseMesh == nil then return nil end
	local children = baseMesh.AttachChildren
	if children == nil then return 0 end
	local count = 0
	for _, child in ipairs(children) do
		if isSkeletalMesh(child) and not isExcluded(shortName(child)) then
			count = count + 1
		end
	end
	return count
end

-- ik.lua, "animation_mesh" = Custom. Tem de ser a mesma malha de origem.
function getCustomAnimationIKComponent(rigID)
	return getPlayerBodyMesh(false)
end

-- ik.lua, "mesh" = Custom. A primeira tem de ser Pawn.Mesh (referência dos solvers).
function getCustomIKComponent(rigID)
	meshTags = {}

	local baseMesh = getPlayerBodyMesh(true)

	if baseMesh == nil then
		log("Pawn.Mesh indisponível, corpo não foi criado", LogLevel.Warning)
		builtChildCount = nil
		return {}
	end

	local templates = {}
	table.insert(templates, { descriptor = "Pawn.Mesh", instance = baseMesh, animation = "Body" })
	meshTags["Body"] = true

	-- Roupa, luvas e braços entram sempre; a origem é escolhida no IK Dev Config.
	do
		local children = baseMesh.AttachChildren
		if children ~= nil then
			for _, child in ipairs(children) do
				if isSkeletalMesh(child) then
					local name = shortName(child)
					if isExcluded(name) then
						log("Malha ignorada: " .. name)
					else
						local tag = nil
						if string.find(name, "Arm") ~= nil then
							tag = "Arms"
						elseif string.find(name, "Glove") ~= nil then
							tag = "Gloves"
						end
						if tag ~= nil and meshTags[tag] == true then
							tag = nil -- só a primeira malha de cada tipo recebe as animações de dedo
						end
						if tag ~= nil then meshTags[tag] = true end

						table.insert(templates, {
							descriptor = "Pawn.Mesh(" .. name .. ")",
							instance = child,
							animation = tag,
							optional = true,
						})
						log("Malha do corpo: " .. name .. (tag ~= nil and (" [" .. tag .. "]") or ""))
					end
				end
			end
		end
	end

	builtChildCount = #templates - 1 -- sem contar Pawn.Mesh
	log("Total de malhas no corpo: " .. #templates)
	return templates
end

-- === Animação dos dedos, reaproveitando as poses do perfil ===

-- Os IDs do hands_animation são "<mão>_<alvo>": "body", "hand", "glove".
local function buildAnimationTable()
	local profile = {}
	local targets = { Body = "body", Arms = "hand", Gloves = "glove" }
	for tag, target in pairs(targets) do
		if meshTags[tag] == true then
			profile[tag] = {
				Left  = { AnimationID = "left_"  .. target },
				Right = { AnimationID = "right_" .. target },
			}
		end
	end
	return { animations = { Shared = handAnimations }, profiles = { Main = profile } }
end

-- === Ossos: nome errado faz o ik.lua descartar o solver EM SILÊNCIO ===

-- palavras que descartam um osso como sendo a mão (dedos e ossos auxiliares)
local NOT_A_HAND = {
	"index", "middle", "ring", "pinky", "thumb", "finger", "twist", "roll",
	"ik", "attach", "socket", "weapon", "prop", "end", "tip", "ctrl", "helper",
}

local NOT_A_HEAD = { "top", "end", "attach", "socket", "ik", "ctrl", "helper", "hat", "wear" }

-- nomes exatos mais comuns, em ordem de preferência (minúsculas)
local HAND_NAMES = {
	[Handed.Right] = { "righthand", "hand_r", "r_hand", "hand_right", "bip01 r hand", "bip01_r_hand", "mixamorig:righthand" },
	[Handed.Left]  = { "lefthand",  "hand_l", "l_hand", "hand_left",  "bip01 l hand", "bip01_l_hand", "mixamorig:lefthand"  },
}

local HEAD_NAMES = { "head", "bip01 head", "bip01_head", "mixamorig:head", "b_head", "head_01" }

local function toBoneSet(names)
	local set = {}
	for _, name in ipairs(names) do
		set[string.lower(name)] = name
	end
	return set
end

local function containsAny(lowerName, words)
	for _, word in ipairs(words) do
		if string.find(lowerName, word, 1, true) ~= nil then return true end
	end
	return false
end

-- separadores usados pelas convenções de nome: hand_r, hand.r, hand-r, "Bip01 R Hand"
local SEPARATOR = "[_%.%-%s]"

local function hasSideMarker(lowerName, side)
	local word, letter = "left", "l"
	if side == Handed.Right then word, letter = "right", "r" end
	return string.find(lowerName, word, 1, true) ~= nil
		or string.match(lowerName, SEPARATOR .. letter .. "$") ~= nil
		or string.match(lowerName, SEPARATOR .. letter .. SEPARATOR) ~= nil
end

-- Nomes conhecidos primeiro; depois palavra-chave + lado, vencendo o nome mais
-- curto (a raiz: LeftHand, não LeftHandIndex1). Mão, pé e cabeça saem daqui.
local function detectBone(names, set, knownNames, keywords, rejects, side)
	for _, candidate in ipairs(knownNames) do
		if set[candidate] ~= nil then return set[candidate] end
	end

	for _, keyword in ipairs(keywords) do
		local best = nil
		for _, name in ipairs(names) do
			local lower = string.lower(name)
			if string.find(lower, keyword, 1, true) ~= nil
				and not containsAny(lower, rejects)
				and (side == nil or hasSideMarker(lower, side))
				and (best == nil or #name < #best)
			then
				best = name
			end
		end
		if best ~= nil then return best end
	end

	return nil
end

local function detectHandBone(names, set, side)
	return detectBone(names, set, HAND_NAMES[side], { "hand", "wrist" }, NOT_A_HAND, side)
end

local function detectHeadBone(names, set)
	return detectBone(names, set, HEAD_NAMES, { "head" }, NOT_A_HEAD)
end

-- Cadeia até a raiz: {osso, pai, avô, ...}. Com teto (o da lib é while sem limite).
local function getBoneChain(mesh, boneName, maxDepth)
	local chain = { boneName }
	local current = boneName
	for _ = 1, (maxDepth or 6) do
		local parent = mesh:GetParentBone(current)
		if parent == nil then break end
		parent = parent:to_string()
		if parent == "" or parent == "None" or parent == current then break end
		table.insert(chain, parent)
		current = parent
	end
	return chain
end

-- Corrige os ossos de um solver; true se mudou. Só a mão é adivinhada.
local function fixSolverBones(rig, mesh, names, set, solverId, solverParams)
	local side = Handed.Right
	if solverParams["end_control_type"] == 0 then side = Handed.Left end

	local endBone = solverParams["end_bone"] or ""
	if endBone ~= "" and set[string.lower(endBone)] ~= nil then
		return false -- o nome configurado existe na malha, não mexe
	end

	local detected = detectHandBone(names, set, side)
	-- se um lado foi achado e o outro não, espelha o nome
	if detected == nil then
		local other = detectHandBone(names, set, side == Handed.Right and Handed.Left or Handed.Right)
		if other ~= nil then
			detected = uevrUtils.findOppositeBone(other, side == Handed.Right, names)
		end
	end

	if detected == nil then
		log("Não achei o osso da mão " .. (side == Handed.Right and "direita" or "esquerda")
			.. " para o solver '" .. tostring(solverId) .. "'. Use 'Listar ossos no log' e "
			.. "escolha na aba IK Dev Config.", LogLevel.Warning)
		return false
	end

	local chain = getBoneChain(mesh, detected, 5)
	if #chain < 3 then
		log("Osso '" .. detected .. "' não tem antebraço e braço acima dele, ignorado", LogLevel.Warning)
		return false
	end

	log("Solver '" .. tostring(solverId) .. "': usando " .. chain[3] .. " -> " .. chain[2] .. " -> " .. chain[1])
	rig:setConfigParameter({ "solvers", solverId, "end_bone" }, chain[1], true)
	rig:setConfigParameter({ "solvers", solverId, "joint_bone" }, chain[2], true)
	rig:setConfigParameter({ "solvers", solverId, "start_bone" }, chain[3], true)

	-- ombro e espinha (usados só pelo modo "Somente braços") saem da mesma cadeia
	local shoulderKey = side == Handed.Right and "right_shoulder_bone_name" or "left_shoulder_bone_name"
	if chain[4] ~= nil then
		rig:setConfigParameter(shoulderKey, chain[4], true)
		if chain[5] ~= nil then
			rig:setConfigParameter("spine_bone_name", chain[5], true)
		end
	end

	return true
end

-- Devolve true se algum osso foi corrigido (nesse caso o corpo é reconstruído).
local function detectBones(rig, force)
	local mesh = bodyMeshes[1]
	if uevrUtils.getValid(mesh) == nil then return false end

	local names = uevrUtils.getBoneNames(mesh)
	if names == nil or #names == 0 then
		log("A malha do corpo não devolveu nenhum osso", LogLevel.Warning)
		return false
	end
	local set = toBoneSet(names)

	-- cabeça (não faz parte do rig, aplica na hora)
	if set[string.lower(headBone)] == nil or force then
		local detectedHead = detectHeadBone(names, set)
		if detectedHead ~= nil then
			if detectedHead ~= headBone then
				log("Osso da cabeça: " .. detectedHead)
			end
			headBone = detectedHead
		else
			log("Não achei o osso da cabeça; 'Esconder a cabeça' não vai funcionar", LogLevel.Warning)
		end
	end

	-- os solvers saem do arquivo, não do rig: nome errado nem chega em activeSolvers
	if json == nil then return false end
	local params = json.load_file("ik_parameters.json")
	local rigParams = params ~= nil and params[rig.rigId or ""] or nil
	local solvers = rigParams ~= nil and rigParams.solvers or nil
	if solvers == nil then return false end

	local changed = false
	for solverId, solverParams in pairs(solvers) do
		if force then solverParams["end_bone"] = "" end
		if fixSolverBones(rig, mesh, names, set, solverId, solverParams) then
			changed = true
		end
	end
	return changed
end

-- === Visibilidade ===

-- SEMPRE ATIVO: a câmera fica dentro da cabeça. O osso é encolhido, não movido.
local function applyHeadVisibility()
	local scale = uevrUtils.vector(0.001, 0.001, 0.001, true)
	local fname = uevrUtils.fname_from_string(headBone)
	forEachMesh("SetBoneScaleByName", function(mesh)
		mesh:SetBoneScaleByName(fname, scale, EBoneSpaces.ComponentSpace)
	end)
end

-- A cópia é só visual e não pertence ao pawn (nasce sem parent e é presa depois),
-- então o trace de interação do jogo NÃO a ignora: com colisão, ela fica na frente
-- do que você quer pegar. 0 = NoCollision.
local function disableBodyCollision()
	forEachMesh("SetCollisionEnabled", function(mesh)
		pcall(function() mesh:SetCollisionEnabled(0, false) end)
	end)
end

local function applyShadowSetting()
	local castShadow = configui.getValue("body_shadow") == true
	forEachMesh(nil, function(mesh)
		mesh.bCastDynamicShadow = castShadow
		-- BoundsScale grande: sem ele o frustum descarta o corpo (a origem fica nos pés).
		mesh.BoundsScale = 16.0
		-- bRenderInDepthPass não é forçado: em Native Stereo, candidato a artefato.
	end)
end

-- === Cinemática em primeira pessoa ===
-- Com "First Person Cinematics" LIGADO o main.lua não trata a cena: não vai para
-- terceira pessoa e não devolve a malha do jogo. Quem tem de aparecer ali é o
-- corpo VR, e a malha do jogo tem de continuar escondida (isso é o
-- `keepGameMeshHidden` abaixo). DESLIGADO, nada muda: cena em terceira pessoa e
-- corpo escondido, como no perfil do Pande. Ver LEIAME.
local function isFPCinematic()
	return configui.getValue("fpCinematic") == true
end

-- Some em terceira pessoa e em cinemática. NA MONTARIA NÃO: é onde o corpo importa.
local function shouldHideBody()
	if configui.getValue("isFP") == false then return true end
	local playerPawn = uevrUtils.getValid(pawn)
	if playerPawn == nil then return true end
	if playerPawn.InCinematic == true and not isFPCinematic() then return true end
	return false
end

-- InCinematic oscila: só esconde após duas leituras seguidas. Voltar é imediato.
local hideStreak = 0
local bodyHidden = false

-- Estado FILTRADO: é este que o arquivo usa, nunca o shouldHideBody() cru.
local function isBodyHidden()
	return bodyHidden
end

uevrUtils.registerUEVRCallback("is_hands_hidden", function()
	if not isEnabled() then return nil end
	if shouldHideBody() then
		hideStreak = hideStreak + 1
	else
		hideStreak = 0
	end
	bodyHidden = hideStreak >= 2
	return bodyHidden, 20
end)

-- === 1. Pernas animadas ===
-- Copia só a subárvore das pernas, reancorada no quadril da cópia. Ver LEIAME.

local RTS_COMPONENT = 2 -- ERelativeTransformSpace::RTS_Component

local FOOT_NAMES = {
	[Handed.Right] = { "rightfoot", "foot_r", "r_foot", "bip01 r foot", "mixamorig:rightfoot" },
	[Handed.Left]  = { "leftfoot",  "foot_l", "l_foot", "bip01 l foot", "mixamorig:leftfoot"  },
}
local NOT_A_FOOT = { "toe", "ball", "ik", "attach", "socket", "twist", "roll", "ctrl", "helper", "end", "tip" }

local legBones = nil       -- { {name=..., fname=...}, ... } coxa para baixo
local legAnchorFName = nil -- quadril: a âncora das pernas

-- Malhas que recebem os ossos da perna. Escrever perna numa malha cujo esqueleto
-- nem tem o osso (luva, cabelo) é chamada de reflexão jogada fora, e são 30 ossos
-- vezes uma malha POR FRAME. A lista é montada uma vez, na criação.
local legMeshes = {}
-- As mesmas, já validadas neste frame. O getValid consulta o UObjectHook: fazer
-- isso por osso custava 30x o que custa fazer uma vez por frame.
local legFrameTargets = {}
local legFrameCount = 0

-- Pose de referência das pernas, em NÚMEROS (nunca guardar a struct do motor: ela
-- é reaproveitada). É para onde a perna volta quando a animação é desligada —
-- sem isso ela guarda o último passo, ou a pose crua da criatura, e fica torta.
local legRef = nil
local legsApplied = false

-- Quadril na pose de referência, lido na criação. A conta parte dele (armadilha 4).
local referenceHip = nil
-- Altura do quadril de pé, na malha de origem: é contra ela que o agachar é medido.
local standingSourceHipZ = nil
-- O quanto o quadril está abaixado agora (0 = em pé), suavizado.
local hipDrop = 0

-- Quanto o quadril saiu da referência; a cintura soma isto para acompanhá-lo.
local hipShift = { X = 0, Y = 0, Z = 0 }

-- Abaixo disto é balanço do andar, não agachamento. Sem lerp (armadilha 6).
local HIP_DROP_DEADZONE = 8.0

local function keepSourceMeshesAnimating(rig)
	for _, template in pairs(rig.meshTemplates or {}) do
		local source = template.instance
		if uevrUtils.getValid(source) ~= nil and source.VisibilityBasedAnimTickOption ~= nil then
			source.VisibilityBasedAnimTickOption = ALWAYS_TICK_POSE_AND_REFRESH_BONES
		end
	end
end

local function detectFootBone(names, set, side)
	return detectBone(names, set, FOOT_NAMES[side], { "foot", "ankle" }, NOT_A_FOOT, side)
end

-- Pé -> canela -> coxa -> quadril. A lista final é coxa + todos os descendentes.
local function detectLegBones(mesh)
	legBones, legAnchorFName = nil, nil
	legMeshes, legFrameCount = {}, 0
	legRef, legsApplied = nil, false
	referenceHip, standingSourceHipZ, hipDrop = nil, nil, 0
	hipShift.X, hipShift.Y, hipShift.Z = 0, 0, 0
	if uevrUtils.getValid(mesh) == nil then return end

	local names = uevrUtils.getBoneNames(mesh)
	if names == nil or #names == 0 then return end
	local set = toBoneSet(names)

	local bones, anchor = {}, nil
	for _, side in ipairs({ Handed.Right, Handed.Left }) do
		local foot = detectFootBone(names, set, side)
		if foot ~= nil then
			local chain = getBoneChain(mesh, foot, 4) -- {pé, canela, coxa, quadril}
			if #chain >= 4 then
				local thigh = chain[3]
				anchor = anchor or chain[4]
				table.insert(bones, thigh)
				for _, descendant in ipairs(animation.getDescendantBones(mesh, thigh, false)) do
					table.insert(bones, descendant)
				end
			end
		end
	end

	if #bones == 0 or anchor == nil then
		log("Não achei os ossos das pernas — a animação das pernas fica desligada", LogLevel.Warning)
		return
	end

	legBones = {}
	for _, name in ipairs(bones) do
		table.insert(legBones, { name = name, fname = uevrUtils.fname_from_string(name) })
	end
	legAnchorFName = uevrUtils.fname_from_string(anchor)

	-- ainda em pose de referência: único momento de ler o quadril "de pé" E a perna
	local hipTransform = mesh:GetBoneTransformByName(legAnchorFName, EBoneSpaces.ComponentSpace)
	if hipTransform ~= nil and hipTransform.Translation ~= nil then
		referenceHip = {
			X = hipTransform.Translation.X,
			Y = hipTransform.Translation.Y,
			Z = hipTransform.Translation.Z,
		}
	end

	-- a malha ainda está na pose de referência aqui: é agora ou nunca
	legRef = {}
	local refBones = { { fname = legAnchorFName } }
	for _, bone in ipairs(legBones) do table.insert(refBones, bone) end
	for _, bone in ipairs(refBones) do
		local t = mesh:GetBoneTransformByName(bone.fname, EBoneSpaces.ComponentSpace)
		if t ~= nil and t.Translation ~= nil and t.Rotation ~= nil and t.Scale3D ~= nil then
			table.insert(legRef, {
				fname = bone.fname,
				x  = t.Translation.X, y  = t.Translation.Y, z  = t.Translation.Z,
				qx = t.Rotation.X,    qy = t.Rotation.Y,
				qz = t.Rotation.Z,    qw = t.Rotation.W,
				sx = t.Scale3D.X,     sy = t.Scale3D.Y,     sz = t.Scale3D.Z,
			})
		end
	end

	logMilestone("Pernas: " .. #legBones .. " ossos, ancoradas em " .. anchor
		.. ", quadril de pe em Z=" .. (referenceHip and string.format("%.1f", referenceHip.Z) or "?"))
end

-- Quais malhas do corpo têm os ossos da perna no esqueleto. Roda uma vez, na
-- criação: dentro do frame é tarde demais. Na dúvida a malha ENTRA — escrever a
-- mais é só desperdício, escrever de menos deixa a perna parada.
local function detectLegMeshes()
	legMeshes, legFrameCount = {}, 0
	if legBones == nil or #legBones == 0 then return end

	local kept, skipped = {}, {}
	for _, mesh in ipairs(bodyMeshes) do
		if uevrUtils.getValid(mesh) ~= nil and mesh.SetBoneTransformByName ~= nil then
			local hasLeg = true
			if mesh.GetBoneIndex ~= nil then
				hasLeg = false
				for _, bone in ipairs(legBones) do
					local ok, index = pcall(function() return mesh:GetBoneIndex(bone.fname) end)
					if ok and index ~= nil and index >= 0 then
						hasLeg = true
						break
					end
				end
			end

			local name = "?"
			pcall(function() name = shortName(mesh) end)
			if hasLeg then
				table.insert(legMeshes, mesh)
				table.insert(kept, name)
			else
				table.insert(skipped, name)
			end
		end
	end

	logMilestone("Pernas: escrevendo em " .. #legMeshes .. " de " .. #bodyMeshes
		.. " malha(s) [" .. table.concat(kept, ", ") .. "]"
		.. (#skipped > 0 and (" — fora: " .. table.concat(skipped, ", ")) or ""))
end

-- Revalida a lista UMA vez por frame. Devolve false quando não sobrou ninguém.
local function refreshLegTargets()
	legFrameCount = 0
	for _, mesh in ipairs(legMeshes) do
		if uevrUtils.getValid(mesh) ~= nil then
			legFrameCount = legFrameCount + 1
			legFrameTargets[legFrameCount] = mesh
		end
	end
	return legFrameCount > 0
end

-- Sem closure e sem getValid: roda por osso e por frame. Ver refreshLegTargets.
local function setLegBone(fname, transform)
	for i = 1, legFrameCount do
		legFrameTargets[i]:SetBoneTransformByName(fname, transform, EBoneSpaces.ComponentSpace)
	end
end

-- Devolve a perna à pose de referência. Roda UMA vez quando a animação é
-- desligada, mesma ideia do writeWaist(0, nil) da cintura.
local function restoreLegReference()
	if legRef == nil or #legRef == 0 then return end
	if not refreshLegTargets() then return end

	for _, bone in ipairs(legRef) do
		setLegBone(bone.fname, kismet_math_library:MakeTransform(
			uevrUtils.vector(bone.x, bone.y, bone.z),
			uevrUtils.rotatorFromQuat(bone.qx, bone.qy, bone.qz, bone.qw),
			uevrUtils.vector(bone.sx, bone.sy, bone.sz)))
	end
	logMilestone("Pernas devolvidas à pose de referencia")
end

-- A malha de origem da cópia principal é quem carrega a animação do jogo.
local function getSourceMesh()
	if currentRig == nil then return nil end
	local reference = bodyMeshes[1]
	if reference == nil then return nil end
	for _, template in pairs(currentRig.meshTemplates or {}) do
		if template.mesh == reference then return template.instance end
	end
	return nil
end

local function copyLegPose(engine, delta)
	-- sem cópia de pernas, zera o hipShift para não empurrar o tronco com valor velho
	-- "Animar as pernas" é sobre o ANDAR. MONTADO a perna do jogo não é animação, é
	-- a pose no estribo (na vassoura, a de sentar): desligar aí devolvia a pose de
	-- referência e o boneco ficava DE PÉ em cima do hipogrifo. Então o interruptor
	-- só vale a pé; montado, a perna continua vindo do jogo.
	local animateOff = configui.getValue("body_animate") == false and mounts.isWalking()
	if not isEnabled() or currentRig == nil or legBones == nil
		or animateOff
		or configui.getValue("body_onlyArms") == true
		or isBodyHidden()
	then
		hipShift.X, hipShift.Y, hipShift.Z = 0, 0, 0
		-- SÓ quando o motivo é "animação desligada". Em somente-braços e com o corpo
		-- escondido a perna está encolhida POR ESCALA, e a transform de referência
		-- traz a escala 1 junto: reescrevê-la faria a perna reaparecer.
		local shouldRestore = legsApplied and animateOff
			and configui.getValue("body_onlyArms") ~= true and not isBodyHidden()
		legsApplied = false
		if shouldRestore then pcall(restoreLegReference) end
		return
	end

	local reference = bodyMeshes[1]
	if uevrUtils.getValid(reference) == nil or reference.SetBoneTransformByName == nil then return end

	local source = getSourceMesh()
	if uevrUtils.getValid(source) == nil or source.GetSocketTransform == nil then return end

	local sourceAnchor = source:GetSocketTransform(legAnchorFName, RTS_COMPONENT)
	local targetAnchor = reference:GetBoneTransformByName(legAnchorFName, EBoneSpaces.ComponentSpace)
	if sourceAnchor == nil or targetAnchor == nil then return end

	-- O quadril é ÂNCORA: só a altura vem da animação, e só em agachamento de
	-- verdade. X, Y e rotação são da pose de referência. Ver LEIAME.
	if standingSourceHipZ == nil and mounts.isWalking() then
		standingSourceHipZ = sourceAnchor.Translation.Z
	end

	-- MONTADO: quadril do jogo (a prudência acima é pelo balanço do andar)
	local mounted = not mounts.isWalking()
	-- Na criatura a perna é a do jogo, crua. A vassoura fica de fora: lá a regra
	-- do perfil é não mexer, e ela nunca foi motivo de reclamação.
	local rawLegs = mounted and not mounts.isOnBroom()

	if mounted or referenceHip ~= nil then
		if rawLegs then
			-- quadril INTEIRO do jogo, rotação inclusive: copiar só a translação
			-- deixava o quadril na pose de referência e o `align` abaixo girava a
			-- perna toda pela diferença — era o que deitava a perna no hipogrifo
			targetAnchor = sourceAnchor
			hipDrop = 0
		elseif mounted then
			targetAnchor.Translation.X = sourceAnchor.Translation.X
			targetAnchor.Translation.Y = sourceAnchor.Translation.Y
			targetAnchor.Translation.Z = sourceAnchor.Translation.Z
			hipDrop = 0
		else
			hipDrop = 0
			if configui.getValue("body_followCrouch") ~= false and standingSourceHipZ ~= nil then
				-- só para baixo, e só o que passar da folga: andar não é agachar
				hipDrop = math.min(0, sourceAnchor.Translation.Z - standingSourceHipZ + HIP_DROP_DEADZONE)
			end

				-- escrito sempre: é assim que o quadril volta a ficar de pé quando se desliga
			targetAnchor.Translation.X = referenceHip.X
			targetAnchor.Translation.Y = referenceHip.Y
			targetAnchor.Translation.Z = referenceHip.Z + hipDrop
		end

		-- guardado para a cintura acompanhar (ver hipShift)
		if referenceHip ~= nil then
			hipShift.X = targetAnchor.Translation.X - referenceHip.X
			hipShift.Y = targetAnchor.Translation.Y - referenceHip.Y
			hipShift.Z = targetAnchor.Translation.Z - referenceHip.Z
		end

		setBoneOnAll(legAnchorFName, targetAnchor)
	end

	-- A pé (e na vassoura), reancoradas no quadril da cópia, que fica na pose de
	-- referência, senão o balanço do andar vem junto e a cintura rasga. Na
	-- criatura, não: a cópia está colada na malha do jogo — mesma transform de
	-- mundo, mesmo esqueleto —, então a perna crua cai exatamente em cima da
	-- perna do jogo, que é onde o pé fica no estribo.
	local align = nil
	if not rawLegs then
		align = kismet_math_library:ComposeTransforms(
			kismet_math_library:InvertTransform(sourceAnchor), targetAnchor)
	end

	-- Ajuste do painel. EIXOS DO COMPONENTE: +Y é a frente, -X é a direita.
	-- Na criatura ele não entra: ali a perna é a do jogo, e empurrá-la tira o pé
	-- do estribo. É calibragem de quem está de pé.
	local lx, ly, lz = vec3Of(configui.getValue("body_legOffset"))
	local hasLegOffset = align ~= nil and (lx ~= 0 or ly ~= 0 or lz ~= 0)

	-- validação fora do laço: era 1 getValid por malha POR OSSO
	if not refreshLegTargets() then return end

	for _, bone in ipairs(legBones) do
		local transform = source:GetSocketTransform(bone.fname, RTS_COMPONENT)
		if transform ~= nil then
			local aligned = transform
			if align ~= nil then
				aligned = kismet_math_library:ComposeTransforms(transform, align)
			end
			if hasLegOffset and aligned.Translation ~= nil then
				aligned.Translation.X = aligned.Translation.X + lx
				aligned.Translation.Y = aligned.Translation.Y + ly
				aligned.Translation.Z = aligned.Translation.Z + lz
			end
			setLegBone(bone.fname, aligned)
		end
	end

	legsApplied = true
end

-- Prioridade 10 = antes do ik.lua (0). Ele só mexe em braço, nós só em perna.
uevrUtils.registerPreEngineTickCallback(function(engine, delta)
	guard("Falha ao animar as pernas", copyLegPose, engine, delta)
end, 10)

-- === 1b. Só montado: ik.lua no personagem, e Z solto ===
-- ik.setPawn troca a referência do rig; coupling = 2 tira o ik.lua do Z, senão a
-- cápsula da criatura joga o alvo do solver para fora do alcance (armadilha 7).
local lastRigPawn = nil

local function updateRigPawn()
	local playerPawn = uevrUtils.getValid(pawn)
	if playerPawn == nil then
		-- sem pawn válido, o getPawn() do ik.lua cai sozinho no pawn global
		if lastRigPawn ~= nil then
			lastRigPawn = nil
			ik.setPawn(nil)
		end
		return
	end

	local rigPawn = uevrUtils.getValid(mounts.getMountPawn(playerPawn)) or playerPawn
	if rigPawn == lastRigPawn then return end
	lastRigPawn = rigPawn

	ik.setPawn(rigPawn)
	if rigPawn ~= playerPawn then
		logMilestone("Montado: ik.lua ancorado no personagem, nao na criatura")
	else
		logMilestone("ik.lua ancorado no pawn controlado")
	end
end

-- valor original do `coupling` do rig (vem de parent_type), guardado na criação
local rigCoupling = nil

-- Somente braços usa o mesmo: sem pernas, a conta da cápsula não descreve nada.
local function updateMountCoupling()
	if currentRig == nil then return end

	local wantFree = configui.getValue("body_onlyArms") == true
		or (not mounts.isWalking()
			and configui.getValue("body_mountArmsIK") ~= false)

	if wantFree then
		if currentRig.coupling ~= 2 then
			currentRig.coupling = 2
			logMilestone("Z do ik.lua liberado, quem posiciona a copia e o body.lua")
		end
	elseif rigCoupling ~= nil and currentRig.coupling ~= rigCoupling then
		currentRig.coupling = rigCoupling
		logMilestone("Z do ik.lua devolvido (coupling " .. tostring(rigCoupling) .. ")")
	end
end

-- Ossos do braço direito, só para os diagnósticos abaixo (sem efeito no jogo).
local diagArmBone, diagHandBone = nil, nil

local function detectDiagArmBones(mesh)
	diagArmBone, diagHandBone = nil, nil
	if uevrUtils.getValid(mesh) == nil then return end
	local names = uevrUtils.getBoneNames(mesh)
	if names == nil or #names == 0 then return end
	local hand = detectHandBone(names, toBoneSet(names), Handed.Right)
	if hand == nil then return end
	local chain = getBoneChain(mesh, hand, 5)
	diagHandBone = uevrUtils.fname_from_string(hand)
	if chain[3] ~= nil then diagArmBone = uevrUtils.fname_from_string(chain[3]) end
end

-- Diagnóstico dos braços, de 2 em 2 s e só montado. Sem efeito no jogo.
local diagTimer = 0

local function logArmDiagnostics(delta)
	if mounts.isWalking() then diagTimer = 0 return end
	if currentRig == nil or #bodyMeshes == 0 then return end
	diagTimer = diagTimer + (delta or 0)
	if diagTimer < 2.0 then return end
	diagTimer = 0

	local mesh = bodyMeshes[1]
	if uevrUtils.getValid(mesh) == nil or mesh.GetBoneLocationByName == nil then return end

	local animLeft = uevrUtils.executeUEVRCallbacksWithPriorityBooleanResult(
		"is_hands_animating_from_mesh", Handed.Left)
	local animRight = uevrUtils.executeUEVRCallbacksWithPriorityBooleanResult(
		"is_hands_animating_from_mesh", Handed.Right)

	local shoulder = diagArmBone ~= nil and mesh:GetBoneLocationByName(diagArmBone, EBoneSpaces.WorldSpace) or nil
	local hand = diagHandBone ~= nil and mesh:GetBoneLocationByName(diagHandBone, EBoneSpaces.WorldSpace) or nil
	local controller = controllers.getController(1)
	local controllerLoc = uevrUtils.getValid(controller) ~= nil and controller:K2_GetComponentLocation() or nil

	local reach = "?"
	if shoulder ~= nil and controllerLoc ~= nil then
		reach = string.format("%.0f", kismet_math_library:Vector_Distance(shoulder, controllerLoc))
	end
	local erro = "?"
	if hand ~= nil and controllerLoc ~= nil then
		erro = string.format("%.0f", kismet_math_library:Vector_Distance(hand, controllerLoc))
	end

	local solvers = 0
	for _ in pairs(currentRig.activeSolvers or {}) do solvers = solvers + 1 end

	logMilestone("[bracos] solvers=" .. solvers
		.. ", animando pela malha: esq=" .. tostring(animLeft) .. " dir=" .. tostring(animRight)
		.. ", ombro=" .. fmt(shoulder) .. ", mao=" .. fmt(hand)
		.. ", controle=" .. fmt(controllerLoc)
		.. ", ombro->controle=" .. reach .. "cm, mao->controle=" .. erro .. "cm")
end

local lastLoggedMountType = nil

local function logMountStateChange()
	local mountType = mounts.getMountType()
	if mountType == lastLoggedMountType then return end
	lastLoggedMountType = mountType

	local function nameOf(obj)
		if uevrUtils.getValid(obj) == nil or obj.get_full_name == nil then return "nil" end
		local full = obj:get_full_name()
		return full:sub(-60)
	end

	-- o tipo sai primeiro: se uma leitura estourar, a transição não se perde
	logMilestone("--- montaria mudou: tipo=" .. tostring(mountType)
		.. ", voando=" .. tostring(mounts.getIsFlying()) .. " ---")

	local playerPawn = uevrUtils.getValid(pawn)
	local rider = playerPawn ~= nil and uevrUtils.getValid(mounts.getMountPawn(playerPawn)) or nil
	local source = getSourceMesh()
	local mesh = bodyMeshes[1]
	local hmd = controllers.getController(2)
	local root = uevrUtils.getValid(playerPawn, {"RootComponent"})
	logMilestone("  pawn=" .. nameOf(playerPawn) .. ", personagem=" .. nameOf(rider))
	logMilestone("  capsula=" .. tostring(root ~= nil and root.CapsuleHalfHeight or "nil")
		.. ", root=" .. fmt(root ~= nil and root:K2_GetComponentLocation() or nil))
	logMilestone("  malha do jogo=" .. nameOf(source) .. " em "
		.. fmt(uevrUtils.getValid(source) ~= nil and source:K2_GetComponentLocation() or nil))
	logMilestone("  copia=" .. fmt(uevrUtils.getValid(mesh) ~= nil and mesh:K2_GetComponentLocation() or nil)
		.. ", cabeca=" .. fmt(uevrUtils.getValid(mesh) ~= nil and mesh.GetSocketLocation ~= nil
			and mesh:GetSocketLocation(uevrUtils.fname_from_string(headBone)) or nil)
		.. ", HMD=" .. fmt(uevrUtils.getValid(hmd) ~= nil and hmd:K2_GetComponentLocation() or nil))
end

uevrUtils.registerPreEngineTickCallback(function(engine, delta)
	-- antes do coupling: quem for refazer o rig neste frame já pega o pawn certo
	guard("Falha ao apontar o pawn do rig", updateRigPawn)
	guard("Falha ao ajustar o coupling na montaria", updateMountCoupling)
	guard("Falha ao registrar a mudanca de montaria", logMountStateChange)
	guard("Falha no diagnostico dos bracos", logArmDiagnostics, delta)
end, 20)

-- === 1c. Só montado (criatura): postura do tronco ===
-- Gira a CINTURA (no quadril as pernas sairiam do estribo) atrás do headset, e
-- aplica o "endireitar a coluna". Prioridade 5: depois das pernas, antes do IK.

local waistFName    = nil   -- primeiro osso da coluna (filho do quadril)
local waistRef      = nil   -- pose de referência dele, em números
local waistYawState = 0     -- torção já aplicada (suavizada)
local waistApplied  = false -- há uma torção escrita no osso agora?
local waistWarned   = false

local WAIST_LERP = 8.0

-- O endireitar não é suavizado: já é função direta da rotação da criatura.

local function detectWaistBone(mesh)
	waistFName, waistRef, waistYawState, waistApplied = nil, nil, 0, false
	if uevrUtils.getValid(mesh) == nil or legAnchorFName == nil then return end
	if mesh.GetParentBone == nil or mesh.GetBoneTransformByName == nil then return end

	local names = uevrUtils.getBoneNames(mesh)
	if names == nil or #names == 0 then return end

	-- filho do quadril que não é perna; vence o nome mais curto (Spine)
	local isLeg = {}
	for _, bone in ipairs(legBones or {}) do isLeg[string.lower(bone.name)] = true end

	local hipName = legAnchorFName:to_string()
	local best = nil
	for _, name in ipairs(names) do
		if not isLeg[string.lower(name)] then
			local parent = mesh:GetParentBone(uevrUtils.fname_from_string(name))
			if parent ~= nil and parent:to_string() == hipName then
				if best == nil or #name < #best then best = name end
			end
		end
	end

	if best == nil then
		log("Não achei o osso da cintura — o tronco não vai acompanhar a visão na montaria", LogLevel.Warning)
		return
	end

	local fname = uevrUtils.fname_from_string(best)
	-- ainda em pose de referência: único momento de ler a cintura neutra
	local transform = mesh:GetBoneTransformByName(fname, EBoneSpaces.ComponentSpace)
	local q = transform ~= nil and transform.Rotation or nil
	if transform == nil or transform.Translation == nil or q == nil or q.W == nil then
		log("Não consegui ler a pose da cintura ('" .. best .. "')", LogLevel.Warning)
		return
	end

	local rot = uevrUtils.rotatorFromQuat(q.X, q.Y, q.Z, q.W)
	local scale = transform.Scale3D
	waistFName = fname
	-- guardado em NÚMEROS: struct do motor devolvida por Get... é reaproveitada
	waistRef = {
		lx = transform.Translation.X, ly = transform.Translation.Y, lz = transform.Translation.Z,
		pitch = rot.Pitch, yaw = rot.Yaw, roll = rot.Roll,
		sx = scale ~= nil and scale.X or 1, sy = scale ~= nil and scale.Y or 1,
		sz = scale ~= nil and scale.Z or 1,
	}

	logMilestone("Cintura: '" .. best .. "' (acima de '" .. hipName .. "')")
end

-- ComposeRotators em números: a struct devolvida pelo motor é reaproveitada, e
-- guardar uma delas para usar dois passos depois já custou caro aqui.
local function composeRot(p1, y1, r1, p2, y2, r2)
	local out = kismet_math_library:ComposeRotators(
		uevrUtils.rotator(p1, y1, r1), uevrUtils.rotator(p2, y2, r2))
	if out == nil then return p1, y1, r1 end
	return out.Pitch, out.Yaw, out.Roll
end

-- Rotação que tira da coluna a inclinação da malha do jogo; nil se não há o que fazer.
local function computeSpineCorrection()
	-- A vassoura tem controles próprios: o mesmo par endireitar + lateral do
	-- hipogrifo, sem o ajuste fino em graus. A lateral é escalada pelo MESMO
	-- `amount`, então com a coluna em 0 marcar o checkbox não faz nada.
	local amount, trim, withRoll
	if mounts.isOnBroom() then
		amount   = configui.getValue("body_broomSpineUpright") or 0
		trim     = 0
		withRoll = configui.getValue("body_broomSpineRoll") == true
	else
		amount   = configui.getValue("body_mountSpineUpright") or 0
		trim     = configui.getValue("body_mountSpineTrim") or 0
		withRoll = configui.getValue("body_mountSpineRoll") ~= false
	end
	if amount <= 0 and trim == 0 then return nil end

	local source = getSourceMesh()
	if uevrUtils.getValid(source) == nil or source.K2_GetComponentRotation == nil then return nil end
	local srcRot = source:K2_GetComponentRotation()
	if srcRot == nil then return nil end

	amount = math.max(0, math.min(1, amount))

	-- Endireitar é reduzir a inclinação DO PERSONAGEM, e os canais do rotator da
	-- malha não são os dele: o "Mesh Rotation Offset" do rig está em Yaw -90, e
	-- com isso o pitch da malha é a inclinação LATERAL e o roll é a da FRENTE.
	-- Mexer direto no pitch, como era antes, endireitava o lado e deixava o
	-- personagem deitado para a frente (armadilha 11). Então: tira o giro do
	-- mundo, leva a sobra para os eixos do personagem, escala lá, e volta.
	local meshYaw = rigMeshYaw()
	local lp, ly, lr = composeRot(srcRot.Pitch, srcRot.Yaw, srcRot.Roll, 0, -srcRot.Yaw, 0)
	lp, ly, lr = composeRot(0, -meshYaw, 0, lp, ly, lr)
	lp, ly, lr = composeRot(lp, ly, lr, 0, meshYaw, 0)

	-- aqui pitch é a inclinação para a frente e roll é a lateral, sempre
	lp = lp * (1 - amount)
	if withRoll then lr = lr * (1 - amount) end

	lp, ly, lr = composeRot(0, meshYaw, 0, lp, ly, lr)
	lp, ly, lr = composeRot(lp, ly, lr, 0, -meshYaw, 0)
	-- devolve o giro do mundo: com amount 0 isto reconstrói srcRot exatamente
	local tp, ty, tr = composeRot(lp, ly, lr, 0, srcRot.Yaw, 0)
	local target = uevrUtils.rotator(tp, ty, tr)

	-- Ajuste fino: desgira, inclina no plano do personagem, gira de volta.
	if trim ~= 0 then
		local facingYaw = srcRot.Yaw - rigMeshYaw()
		-- desgira -> inclina em pitch (agora o pitch é o do personagem) -> gira de volta
		local lean = kismet_math_library:ComposeRotators(
			kismet_math_library:ComposeRotators(
				uevrUtils.rotator(0, -facingYaw, 0),
				uevrUtils.rotator(trim, 0, 0)),
			uevrUtils.rotator(0, facingYaw, 0))
		target = kismet_math_library:ComposeRotators(target, lean)
	end

	-- Transform, não rotator: o inverso de um rotator não é o rotator negado.
	local one  = uevrUtils.vector(1, 1, 1)
	local zero = uevrUtils.vector(0, 0, 0)
	return kismet_math_library:ComposeTransforms(
		kismet_math_library:MakeTransform(zero, target, one),
		kismet_math_library:InvertTransform(
			kismet_math_library:MakeTransform(zero, uevrUtils.rotator(srcRot.Pitch, srcRot.Yaw, srcRot.Roll), one)))
end

-- Escreve a cintura. A CABEÇA NÃO ENTRA aqui (esticava o pescoço). Ver LEIAME.
local function writeWaist(yaw, correction)
	local rotation = uevrUtils.rotator(waistRef.pitch, waistRef.yaw, waistRef.roll)
	if yaw ~= 0 then
		rotation = kismet_math_library:ComposeRotators(rotation, uevrUtils.rotator(0, yaw, 0))
	end

	-- referência + hipShift: em espaço de componente a escrita é absoluta.
	local lx = waistRef.lx + hipShift.X
	local ly = waistRef.ly + hipShift.Y
	local lz = waistRef.lz + hipShift.Z

	local transform = kismet_math_library:MakeTransform(
		uevrUtils.vector(lx, ly, lz),
		rotation,
		uevrUtils.vector(waistRef.sx, waistRef.sy, waistRef.sz))

	if correction ~= nil then
		-- a correção entra depois da rotação do osso: giro puro, sem deslocar nada
		local rotated = kismet_math_library:ComposeTransforms(
			kismet_math_library:MakeTransform(uevrUtils.vector(0, 0, 0), rotation, uevrUtils.vector(1, 1, 1)),
			correction)
		local q = rotated ~= nil and rotated.Rotation or nil
		if q ~= nil and q.W ~= nil then
			transform = kismet_math_library:MakeTransform(
				uevrUtils.vector(lx, ly, lz),
				uevrUtils.rotatorFromQuat(q.X, q.Y, q.Z, q.W),
				uevrUtils.vector(waistRef.sx, waistRef.sy, waistRef.sz))
		end
	end

	setBoneOnAll(waistFName, transform)
end

-- Condições comuns ao giro e ao endireitar; qual age é decidido no tick.
local function waistControlActive()
	if waistFName == nil or waistRef == nil then return false end
	if not isEnabled() or currentRig == nil or #bodyMeshes == 0 then return false end
	if mounts.isWalking() then return false end
	-- Vassoura entra SÓ para endireitar a coluna, e só se o slider pedir. Com ele
	-- em 0 nada é escrito — é a regra antiga de não modificar nada lá.
	if mounts.isOnBroom() and (configui.getValue("body_broomSpineUpright") or 0) <= 0 then
		return false
	end
	if isBodyHidden() then return false end
	return true
end

local function updateWaistFollow(engine, delta)
	local active = waistControlActive()

	local correction = nil
	if active then
		local ok, result = pcall(computeSpineCorrection)
		if ok then correction = result end
	end

	-- girar a cintura atrás do headset é coisa de criatura; na vassoura, só endireitar
	local followYaw = active and not mounts.isOnBroom()
		and configui.getValue("body_mountHipAlign") ~= false

	if not active or (not followYaw and correction == nil) then
		-- devolve a cintura à referência UMA vez, senão o osso guarda a torção
		if waistApplied then
			waistApplied = false
			waistYawState = 0
			local ok = pcall(writeWaist, 0, nil)
			if not ok and not waistWarned then
				waistWarned = true
				logMilestone("Cintura: nao consegui devolver a pose de referencia")
			end
		end
		return
	end

	local target = 0
	if followYaw then
		local hmd = controllers.getController(2)
		local mesh = bodyMeshes[1]
		if uevrUtils.getValid(hmd) == nil or uevrUtils.getValid(mesh) == nil then return end

		local hmdRot = hmd:K2_GetComponentRotation()
		local bodyRot = mesh:K2_GetComponentRotation()
		if hmdRot == nil or bodyRot == nil then return end

		-- montado, a rotação do corpo é a da malha do jogo: a torção é a diferença
		local diff = uevrUtils.clampAngle180(hmdRot.Yaw - bodyRot.Yaw)

		local deadzone = configui.getValue("body_mountHipDeadzone") or 0
		if math.abs(diff) > deadzone then
			local sign = diff >= 0 and 1 or -1
			target = (diff - sign * deadzone) * (configui.getValue("body_mountHipSensitivity") or 0)
			local limit = configui.getValue("body_mountHipMaxYaw") or 60
			target = math.max(-limit, math.min(limit, target))
		end
	end

	if delta ~= nil and delta > 0 then
		waistYawState = waistYawState + (target - waistYawState) * math.min(1, WAIST_LERP * delta)
	else
		waistYawState = target
	end

	waistApplied = true
	writeWaist(waistYawState, correction)
end

uevrUtils.registerPreEngineTickCallback(function(engine, delta)
	guard("Falha ao girar a cintura", updateWaistFollow, engine, delta)
end, 5)

-- === 2. Altura do corpo ===
-- Sobrou só a linha de base do quadril; a altura é toda do ik.lua. As duas
-- correções que moravam aqui (armadilhas 2 e 3) não devem voltar.

local function resetHeightCalibration()
	standingSourceHipZ = nil -- a linha do "em pé" do quadril (seção 1)
end

-- === 3. Câmera atracada à cabeça ===
-- Vai ao osso da cabeça, nos três eixos, a pé e montado; só a POSIÇÃO. Registrada
-- num delay: o callback do main.lua sobrescreveria o nosso. Ver LEIAME.
local function headCameraActive()
	if not isEnabled() or currentRig == nil or #bodyMeshes == 0 then return false end
	if configui.getValue("body_headCamera") ~= true then return false end
	if configui.getValue("body_onlyArms") == true then return false end -- sem corpo, sem cabeça
	if isBodyHidden() then return false end
	-- No mapa e na tela de equipamento o main.lua desliga a camera do VR para o
	-- mapa/avatar desenharem; a nossa segue a mesma decisao (um dono por valor).
	if type(_G.isVRCameraOffsetEnabled) == "function" then
		local ok, allowed = pcall(_G.isVRCameraOffsetEnabled)
		if ok and allowed == false then return false end
	end
	return true
end

local function getHeadWorldLocation()
	local mesh = bodyMeshes[1]
	if uevrUtils.getValid(mesh) == nil or mesh.GetSocketLocation == nil then return nil end
	-- "Esconder a cabeca" encolhe o osso, não o move: a posição continua valendo.
	return mesh:GetSocketLocation(uevrUtils.fname_from_string(headBone))
end

-- === Olhar para baixo leva a vista para a frente ===
-- Move só a câmera. Janela de 120°, e o avanço é na FRENTE DO CORPO, nunca na
-- direção do olhar. Ver LEIAME.

local GAZE_ARC_CORE   = 45 -- até aqui o efeito é cheio
local GAZE_ARC_HALF   = 60 -- daqui para fora, zero (a janela de 120°)
local GAZE_PITCH_DEAD = 10 -- graus de olhar para baixo que ainda não movem nada

-- Yaw contra o corpo, pitch contra o horizonte, tudo por vetor. Ver LEIAME.
local function getGazeInBodySpace()
	local mesh = bodyMeshes[1]
	local hmd = controllers.getController(2)
	if uevrUtils.getValid(mesh) == nil or uevrUtils.getValid(hmd) == nil then return nil end
	if mesh.K2_GetComponentRotation == nil or hmd.K2_GetComponentRotation == nil then return nil end
	if kismet_math_library == nil or kismet_math_library.GetForwardVector == nil
		or kismet_math_library.GetRightVector == nil then return nil end

	local hmdRot  = hmd:K2_GetComponentRotation()
	local bodyRot = mesh:K2_GetComponentRotation()
	if hmdRot == nil or bodyRot == nil then return nil end

	-- copiar para números na hora: o motor reaproveita a mesma struct
	local v = kismet_math_library:GetForwardVector(hmdRot)
	if v == nil then return nil end
	local vx, vy, vz = v.X, v.Y, v.Z

	-- só X e Y: a janela e o avanço são medidos no chão
	local f = kismet_math_library:GetForwardVector(bodyRot)
	if f == nil then return nil end
	local fx, fy = f.X, f.Y

	local r = kismet_math_library:GetRightVector(bodyRot)
	if r == nil then return nil end
	local rx, ry = r.X, r.Y

	-- frente do ESQUELETO: eixos do componente girados por -meshRotationOffset.Yaw
	local a = math.rad(-rigMeshYaw())
	local ca, sa = math.cos(a), math.sin(a)
	local Fx, Fy = (fx * ca) + (rx * sa), (fy * ca) + (ry * sa)

	-- sombra no chão: é o que faz a conta valer reclinado (hipogrifo) ou deitado
	local bodyFlat = math.sqrt((Fx * Fx) + (Fy * Fy))
	local gazeFlat = math.sqrt((vx * vx) + (vy * vy))
	-- reto para cima/baixo: sem sombra para medir, e direção inventada seria pior
	if bodyFlat < 0.0001 or gazeFlat < 0.0001 then return nil end

	local bodyYawNow = math.deg(math.atan(Fy, Fx))
	local gazeYaw    = math.deg(math.atan(vy, vx))

	-- pitch CONTRA O HORIZONTE: é o pescoço de quem joga, não o peito do boneco
	local pitch = math.deg(math.atan(vz, gazeFlat))

	-- avanço horizontal: a frente crua apontaria para o chão ou para o céu
	return gazeYaw - bodyYawNow, pitch, Fx / bodyFlat, Fy / bodyFlat, 0
end

-- Quantos cm a vista avança, e para onde; nil se não há avanço. Sem lerp.
local function gazeLeanPush()
	if configui.getValue("body_gazeLean") == false then return nil end
	-- repetido aqui para o diagnóstico não anunciar um empurrão que não acontece
	if not headCameraActive() then return nil end

	local maximum = configui.getValue("body_gazeLeanMax") or 0
	if maximum <= 0 then return nil end

	local relYaw, relPitch, Fx, Fy, Fz = getGazeInBodySpace()
	if relYaw == nil then return nil end

	-- janela de 120°: cheio até 45°, cosseno até 60°, zero depois
	local away = math.abs(uevrUtils.clampAngle180(relYaw))
	if away >= GAZE_ARC_HALF then return nil end
	local gate = 1
	if away > GAZE_ARC_CORE then
		gate = 0.5 * (1 + math.cos(math.pi * (away - GAZE_ARC_CORE) / (GAZE_ARC_HALF - GAZE_ARC_CORE)))
	end

	-- rampa do pitch: 0 na zona morta, 1 reto para baixo — assim o painel é em cm
	local down = -relPitch - GAZE_PITCH_DEAD
	if down <= 0 then return nil end
	local ramp = down / (90 - GAZE_PITCH_DEAD)
	if ramp > 1 then ramp = 1 end

	return maximum * ramp * gate, Fx, Fy, Fz
end

-- Só para o "Diagnostico no log".
local function gazeLeanDistance()
	local push = gazeLeanPush()
	return push or 0
end

-- tudo lido AQUI dentro: nada vem guardado do tick (armadilha 5)
local function applyHeadCamera(position, rotation)
	if not headCameraActive() then return end

	-- osso da CÓPIA: a câmera pega a cabeça que você vê
	local head = getHeadWorldLocation()
	if head == nil then return end

	local x, y, z = head.X, head.Y, head.Z

	-- olhar para baixo empurra a vista para a frente (bloco acima)
	local push, fx, fy, fz = gazeLeanPush()
	if push ~= nil then
		x, y, z = x + (fx * push), y + (fy * push), z + (fz * push)
	end

	-- Altura dos olhos. Só altura: o X/Y girava pelo olhar e andava em círculo.
	z = z + (configui.getValue("body_headCameraHeight") or 0)

	position.x = x
	position.y = y
	position.z = z
end

local headCameraRegistered = false

local function registerHeadCamera()
	if headCameraRegistered then return end
	headCameraRegistered = true

	uevr.params.sdk.callbacks.on_early_calculate_stereo_view_offset(
		function(device, view_index, world_to_meters, position, rotation, is_double)
			-- protegido: roda no caminho da câmera, uma vez por olho
			guard("Falha na camera da cabeca", applyHeadCamera, position, rotation)
		end)

	logMilestone("Camera atracada a cabeca: callback registrado")
end

-- === 4. Posição e giro do corpo ===
-- O corpo é filho do RootComponent e a câmera do perfil ORBITA o pawn, então o
-- X/Y é refeito todo frame. O Z é do ik.lua (o valor de "Posicao").

-- Yaw do corpo: variável NOSSA, nunca lida de volta do componente (armadilha 4).
local bodyYawState = nil

local function updateBodyTransform(engine, delta)
	if not isEnabled() or currentRig == nil or #bodyMeshes == 0 then return end
	if isBodyHidden() then return end

	local followView = configui.getValue("body_followView") ~= false
	-- SOMENTE BRAÇOS: sem tronco, a posição inteira sai do HMD (aqui não é realimentação).
	local onlyArms = configui.getValue("body_onlyArms") == true

	local rootComponent = uevrUtils.getValid(pawn, {"RootComponent"})
	if rootComponent == nil then return end
	-- montado o pawn é a criatura, mas o corpo pende do RootComponent do personagem
	if onlyArms and not mounts.isWalking() then
		local rigRoot = uevrUtils.getValid(mounts.getMountPawn(pawn), {"RootComponent"})
		if rigRoot ~= nil then rootComponent = rigRoot end
	end
	local mesh = bodyMeshes[1]
	if uevrUtils.getValid(mesh) == nil then return end

	-- MONTARIA: o corpo copia a malha do jogo, em MUNDO — a conta normal pressupõe
	-- alguém em pé. "Somente bracos" não entra.
	if not mounts.isWalking() and not onlyArms then
		local source = getSourceMesh()
		if uevrUtils.getValid(source) ~= nil and source.K2_GetComponentLocation ~= nil then
			local srcLoc = source:K2_GetComponentLocation()
			local srcRot = source:K2_GetComponentRotation()
			if srcLoc ~= nil and srcRot ~= nil then
				-- cruas: cópia e malha têm o mesmo esqueleto e a mesma origem
				local location = uevrUtils.vector(srcLoc.X, srcLoc.Y, srcLoc.Z, true)
				local rotation = uevrUtils.rotator(srcRot.Pitch, srcRot.Yaw, srcRot.Roll)
				forEachMesh("K2_SetWorldLocation", function(component)
					component:K2_SetWorldLocation(location, false, reusable_hit_result, false)
					component:K2_SetWorldRotation(rotation, false, reusable_hit_result, false)
				end)

				-- o yaw livre perde o sentido montado; recomeça do pawn ao desmontar
				bodyYawState = nil
				return
			end
		end
	end

	local hmd = controllers.getController(2)
	local pawnYaw = rootComponent:K2_GetComponentRotation().Yaw
	-- offset da rotação da malha, não da direção do olhar: entra e sai da conta
	local meshYawOffset = rigMeshYaw()

	-- 1) para onde o corpo olha
	local newYaw = pawnYaw
	if followView then
		if bodyYawState == nil then bodyYawState = pawnYaw end
		newYaw = bodyYawState
		if uevrUtils.getValid(hmd) ~= nil and delta ~= nil and delta > 0 then
			newYaw = bodyYaw.update(newYaw, hmd:K2_GetComponentRotation().Yaw, delta) or newYaw
		end
		bodyYawState = newYaw
	else
		-- desligado: o corpo volta a girar com o pawn, e recomeça de onde ele estiver
		bodyYawState = nil
	end

	-- 2) SOMENTE BRAÇOS: pendurados no HMD, em MUNDO, e acabou.
	-- Antes isto era RelativeLocation medida contra o RootComponent, e aí a
	-- altura dos braços virava (HMD.Z - root.Z): a origem da cápsula muda de
	-- lugar a pé, na vassoura e no hipogrifo (e montado o root nem é o mesmo
	-- componente em que a cópia está presa), então os braços apareciam em três
	-- posições diferentes. Sem tronco não existe motivo para passar pela cápsula:
	-- em mundo, o resultado é o mesmo nos três casos.
	if onlyArms then
		local hmdLoc = uevrUtils.getValid(hmd) ~= nil and hmd:K2_GetComponentLocation() or nil
		if hmdLoc == nil then return end

		-- o ajuste do painel gira com o CORPO (aqui já estamos em mundo)
		local ox, oy = 0, 0
		local offset = currentRig.meshLocationOffset
		if offset ~= nil then
			local rotated = kismet_math_library:RotateAngleAxis(
				uevrUtils.vector(offset.X, offset.Y, 0), newYaw, uevrUtils.vector(0, 0, 1))
			ox, oy = rotated.X, rotated.Y
		end

		local location = uevrUtils.vector(hmdLoc.X + ox, hmdLoc.Y + oy,
			hmdLoc.Z + (tonumber(configui.getValue("body_armsHeight")) or 0), true)
		local rotation = uevrUtils.rotator(0, newYaw + meshYawOffset, 0)
		forEachMesh("K2_SetWorldLocation", function(component)
			component:K2_SetWorldLocation(location, false, reusable_hit_result, false)
			component:K2_SetWorldRotation(rotation, false, reusable_hit_result, false)
		end)
		return
	end

	-- 3) corpo inteiro, horizontal: base + o ajuste do painel, no espaço do CORPO
	local x, y = 0, 0
	local offset = currentRig.meshLocationOffset
	if offset ~= nil then
		local rotated = kismet_math_library:RotateAngleAxis(
			uevrUtils.vector(offset.X, offset.Y, 0), newYaw - pawnYaw, uevrUtils.vector(0, 0, 1))
		x, y = rotated.X, rotated.Y
	end

	-- 4) altura: é do ik.lua; lemos e devolvemos igual
	forEachMesh("K2_SetRelativeLocation", function(component)
		local z = component.RelativeLocation ~= nil and component.RelativeLocation.Z or 0
		component:K2_SetRelativeLocation(
			uevrUtils.vector(x, y, z, true), false, reusable_hit_result, false)
	end)

	if followView then
		local rotation = uevrUtils.rotator(0, newYaw + meshYawOffset, 0)
		forEachMesh("K2_SetWorldRotation", function(component)
			component:K2_SetWorldRotation(rotation, false, reusable_hit_result, false)
		end)
	end
end

-- === Somente braços: repor o corpo escondido ===
-- Esconder é ESCALA de osso (armadilha 10), e o ik.lua a desfaz ao copiar pose.
local reapplyCount = 0
local wasAnimatingLast = false

local function reapplyHiddenBodyScales()
	if currentRig == nil or #bodyMeshes == 0 then return end
	if configui.getValue("body_onlyArms") ~= true then
		wasAnimatingLast = false
		return
	end

	local animating = currentRig.wasAnimating == true
	-- nada aconteceu neste frame nem no anterior
	if not animating and not wasAnimatingLast then return end
	wasAnimatingLast = animating

	if currentRig.updateBonesVisibility == nil then return end
	currentRig:updateBonesVisibility()
	-- a cabeça é escondida do mesmo jeito (escala do osso), então cai junto
	applyHeadVisibility()

	reapplyCount = reapplyCount + 1
	-- só nas primeiras vezes: um pisca a 90 Hz encheria o log.txt
	if reapplyCount <= 5 then
		logMilestone("Somente bracos: pose do jogo copiada, corpo escondido reposto (" .. reapplyCount .. ")")
	end
end

-- Prioridade -10 = depois do ik.lua. No pré-tick: no pós-tick o corpo pisca.
uevrUtils.registerPreEngineTickCallback(function(engine, delta)
	-- escalas primeiro: os solvers deste frame já usam os ossos certos
	guard("Falha ao repor o corpo escondido", reapplyHiddenBodyScales)
	guard("Falha ao posicionar o corpo", updateBodyTransform, engine, delta)
end, -10)

-- === Criação do rig ===

-- Só desconecta; quem reconecta é o poll do main.lua. pcall: isto vem de timer.
local function rebuildWand()
	if type(_G.disconnectWand) ~= "function" then return end
	local ok, err = pcall(_G.disconnectWand)
	if ok then
		log("Varinha desconectada para reconectar junto com o corpo")
	else
		log("Falha ao reconectar a varinha: " .. tostring(err), LogLevel.Warning)
	end
end

-- === Corpos fantasmas ===
-- Cópia que sobrevive a um destroy congela onde estava ("dois corpos"). Varremos
-- na criação e depois do destroyAll; destroyOwner = false. Ver LEIAME.
-- `mine` marca as de `keep`: o diagnóstico precisa das duas.
local function collectPoseableCopies(keep)
	local found = {}

	local rootComponent = uevrUtils.getValid(pawn, {"RootComponent"})
	if rootComponent == nil then return found end

	local poseableClass = uevrUtils.get_class("Class /Script/Engine.PoseableMeshComponent")
	if poseableClass == nil then return found end

	local isMine = {}
	for _, mesh in ipairs(keep or {}) do isMine[mesh] = true end

	local function collect(component, depth)
		if depth > 4 then return end
		local children = component.AttachChildren
		if children == nil then return end
		for i = 1, #children do
			local child = children[i]
			if uevrUtils.getValid(child) ~= nil then
				if child.is_a ~= nil and child:is_a(poseableClass) then
					table.insert(found, { component = child, mine = isMine[child] == true })
				end
				collect(child, depth + 1)
			end
		end
	end
	collect(rootComponent, 0)

	return found
end

local function destroyGhostBodies(keep)
	-- corpo desligado: o perfil volta às mãos antigas, que também são PoseableMesh
	if not isEnabled() then return end

	local ghosts = {}
	for _, entry in ipairs(collectPoseableCopies(keep)) do
		if not entry.mine then table.insert(ghosts, entry.component) end
	end

	if #ghosts == 0 then return end
	for _, ghost in ipairs(ghosts) do
		pcall(uevrUtils.destroyComponent, ghost, false, true)
	end
	logMilestone("Corpos fantasmas removidos: " .. #ghosts)
end

local function rebuild()
	-- TODO caminho de reconstrução passa por aqui: sem este log não dá para saber se
	-- foi o perfil, um gesto ou um reset de scripts (que reimprime o cabeçalho todo).
	logMilestone("Refazendo o corpo")
	ik.destroyAll()
	-- o que sobrou de PoseableMesh no pawn agora é fantasma
	pcall(destroyGhostBodies)
	currentRig = nil
	bodyMeshes = {}
	bodyYawState = nil
	resetHeightCalibration()
	rebuildWand()
end

-- O wand.lua chama isto depois de recriar a varinha (connectAltWand): as mãos do
-- corpo ficam presas na varinha velha e só voltam ao lugar refazendo o corpo.
_G.rebuildVRBody = rebuild

-- Aplica e grava em ik_parameters.json. Sem fila: hide_body não pode esperar.
local function setRigParam(key, value)
	if currentRig ~= nil then
		currentRig:setConfigParameter(key, value, true)
	end
end

ik.registerOnMeshCreatedCallback(function(meshList, rig)
	currentRig = rig
	bodyMeshes = meshList or {}
	if #bodyMeshes == 0 then
		log("Nenhuma malha foi criada para o corpo", LogLevel.Warning)
		return
	end

	-- único ponto por onde passam TODOS os caminhos de criação
	pcall(destroyGhostBodies, bodyMeshes)

	-- Confere os ossos contra a malha. MONTADO NÃO: gravaria os da criatura.
	if not mounts.isWalking() then
		rig.bodyBonesChecked = true
	end
	if configui.getValue("body_autoDetectBones") ~= false and not rig.bodyBonesChecked then
		rig.bodyBonesChecked = true
		if detectBones(rig, false) then
			log("Ossos corrigidos — reconstruindo o corpo")
			uevrUtils.delay(200, rebuild) -- fora do callback de criação
			return
		end
	end

	applyShadowSetting()
	disableBodyCollision()
	applyHeadVisibility()
	keepSourceMeshesAnimating(rig)
	detectLegBones(bodyMeshes[1])
	detectLegMeshes()
	-- o valor de fábrica do Z automático, para devolver ao desmontar (seção 1b)
	rigCoupling = rig.coupling or 1
	-- depois das pernas: a cintura é achada excluindo os ossos delas (seção 1c)
	detectWaistBone(bodyMeshes[1])
	detectDiagArmBones(bodyMeshes[1])

	-- reaproveita as poses de dedo do perfil nas mãos do corpo
	rig:setAnimationsFromHandsParametersFile(buildAnimationTable())
	rig:initHandAnimations(rig.meshTemplates)
	-- as animações de mão nasceram de novo: a pose da varinha tem de ser reposta
	wandGripPending = 3

	-- nasceu completo: o teto de tentativas do rebuildWhenCharacterLoads volta a zero
	if (builtChildCount or 0) > 0 then readyRebuilds = 0 end

	logMilestone("Corpo criado com " .. #bodyMeshes .. " malha(s)")

	-- cobre também os caminhos que não passam pelo botão "Reconstruir corpo"
	rebuildWand()
end)

ik.registerOnDestroyCallback(function()
	currentRig = nil
	bodyMeshes = {}
	legMeshes, legFrameCount = {}, 0
end)

-- === Mãos antigas x mãos do corpo: as duas usam os mesmos IDs de animação ===

-- Mexe direto no _G.showHands e nas malhas; setValue dispararia o onUpdate do main.
local function enforceHandsOff()
	if not isEnabled() then return end
	if configui.getValue("body_replaceHands") == false then return end

	if _G.showHands ~= false then
		_G.showHands = false
		log("'Show Hands' desligado — as mãos agora vêm do corpo")
	end

	if hands.exists() then
		log("Destruindo as mãos antigas presas aos controles")
		hands.destroyHands()
		hands.reset()
	end
end

-- Quando o corpo é desligado, devolve as mãos do perfil.
local function restoreHands()
	if _G.showHands == false then
		log("Religando 'Show Hands'")
		_G.showHands = true
	end
end

-- === Materiais: a cópia herda o que a malha do jogo tinha NA HORA da criação ===
-- `uevr_utils:3543` copia os materiais uma única vez, ao criar a cópia. Reconstruir
-- o corpo durante a invisibilidade congelava o material transparente na cópia, e
-- ela ficava transparente para sempre. Re-copiar de tempos em tempos faz a cópia
-- SEGUIR a malha do jogo: some junto no feitiço e volta junto quando ele acaba.
-- copyMaterials é só GetMaterials + SetMaterial, sem instanciar nada: repetir não vaza.
local function syncBodyMaterials()
	if currentRig == nil or #bodyMeshes == 0 then return end
	for _, template in pairs(currentRig.meshTemplates or {}) do
		local source = uevrUtils.getValid(template.instance)
		local copy   = uevrUtils.getValid(template.mesh)
		if source ~= nil and copy ~= nil
			and source.GetMaterials ~= nil and copy.SetMaterial ~= nil then
			uevrUtils.copyMaterials(source, copy)
		end
	end
end

-- === A malha do jogo fica escondida enquanto o corpo VR está em cena ===
-- SÓ no modo acima: o jogo reexibe a malha do personagem durante a cena e, sem o
-- `checkCinematic()`, ninguém a reesconde — sobrava o personagem do jogo, com
-- cabeça, por cima do corpo VR. Quem esconde continua sendo o `hidePlayer` do
-- main (um dono por valor), com force = true para passar pela guarda dele.
local hiddenAgainCount = 0

local function keepGameMeshHidden()
	if not isEnabled() or not isFPCinematic() then return end
	if configui.getValue("isFP") == false then return end -- terceira pessoa: é para aparecer
	if isBodyHidden() then return end
	if type(_G.hidePlayer) ~= "function" then return end

	local source = getSourceMesh()
	if uevrUtils.getValid(source) == nil or source.bVisible ~= true then return end

	pcall(_G.hidePlayer, true, true)

	hiddenAgainCount = hiddenAgainCount + 1
	-- só as primeiras: numa cena que reexibe por frame isto encheria o log.txt
	if hiddenAgainCount <= 5 then
		logMilestone("Malha do jogo estava visível com o corpo VR em cena: escondida ("
			.. hiddenAgainCount .. ")")
	end
end

uevrUtils.setInterval(2000, function()
	guard("Falha ao desligar as maos", enforceHandsOff)
	guard("Falha ao sincronizar os materiais do corpo", syncBodyMaterials)
end)

-- === Refazer o corpo ao trocar de roupa ===
-- Tela de equipamento = UIManager com o Guia de Campo na aba 1; refaz nas duas
-- bordas (a que resolve é a de saída, com a roupa nova pronta). Ver LEIAME.
local uiManagerCache = nil
local lastInGearScreen = false

local function isInGearScreen()
	if uevrUtils.getValid(uiManagerCache) == nil then
		uiManagerCache = uevrUtils.find_first_of("Class /Script/Phoenix.UIManager")
	end
	local uiManager = uevrUtils.getValid(uiManagerCache)
	if uiManager == nil then return false end
	if uiManager.GetIsUIShown == nil or uiManager:GetIsUIShown() ~= true then return false end

	local widget = uevrUtils.getValid(uiManager.FieldGuideWidget)
	if widget == nil then return false end
	return widget.CurrentTabIndex == 1
end

local function rebuildOnGearScreen()
	local inGear = isInGearScreen()
	if inGear == lastInGearScreen then return end
	lastInGearScreen = inGear

	-- corpo desligado ou ainda não criado: não há o que refazer
	if not isEnabled() or currentRig == nil then return end

	logMilestone(inGear and "Equipamento aberto: refazendo o corpo"
		or "Equipamento fechado: refazendo o corpo com a roupa nova")
	rebuild()
end

-- === Mão fechada empunhando a varinha ===
-- A pose `grip_<mão>_weapon` do hand_animations só é aplicada pelo
-- `hands_animation.updateAnimationState`, e quem dispara isso é o
-- `setHoldingAttachment` — que o main.lua NUNCA chama: ele só passa o booleano
-- para o `handleInput`, que cuida dos DEDOS por frame, não da pose de base.
-- Espelhar aqui o estado da varinha é o que fecha a mão nela.
-- SÓ na mudança: setHoldingAttachment refaz a pose inteira, e chamar a cada poll
-- brigaria com a animação do gatilho.
-- Mesmo sinal que o main.lua passa para o handleInput (`wand.isVisible()`), senão
-- a pose de base e os dedos discordariam.
local lastWandHeld = false

local function updateWandGrip()
	local active = isEnabled() and configui.getValue("body_replaceHands") ~= false
	local held = active and wandHelper.isVisible() == true

	local force = wandGripPending > 0
	if force then wandGripPending = wandGripPending - 1 end

	if held == lastWandHeld and not force then return end
	local changed = held ~= lastWandHeld
	lastWandHeld = held

	local leftHanded = false
	if type(_G.getIsLeftHanded) == "function" then
		local ok, value = pcall(_G.getIsLeftHanded)
		if ok then leftHanded = value == true end
	end

	-- só o lado direito tem `right_grip_weapon` no hand_animations; para canhoto a
	-- pose `grip_left_weapon` aponta para posições que não existem no arquivo.
	local hand = leftHanded and Handed.Left or Handed.Right
	hands.setHoldingAttachment(hand, held)
	if changed then
		logMilestone("Varinha " .. (held and "empunhada: mao fechada" or "guardada: mao aberta"))
	end
end

-- === Refazer o corpo ao DESMONTAR de uma criatura ===
-- SÓ nessa borda. Refazer AO MONTAR fazia o corpo NASCER FORA DO HIPOGRIFO: a
-- cópia é criada a partir do RiderCharacter e posicionada antes de a montaria
-- assentar, e aparece ao lado do bicho. Montado, quem cuida do corpo é o tick
-- (coupling, cintura, perna crua) — não o rebuild.
-- Vassoura fica de fora: lá a regra do perfil é não mexer.
-- getMountType é variável em cache do mounts.lua: ler aqui não custa nada.
-- Debounce porque a transição passa por tipos intermediários.
local lastMountType    = nil
local pendingMountType = nil
local pendingMountTicks = 0
local MOUNT_SETTLE_TICKS = 2  -- 2 x 200ms de estabilidade antes de refazer

-- 2..5 = criatura (mesma faixa do mounts.getMountPawn); 0 = vassoura, 6 = a pé
local function isCreatureMount(mountType)
	return mountType ~= nil and mountType >= 2 and mountType <= 5
end

-- === Refazer o corpo ao terminar o diálogo (pedido do Renan) ===
-- Sair de uma cena deixa o corpo em estado estranho e refazer resolve. Borda
-- cinemática -> jogo, com o mesmo debounce do `rebuildOnDismount`, porque o
-- `InCinematic` oscila (a mesma razão do `hideStreak`). MONTADO NÃO: refazer em
-- cima de uma criatura faz o corpo nascer fora dela (ver LEIAME).
local lastCinematic     = nil
local pendingCinematic  = nil
local pendingCinematicTicks = 0

local function rebuildOnCinematicEnd()
	local playerPawn = uevrUtils.getValid(pawn)
	if playerPawn == nil then return end
	local inCinematic = playerPawn.InCinematic == true

	if inCinematic ~= pendingCinematic then
		pendingCinematic = inCinematic
		pendingCinematicTicks = 0
		return
	end
	if pendingCinematicTicks < MOUNT_SETTLE_TICKS then
		pendingCinematicTicks = pendingCinematicTicks + 1
		return
	end

	if inCinematic == lastCinematic then return end
	local previous = lastCinematic
	lastCinematic = inCinematic

	if previous == nil then return end -- primeira leitura da sessão: só registra
	if not (previous == true and inCinematic == false) then return end -- só a saída
	if not isEnabled() or currentRig == nil then return end
	if not mounts.isWalking() then return end

	logMilestone("Dialogo terminou: refazendo o corpo")
	rebuild()
end

local function rebuildOnDismount()
	local mountType = mounts.getMountType()

	-- ainda mudando: reinicia a contagem
	if mountType ~= pendingMountType then
		pendingMountType  = mountType
		pendingMountTicks = 0
		return
	end
	if pendingMountTicks < MOUNT_SETTLE_TICKS then
		pendingMountTicks = pendingMountTicks + 1
		return
	end

	if mountType == lastMountType then return end
	local previous = lastMountType
	lastMountType = mountType

	-- primeira leitura da sessão: só registra o estado
	if previous == nil then return end
	-- a única borda que refaz: criatura -> a pé
	if not (isCreatureMount(previous) and mounts.isWalking()) then return end
	if not isEnabled() or currentRig == nil then return end

	logMilestone("Desmontou da criatura (" .. tostring(previous) .. " -> "
		.. tostring(mountType) .. "): refazendo o corpo")
	rebuild()
end

-- === Refazer o corpo quando o personagem termina de carregar ===
-- Ao trocar de nível (porta, chaminé, viagem rápida) o ik.lua destrói o corpo e o
-- temporizador dele (1x/s) o recria assim que houver um pawn. Nessa janela
-- `Pawn.Mesh` já existe mas está SOZINHO: as malhas modulares ainda não foram
-- presas e o esqueleto não devolve os ossos das pernas. Sai um corpo de uma malha
-- só, em pose de referência e sem animação — é o corpo que 'nasce no chão' e que
-- o botão 'Reconstruir corpo' resolvia na mão. Log: 'Corpo criado com 1 malha(s)'.
-- Só mexe no corpo que nasceu incompleto, e só quando as malhas aparecem.
-- A pé: refazer montado faz o corpo nascer FORA da criatura (ver LEIAME).
local READY_MAX_REBUILDS = 10 -- teto: personagem sem malha filha não vira laço

local function rebuildWhenCharacterLoads()
	if not isEnabled() or currentRig == nil then return end
	if builtChildCount == nil or builtChildCount > 0 then return end -- nasceu completo
	if not mounts.isWalking() then return end
	if readyRebuilds >= READY_MAX_REBUILDS then return end

	local count = countBodyChildMeshes()
	if count == nil or count == 0 then return end -- personagem ainda carregando

	readyRebuilds = readyRebuilds + 1
	logMilestone("Personagem terminou de carregar (" .. count
		.. " malhas): refazendo o corpo")
	rebuild()
end

uevrUtils.setInterval(200, function()
	guard("Falha ao esconder a malha do jogo", keepGameMeshHidden)
	guard("Falha ao refazer o corpo apos carregar", rebuildWhenCharacterLoads)
	guard("Falha ao refazer o corpo no fim do dialogo", rebuildOnCinematicEnd)
	guard("Falha ao refazer o corpo no inventario", rebuildOnGearScreen)
	guard("Falha ao refazer o corpo ao desmontar", rebuildOnDismount)
	guard("Falha ao fechar a mao na varinha", updateWandGrip)
end)

-- === Painel ===

-- Os dois andam juntos; sem laço, porque só escreve quando o valor difere.
local function syncReplaceHands(enabled)
	if configui.getValue("body_replaceHands") == enabled then return end
	configui.setValue("body_replaceHands", enabled)
end

local function syncBodyEnabled(enabled)
	if configui.getValue("body_enabled") == enabled then return end
	configui.setValue("body_enabled", enabled)
end

configui.onCreateOrUpdate("body_enabled", function(value)
	ik.setAutoCreateArms(value == true)
	syncReplaceHands(value == true)
	if value ~= true then
		rebuild()
		restoreHands()
	else
		uevrUtils.delay(1000, enforceHandsOff)
	end
end)

configui.onCreateOrUpdate("body_replaceHands", function(value)
	syncBodyEnabled(value == true)
	if value == false then
		restoreHands()
	else
		uevrUtils.delay(1000, enforceHandsOff)
	end
end)

configui.onCreateOrUpdate("body_shadow", function(value)
	applyShadowSetting()
end)

configui.onCreateOrUpdate("body_followViewDeadzone", function(value)
	bodyYaw.setMinAngularDeviation(value)
end)

-- === Padrões do painel: a calibragem aprovada em jogo ===
-- Serve de initialValue e de alvo do "Restaurar padroes". Posição e rotação não
-- entram: são do IK Dev Config (armadilha 8).
local PANEL_DEFAULTS = {
	body_devMode             = false,
	body_enabled             = true,
	body_replaceHands        = true,
	body_shadow              = false,
	body_onlyArms            = false,
	body_armsHeight          = -15,
	body_animate             = true,
	body_followCrouch        = false,
	body_headCamera          = true,
	body_headCameraHeight    = 5,
	body_gazeLean            = true,
	body_gazeLeanMax         = 16.677,
	body_followView          = true,
	body_followViewDeadzone  = 5,
	body_legOffset           = { 0, 3, 0 },
	body_mountArmsIK         = true,
	body_mountHipAlign       = true,
	body_mountHipSensitivity = 0,
	body_mountHipDeadzone    = 0,
	body_mountHipMaxYaw      = 0,
	body_mountSpineUpright   = 0.785,
	body_broomSpineUpright   = 1,
	body_broomSpineRoll      = true,
	body_mountSpineRoll      = true,
	body_mountSpineTrim      = -1.45,
	body_autoDetectBones     = true,
}

-- Vetor vem do configui como struct (X/Y/Z) e o padrão é lista de três.
local function nearEnough(a, b)
	if type(a) ~= "number" or type(b) ~= "number" then return a == b end
	-- o painel devolve 16.677000045…, então == acusaria uma diferença invisível
	return math.abs(a - b) < 0.0005
end

local function sameAsDefault(current, wanted)
	if type(wanted) == "table" then
		if type(current) ~= "table" and type(current) ~= "userdata" then return false end
		local ok, cx, cy, cz = pcall(function()
			local x = current.X or current.x or current[1]
			local y = current.Y or current.y or current[2]
			local z = current.Z or current.z or current[3]
			return x, y, z
		end)
		if not ok then return false end
		return nearEnough(cx, wanted[1]) and nearEnough(cy, wanted[2]) and nearEnough(cz, wanted[3])
	end
	return nearEnough(current, wanted)
end

-- === Configuracoes avancadas ===
-- begin_group com isHidden esconde o bloco inteiro; a aba do IK é criada sempre e
-- só escondida, pelo nome do arquivo de save.
local IK_DEV_PANEL_ID = "dev/ik_config_dev"

local function applyDevMode()
	local on = configui.getValue("body_devMode") == true
	configui.hideWidget("body_devGroup", not on)
	-- pcall: na primeira passada o painel do IK pode ainda não existir
	pcall(configui.hidePanel, IK_DEV_PANEL_ID, not on)
end

configui.onUpdate("body_devMode", applyDevMode)

-- Só escreve o que está diferente, em ordem fixa e com pcall por item.
local RESET_ORDER = {
	"body_headCameraHeight", "body_gazeLeanMax", "body_followViewDeadzone",
	"body_legOffset", "body_armsHeight",
	"body_mountSpineUpright", "body_mountSpineTrim", "body_mountSpineRoll",
	"body_broomSpineUpright", "body_broomSpineRoll",
	"body_mountHipAlign", "body_mountHipSensitivity", "body_mountHipDeadzone",
	"body_mountHipMaxYaw", "body_mountArmsIK",
	"body_animate", "body_followCrouch", "body_followView",
	"body_headCamera", "body_gazeLean", "body_shadow", "body_autoDetectBones",
	"body_replaceHands", "body_enabled", "body_onlyArms", "body_devMode",
}

configui.onUpdate("body_resetDefaults", function()
	local changed, failed = 0, {}

	local function restore(id)
		local wanted = PANEL_DEFAULTS[id]
		if wanted == nil or sameAsDefault(configui.getValue(id), wanted) then return end
		local ok, err = pcall(configui.setValue, id, wanted)
		if ok then
			changed = changed + 1
		else
			table.insert(failed, id .. " (" .. tostring(err) .. ")")
		end
	end

	local done = {}
	for _, id in ipairs(RESET_ORDER) do
		done[id] = true
		restore(id)
	end
		-- rede de segurança: padrão fora da lista de ordem ainda é restaurado
	for id in pairs(PANEL_DEFAULTS) do
		if not done[id] then restore(id) end
	end

	logMilestone("Padroes restaurados: " .. changed .. " valor(es) mudado(s)")
	if #failed > 0 then
		logMilestone("Padroes que falharam: " .. table.concat(failed, ", "))
	end
end)

-- onUpdate, não onCreateOrUpdate: quem manda na posição é o ik_parameters.json
configui.onUpdate("body_onlyArms", function(value)
	setRigParam("hide_body", value == true)

	-- desmarcar cai no destroyAll do ik.lua; a varredura espera o corpo novo existir
	uevrUtils.delay(1500, function()
		if currentRig == nil or #bodyMeshes == 0 then return end
		pcall(destroyGhostBodies, bodyMeshes)
	end)
end)

configui.onUpdate("body_rebuild", function()
	log("Reconstruindo o corpo")
	rebuild()
end)

-- Fique de pé, na altura em que você joga, e clique.
configui.onUpdate("body_recalibrate", function()
	resetHeightCalibration()
	logMilestone("Altura recalibrada")
end)

configui.onUpdate("body_detectBones", function()
	if currentRig == nil then
		log("Corpo não está criado", LogLevel.Warning)
		return
	end
	if detectBones(currentRig, true) then
		log("Ossos redetectados — reconstruindo o corpo")
		uevrUtils.delay(200, rebuild)
	else
		applyHeadVisibility()
	end
end)

-- Estado que interessa quando a câmera ou a altura estão erradas. Sai como Error.
local function logDiagnostics()
	logMilestone("--- diagnostico ---")
	logMilestone("corpo criado: " .. tostring(currentRig ~= nil) .. ", malhas: " .. #bodyMeshes
		.. ", escondido (filtrado): " .. tostring(isBodyHidden())
		.. ", escondido (cru): " .. tostring(shouldHideBody()))
	logMilestone("headCamera marcado: " .. tostring(configui.getValue("body_headCamera"))
		.. ", ativo agora: " .. tostring(headCameraActive()))
	logMilestone("montaria: tipo=" .. tostring(mounts.getMountType())
		.. ", voando=" .. tostring(mounts.getIsFlying()))

	-- separa as três causas do "noutra posição e pisca": fantasma, coupling, reposição
	logMilestone("somente bracos: " .. tostring(configui.getValue("body_onlyArms"))
		.. ", coupling=" .. tostring(currentRig ~= nil and currentRig.coupling or "?")
		.. ", animando pela malha=" .. tostring(currentRig ~= nil and currentRig.wasAnimating == true)
		.. ", reposicoes do corpo escondido=" .. reapplyCount)

	local copies = collectPoseableCopies(bodyMeshes)
	logMilestone("copias PoseableMesh no pawn: " .. #copies .. " (esperado: " .. #bodyMeshes .. ")")
	for _, entry in ipairs(copies) do
		local loc = entry.component.K2_GetComponentLocation ~= nil
			and entry.component:K2_GetComponentLocation() or nil
		logMilestone("  " .. (entry.mine and "[do corpo] " or "[FANTASMA] ")
			.. shortName(entry.component) .. " em " .. fmt(loc))
	end

	local rootComponent = uevrUtils.getValid(pawn, {"RootComponent"})
	if rootComponent ~= nil then
		logMilestone("pawn root: " .. fmt(rootComponent:K2_GetComponentLocation())
			.. ", CapsuleHalfHeight: " .. tostring(rootComponent.CapsuleHalfHeight))
	end

	local hmd = controllers.getController(2)
	if uevrUtils.getValid(hmd) ~= nil then
		logMilestone("HMD: " .. fmt(hmd:K2_GetComponentLocation()))
	end

	-- O FOCO DE INTERAÇÃO DO JOGO SAI DAQUI, não da nossa view: pitch apontado para o
	-- chão, ou câmera do jogo longe da cabeça, e o objeto à sua frente não entra no foco.
	local pc = uevrUtils.get_player_controller()
	if uevrUtils.getValid(pc) ~= nil then
		local ctrlRot = pc.GetControlRotation ~= nil and pc:GetControlRotation() or pc.ControlRotation
		if ctrlRot ~= nil then
			logMilestone(string.format("controle do jogador: pitch=%.1f, yaw=%.1f, roll=%.1f",
				ctrlRot.Pitch, ctrlRot.Yaw, ctrlRot.Roll))
		end

		local camMan = uevrUtils.getValid(pc, {"PlayerCameraManager"})
		if camMan ~= nil and camMan.GetCameraLocation ~= nil and camMan.GetCameraRotation ~= nil then
			local camLoc = camMan:GetCameraLocation()
			local camRot = camMan:GetCameraRotation()
			logMilestone("camera do jogo: " .. fmt(camLoc) .. (camRot ~= nil
				and string.format(", pitch=%.1f, yaw=%.1f", camRot.Pitch, camRot.Yaw) or ""))

			-- o que você vê contra o que o jogo mede
			local head = getHeadWorldLocation()
			if head ~= nil and camLoc ~= nil then
				local dx, dy, dz = head.X - camLoc.X, head.Y - camLoc.Y, head.Z - camLoc.Z
				logMilestone(string.format(
					"vista x camera do jogo: horizontal=%.1f cm, vertical=%.1f cm",
					math.sqrt(dx * dx + dy * dy), dz))
			end
		end
	end

	-- A MIRA DO JOGO SAI DA VARINHA (ponta + UpVector, `wand.lua:257`), não do olhar.
	-- Ponta longe do controle = varinha velha na conta, e a mira vai para outro lugar.
	if wandHelper.getWandTargetLocationAndDirection ~= nil then
		local _, wandDir, wandPos = wandHelper.getWandTargetLocationAndDirection(false)
		if wandPos ~= nil then
			local msg = "varinha: ponta=" .. fmt(wandPos)
				.. ", visivel=" .. tostring(wandHelper.isVisible())
			if wandDir ~= nil then
				msg = msg .. string.format(", apontando %.0f graus na vertical",
					math.deg(math.asin(math.max(-1, math.min(1, wandDir.Z)))))
			end
			-- a distância até cada controle: uma delas tem de ser a mão que a segura
			for index, label in ipairs({ "esq", "dir" }) do
				local controller = controllers.getController(index - 1)
				if uevrUtils.getValid(controller) ~= nil and controller.K2_GetComponentLocation ~= nil then
					local loc = controller:K2_GetComponentLocation()
					local wx, wy, wz = wandPos.X - loc.X, wandPos.Y - loc.Y, wandPos.Z - loc.Z
					msg = msg .. string.format(", %s=%.1f cm", label,
						math.sqrt(wx * wx + wy * wy + wz * wz))
				end
			end
			logMilestone(msg)
		end
	end

	logMilestone("altura: quadril abaixado=" .. string.format("%.1f", hipDrop)
		.. ", deslocamento do quadril=" .. string.format("%.1f", hipShift.Z)
		.. ", quadril de pe (origem)=" .. (standingSourceHipZ and string.format("%.1f", standingSourceHipZ) or "nil")
		.. ", quadril na pose de referencia=" .. (referenceHip and string.format("%.1f", referenceHip.Z) or "nil"))

	local source = getSourceMesh()
	if uevrUtils.getValid(source) ~= nil then
		logMilestone("malha de origem no mundo: " .. fmt(source:K2_GetComponentLocation()))
		-- é desta rotação que sai a reclinada do tronco montado
		local srcRot = source:K2_GetComponentRotation()
		if srcRot ~= nil then
			logMilestone(string.format(
				"rotacao da malha de origem: pitch=%.1f, yaw=%.1f, roll=%.1f",
				srcRot.Pitch, srcRot.Yaw, srcRot.Roll))
		end
	end

	logMilestone("pernas: animar=" .. tostring(configui.getValue("body_animate"))
		.. ", escrevendo agora=" .. tostring(legsApplied)
		.. ", malhas=" .. #legMeshes .. ", a pe=" .. tostring(mounts.isWalking()))
	logMilestone("coluna vassoura: endireitar="
		.. tostring(configui.getValue("body_broomSpineUpright"))
		.. ", lateral=" .. tostring(configui.getValue("body_broomSpineRoll"))
		.. ", na vassoura agora=" .. tostring(mounts.isOnBroom()))
	logMilestone("coluna: endireitar=" .. tostring(configui.getValue("body_mountSpineUpright"))
		.. ", lateral=" .. tostring(configui.getValue("body_mountSpineRoll"))
		.. ", ajuste fino=" .. tostring(configui.getValue("body_mountSpineTrim"))
		.. ", corrigindo agora=" .. tostring(computeSpineCorrection() ~= nil))

	-- o yaw diz se está dentro da janela; tudo zero com yaw grande é a janela agindo
	local relYaw, relPitch = getGazeInBodySpace()
	logMilestone("olhar: yaw=" .. (relYaw ~= nil and string.format("%.0f", relYaw) or "?")
		.. ", pitch=" .. (relPitch ~= nil and string.format("%.0f", relPitch) or "?")
		.. ", empurrao=" .. string.format("%.1f", gazeLeanDistance())
		.. " cm, marcado=" .. tostring(configui.getValue("body_gazeLean")))

	local mesh = bodyMeshes[1]
	if uevrUtils.getValid(mesh) ~= nil then
		logMilestone("corpo relativo: " .. fmt(mesh.RelativeLocation)
			.. ", mundo: " .. fmt(mesh:K2_GetComponentLocation()))

		-- alturas lado a lado: separa "corpo no lugar errado" de "há mais de um corpo"
		if rootComponent ~= nil and uevrUtils.getValid(source) ~= nil then
			local srcLoc = source:K2_GetComponentLocation()
			local rootLoc = rootComponent:K2_GetComponentLocation()
			if srcLoc ~= nil and rootLoc ~= nil then
				logMilestone(string.format("altura: malha do jogo-root=%.1f, corpo-root=%.1f, Z de Posicao=%s",
					srcLoc.Z - rootLoc.Z,
					mesh:K2_GetComponentLocation().Z - rootLoc.Z,
					tostring(currentRig ~= nil and currentRig.meshLocationOffset ~= nil
						and currentRig.meshLocationOffset.Z or "?")))
			end
		end

		-- malhas diferentes = mais de um rig vivo
		local ikMesh = ik.getCurrentMesh and ik.getCurrentMesh(1) or nil
		local ikName = uevrUtils.getValid(ikMesh) ~= nil and shortName(ikMesh) or "nil"
		logMilestone("rig rastreado x rig do ik.lua: " .. shortName(mesh) .. " / " .. ikName
			.. ", sao o mesmo: " .. tostring(ikMesh == mesh))
		logMilestone("osso da cabeca '" .. headBone .. "' no mundo: " .. fmt(getHeadWorldLocation()))

			-- quadril na origem x na cópia: a diferença mostra o quanto agachou
		if legAnchorFName ~= nil and currentRig ~= nil then
			if uevrUtils.getValid(source) ~= nil then
				local sourceHip = source:GetSocketTransform(legAnchorFName, RTS_COMPONENT)
				local targetHip = mesh:GetBoneTransformByName(legAnchorFName, EBoneSpaces.ComponentSpace)
				if sourceHip ~= nil and targetHip ~= nil then
					logMilestone("quadril (espaco de componente) origem: " .. fmt(sourceHip.Translation)
						.. ", copia: " .. fmt(targetHip.Translation))
				end
			end
		end
	end
	logMilestone("--- fim ---")
end

configui.onUpdate("body_diagnostics", function()
	guard("Falha no diagnostico", logDiagnostics)
end)

configui.onUpdate("body_logBones", function()
	local mesh = bodyMeshes[1]
	if uevrUtils.getValid(mesh) == nil then
		log("Corpo não está criado", LogLevel.Warning)
		return
	end
	animation.logBoneNames(mesh)
end)

-- Atalhos do painel: os textos de ajuda são só rótulo e os títulos de seção são
-- o mesmo rótulo pintado. O configui lê a cor na ordem #BBGGRRAA
-- (configui.lua:480), então este "#64C8FFFF" sai âmbar.
local function txt(label)
	return { widgetType = "text", label = label }
end

local function head(label)
	return { widgetType = "text_colored", color = "#64C8FFFF", label = label }
end

local BODY_PANEL = {
	txt("Full first person body."),
	{ widgetType = "spacing" },

	head("Body"),
	{ widgetType = "checkbox", id = "body_enabled", label = "Enable VR body" },
	{ widgetType = "checkbox", id = "body_replaceHands", label = "Use the body's hands" },
	txt("  Turns off the UEVR Show Hands."),
	{ widgetType = "checkbox", id = "body_shadow", label = "Body casts a shadow" },
	{ widgetType = "checkbox", id = "body_onlyArms", label = "Arms only (hides torso and legs)" },
	txt("  Arms only; set the arm height below."),
	{ widgetType = "drag_float", id = "body_armsHeight", speed = 0.5, range = { -100, 100 },
		label = "  Arm height" },
	txt("    From the eyes down to the shoulders; more negative lowers them."),
	{ widgetType = "spacing" },

	head("Calibration"),
	{ widgetType = "drag_float", id = "body_headCameraHeight", speed = 0.5, range = { -100, 100 },
		label = "Eye height" },
	txt("  Above the head bone; higher raises the view."),
	{ widgetType = "drag_float3", id = "body_legOffset", speed = 0.5, range = { -100, 100 },
		label = "Legs (X left, Y forward, Z height)" },
	txt("  Moves thigh, shin, foot and toes together, along the skeleton axes."),
	{ widgetType = "spacing" },
	{ widgetType = "button", id = "body_resetDefaults", label = "Restore defaults" },
	txt("  Back to the calibration tested in game."),
	txt("  Leaves 'Location' and 'Rotation' alone (they belong to IK Dev Config)."),
	{ widgetType = "spacing" },

	{ widgetType = "checkbox", id = "body_devMode", label = "Advanced settings" },
	txt("  Shows the settings already dialed in and the 'IK Dev Config' tab."),
	{ widgetType = "begin_group", id = "body_devGroup", isHidden = true },

	head("  Camera"),
	{ widgetType = "checkbox", id = "body_headCamera", label = "  Camera on the body's head" },
	txt("    Requires Roomscale Movement enabled in the UEVR menu."),
	txt("    Rotation still comes from the headset."),
	{ widgetType = "checkbox", id = "body_gazeLean", label = "  Camera moves forward when looking down" },
	txt("    Only within 120 degrees of the body's front."),
	{ widgetType = "slider_float", id = "body_gazeLeanMax", speed = 0.5, range = { 0, 40 },
		label = "    How far it moves (cm)" },
	{ widgetType = "spacing" },

	head("  Body"),
	{ widgetType = "checkbox", id = "body_followView", label = "  Body follows the view (turning)" },
	{ widgetType = "slider_int", id = "body_followViewDeadzone", speed = 1.0, range = { 1, 90 },
		label = "    Angle before it starts turning" },
	{ widgetType = "checkbox", id = "body_animate", label = "  Animate the legs from the game" },
	txt("    Waist down only."),
	{ widgetType = "checkbox", id = "body_followCrouch",
		label = "  Body follows crouching (unticked reduces motion sickness)" },
	txt("    Without this, crouching lifts the feet instead of lowering the body."),
	{ widgetType = "spacing" },

	head("  Mount (creatures only; the broom is not included)"),
	{ widgetType = "checkbox", id = "body_mountArmsIK", label = "  Arms driven by IK" },
	txt("    Without this the hand freezes on the hippogriff."),
	{ widgetType = "checkbox", id = "body_mountHipAlign", label = "  Torso follows the headset" },
	txt("    Turns the waist bone; the legs stay in the stirrups."),
	{ widgetType = "slider_float", id = "body_mountHipSensitivity", speed = 0.01, range = { 0, 1 },
		label = "    Sensitivity" },
	txt("      How much the torso copies from the head: 1 follows it all, 0.5 half, 0 not at all."),
	{ widgetType = "slider_int", id = "body_mountHipDeadzone", speed = 1.0, range = { 0, 60 },
		label = "    Angle before it starts turning" },
	{ widgetType = "slider_int", id = "body_mountHipMaxYaw", speed = 1.0, range = { 0, 90 },
		label = "    Turn limit (degrees)" },
	{ widgetType = "slider_float", id = "body_mountSpineUpright", speed = 0.01, range = { 0, 1 },
		label = "  Straighten the spine" },
	txt("    0 = game pose, 1 = vertical."),
	{ widgetType = "slider_float", id = "body_mountSpineTrim", speed = 0.5, range = { -45, 45 },
		label = "  Spine fine tuning (degrees)" },
	txt("    + leans back, - leans forward."),
	txt("    The camera rises with it: readjust the eye height."),
	{ widgetType = "checkbox", id = "body_mountSpineRoll", label = "  Straighten the sideways lean" },
	txt("    Uncheck to lean along through the turns."),
	{ widgetType = "spacing" },

	head("  Broom"),
	{ widgetType = "slider_float", id = "body_broomSpineUpright", speed = 0.01, range = { 0, 1 },
		label = "  Straighten the spine" },
	txt("    0 = game pose, 1 = fully upright."),
	txt("    The camera rises with it: readjust the eye height."),
	{ widgetType = "checkbox", id = "body_broomSpineRoll", label = "  Straighten the sideways lean" },
	txt("    Uncheck to lean along through the turns."),
	txt("    Depends on the value above: with the spine at 0 this does nothing."),
	{ widgetType = "spacing" },

	head("  Bones"),
	{ widgetType = "checkbox", id = "body_autoDetectBones", label = "  Detect bones automatically" },
	txt("    Fixes a bone name that does not exist in the mesh."),
	{ widgetType = "end_group" },
	{ widgetType = "spacing" },

	head("Actions"),
	{ widgetType = "button", id = "body_recalibrate", label = "Recalibrate height" },
	{ widgetType = "same_line" },
	{ widgetType = "button", id = "body_rebuild", label = "Rebuild body" },
	{ widgetType = "same_line" },
	{ widgetType = "button", id = "body_detectBones", label = "Detect bones now" },
	{ widgetType = "same_line" },
	{ widgetType = "button", id = "body_logBones", label = "List bones in the log" },
	{ widgetType = "same_line" },
	{ widgetType = "button", id = "body_diagnostics", label = "Diagnostics in the log" },
	txt("  Recalibrate: stand at the height you play at, then click."),
	{ widgetType = "spacing" },
	txt("Arm and hand fine tuning: 'IK Dev Config' tab."),
}

-- initialValue vem do PANEL_DEFAULTS: um valor, um dono. Botões passam batido.
for _, item in ipairs(BODY_PANEL) do
	if item.id ~= nil and PANEL_DEFAULTS[item.id] ~= nil then
		item.initialValue = PANEL_DEFAULTS[item.id]
	end
end

configui.create({
	{ panelLabel = "VR Body", saveFile = "config_body", layout = BODY_PANEL },
})
ik.init(SHOW_DEV_UI, LogLevel.Info)

-- depois do ik.init, que é quem cria a aba "IK Dev Config"
applyDevMode()

-- depois do registro do main.lua; o delay evita o frame de inicialização
uevrUtils.delay(2000, registerHeadCamera)

-- dentro de um nível, quem cria o corpo é o temporizador do ik.lua
uevrUtils.registerLevelChangeCallback(function()
	registerHeadCamera() -- protegido por flag: registra uma vez só
end)
