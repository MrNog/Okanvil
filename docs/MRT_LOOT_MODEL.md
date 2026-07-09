# Modelo de loot do **MRT** — captura por chat + atribuição de quem recebeu

*Estudo do código real do MRT (`Interface/AddOns/MRT/LootHistory.lua`) no cliente
3.3.5a. É a base de projeto para a **2ª parte** do sistema de loot do Okanvil: a
parte que sabe **QUEM recebeu cada item**, não só o que dropou.*

> **A grande diferença:** o RaidRoll escaneia o **corpo** (`LOOT_OPENED`) e só sabe
> "o que caiu" — precisa de rolls pra descobrir quem ganhou. O **MRT lê o CHAT**
> (`CHAT_MSG_LOOT`), e a mensagem do jogo **já diz quem recebeu o quê**. Por isso
> o MRT resolve a atribuição de graça.

---

## 1. Os únicos 3 eventos que o MRT registra no 3.3.5a

```lua
-- LootHistory.lua:31-34  (ExRT.isClassic == 3.3.5a)
function module:Enable()
    if ExRT.isClassic then
        module:RegisterEvents("CHAT_MSG_LOOT", "ENCOUNTER_START", "ENCOUNTER_END")
        return
    end
    ...
end
```

Só isso. **Não** usa `LOOT_OPENED`, **não** usa `START_LOOT_ROLL`, **não** usa
`GetLootSlotLink` / `GetNumLootItems`. Nada de escanear corpo.

| Evento | Pra quê |
|---|---|
| `CHAT_MSG_LOOT` | captura o loot — **quem recebeu** + **qual item** |
| `ENCOUNTER_START` | pega o **nome do boss** (oficial, do encounter) |
| `ENCOUNTER_END` | idem (confirma / guarda o nome) |

---

## 2. Nome do boss vem do ENCOUNTER, nunca do corpo

```lua
-- LootHistory.lua:246-252
function module.main:ENCOUNTER_START(encounterID, encounterName)
    module.db.prevEncounterID = encounterID
    if encounterID and encounterID ~= 0 and encounterName and encounterName ~= "" then
        VMRT.LootHistory.bossNames = VMRT.LootHistory.bossNames or {}
        VMRT.LootHistory.bossNames[encounterID] = encounterName
    end
end
```

O MRT guarda o nome do boss no momento em que o encounter começa/termina. Por isso
**nunca erra o boss** — não depende do alvo do corpo (que pode ser um player, ou
já ter sido limpo). O loot capturado depois é atribuído a esse encounter.

---

## 3. A captura: ler `CHAT_MSG_LOOT` (o coração do modelo)

Quando **qualquer pessoa** do grupo pega um item, o jogo escreve no chat uma linha
tipo *"Fulano recebe o saque: [item]."*. **Todo mundo recebe essa mensagem** — não
depende de abrir corpo, de quem lootou, nem do método de loot. O MRT casa essa
linha contra vários padrões pra extrair **quem** e **o quê**.

### Os padrões que ele reconhece (LootHistory.lua:253-289)

```lua
addPattern(LOOT_ITEM_MULTIPLE,       fn -> name, link, qty)   -- "X recebe o saque: [item]x2."
addPattern(LOOT_ITEM_SELF_MULTIPLE,  fn -> VOCÊ, link, qty)   -- "Você recebe o saque: [item]x2."
addPattern(LOOT_ITEM,                fn -> name, link, 1)     -- "X recebe o saque: [item]."
addPattern(LOOT_ITEM_SELF,           fn -> VOCÊ, link, 1)     -- "Você recebe o saque: [item]."
addPattern(LOOT_ITEM_PUSHED_*,       ...)                     -- itens "empurrados" pros bags
addPattern(LOOT_ROLL_WON,            fn -> name, link, 1)     -- "X ganhou: [item]."  (need/greed)
addPattern(LOOT_ROLL_YOU_WON,        fn -> VOCÊ, link, 1)     -- "Você ganhou: [item]."
```

Pontos importantes:

- Usa as **constantes globais localizadas** (`LOOT_ITEM`, `LOOT_ITEM_SELF`, ...),
  então funciona em qualquer idioma do cliente — não hardcoda "recebe o saque".
- Cobre tanto o **loot direto** (`LOOT_ITEM`) quanto o **vencedor de roll**
  (`LOOT_ROLL_WON`). Ou seja: pega loot de Master Loot **e** de Need/Greed.
- Cada padrão devolve `(playerName, itemLink, quantity)` — **o nome de quem
  recebeu já vem junto**. Essa é a atribuição que você queria.

### O fluxo do handler (LootHistory.lua:315-350)

```lua
function module.main:CHAT_MSG_LOOT(msg)
    -- 1. só em raid
    local _, instance_type, difficulty = GetInstanceInfo()
    if instance_type ~= "raid" then return end

    -- 2. casa a msg contra os padrões -> playerName, itemLink, quantity
    for i=1,#patterns do
        local a,b,c = msg:match(patterns[i][1])
        if a then playerName, itemLink, quantity = patterns[i][2](a,b,c); break end
    end
    if not playerName or not itemLink then return end

    -- 3. filtro de qualidade: só epic+
    local _,_,itemRarity = GetItemInfo(itemLinkShort)
    if not itemRarity or itemRarity < 4 then return end

    -- 4. deny-list por id (emblemas / trophy / mats epic)
    if itemId and EMBLEM_ITEM_IDS[itemId] then return end

    -- 5. de-dupe por JOGADOR:ITEM em 5s
    if ShouldDedupe(playerName, itemId) then return end

    -- 6. resolve a classe do jogador (raid roster / party / você) e grava
    ...
end
```

---

## 4. O de-dupe do MRT — a chave inclui o JOGADOR (resolve o bug das bracers)

```lua
-- LootHistory.lua:305-313
local lastLoot = {}
local function ShouldDedupe(playerName, itemId)
    local key = playerName .. ":" .. itemId      -- <<< JOGADOR + ITEM
    local now = GetTime()
    local prev = lastLoot[key]
    if prev and (now - prev) < 5 then return true end   -- mesma linha repetida em 5s
    lastLoot[key] = now
    return false
end
```

**Repare na chave:** `playerName .. ":" .. itemId`. Isso significa:

| Caso | Mesma chave? | Resultado |
|---|---|---|
| Fazcafe recebe 47280, Kobee recebe 47280 | ❌ chaves diferentes | **conta os dois** ✅ |
| A mesma linha "Fazcafe recebe 47280" chega 2x em 5s | ✅ mesma chave | descarta a 2ª ✅ |

Era exatamente o bug que a gente tinha: duas bracers iguais pra jogadores
diferentes, e o de-dupe antigo (só por `itemId`) comia a segunda. **O jeito certo
é a chave incluir o jogador** — que é o que o MRT faz. A janela de 5s serve só pra
matar a linha de chat duplicada, não drops legítimos.

---

## 5. Filtros do MRT

**Qualidade:** só `itemRarity >= 4` (epic+).

**Zona:** só `instance_type == "raid"`.

**Deny-list por id** (LootHistory.lua:293-303) — moeda/tokens/mats que não são loot
de guild de verdade:

```lua
EMBLEM_ITEM_IDS = {
    40752, 40753, 45624, 47241, 49426,   -- emblemas WotLK
    43228,   -- Stone Keeper's Shard
    44990,   -- Champion's Seal
    47242,   -- Trophy of the Crusade
    52027,   -- Sidereal Essence
    20725, 22450, 34057,   -- crystals de encantamento epic (de DE roll)
    49908,   -- Primordial Saronite
}
```

---

## 6. Resolução da classe do jogador (LootHistory.lua:359+)

Depois de saber quem recebeu, o MRT descobre a **classe** pra colorir o nome:

1. Se for **você** → `UnitClass("player")`.
2. Se estiver em **raid** → varre `GetRaidRosterInfo(i)` procurando o nome.
3. Se estiver em **party** → varre `party1..4` com `UnitName`.

O nome pode vir como "Nome-Reino"; o MRT tira o sufixo do reino
(`ExRT.F.delUnitNameServer`) antes de comparar.

---

## 7. Por que este modelo é superior (resumo pro projeto)

| Requisito | RaidRoll (`LOOT_OPENED`) | **MRT (`CHAT_MSG_LOOT`)** |
|---|---|---|
| Registra loot que **outro** pegou | ❌ só quem abre o corpo | ✅ **todos** (chat é nativo) |
| Precisa dos outros terem o addon | ❌ sim (broadcast) | ✅ **não** |
| Sabe **quem recebeu** | ❌ não (só o que caiu) | ✅ **sim, vem na mensagem** |
| Erra o nome do boss | às vezes | ✅ **nunca** (ENCOUNTER) |
| Dois do mesmo item = perde um | ❌ (bug das bracers) | ✅ **não** (chave = jogador:item) |
| Precisa escanear corpo / abrir loot | sim | ✅ **não** |

---

## 8. Projeto da 2ª parte do loot do Okanvil (baseado no MRT)

A captura do Okanvil deve seguir este modelo:

**Eventos a registrar:**
- `ENCOUNTER_START` / `ENCOUNTER_END` → guardar `encounterID -> encounterName` (nome do boss).
- `CHAT_MSG_LOOT` → capturar `(jogador, item, qtd)`.

**No handler do `CHAT_MSG_LOOT`:**
1. Só em raid (`GetInstanceInfo` → `instance_type == "raid"`), ou honrar o toggle de dungeon do Okanvil.
2. Casar a mensagem contra as constantes globais localizadas:
   `LOOT_ITEM`, `LOOT_ITEM_SELF`, `LOOT_ITEM_MULTIPLE`, `LOOT_ITEM_SELF_MULTIPLE`,
   `LOOT_ITEM_PUSHED*`, `LOOT_ROLL_WON`, `LOOT_ROLL_YOU_WON`.
3. Filtro: `itemRarity >= 4` + deny-list por id (emblemas/trophy/mats) — reaproveitar
   a lista que o Okanvil já tem.
4. **De-dupe com chave `jogador:itemId` em ~5s** (NÃO só por itemId — isso é o que
   corrige o bug das bracers).
5. Resolver a classe do jogador (raid roster / party / você) e gravar na sessão.
6. `receivedBy = jogador` já no momento da captura — a atribuição vem pronta,
   sem precisar de roll pra saber quem ganhou.

**O que isso resolve de uma vez:**
- ✅ registra loot que **qualquer** pessoa pega (sem abrir corpo, sem broadcast)
- ✅ já sabe **quem recebeu** cada item (`receivedBy` preenchido na hora)
- ✅ nunca erra o boss
- ✅ de-dupe correto (dois itens iguais pra pessoas diferentes contam os dois)

> **Nota:** o sistema de **roll** (announce + `/roll` + escolher vencedor) do
> RaidRoll continua útil pra decidir quem GANHA um item **antes** de dar. Mas o
> REGISTRO de quem de fato recebeu deve vir do `CHAT_MSG_LOOT` (modelo MRT), que é
> a verdade do que o jogo efetivamente entregou.
