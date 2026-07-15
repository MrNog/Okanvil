# Okanvil — convenção de módulo

O padrão que **já** usas em todos os módulos, escrito para o próximo módulo (e o
próximo Claude) seguir sem adivinhar. Nada aqui é novo — é o que o Guild, o IDs, o
Logs e o RaidFinder fazem. Se estás a escrever um módulo e divergires disto, tens
de ter uma razão.

---

## 1. Esqueleto de um módulo

Todo o ficheiro em `Okanvil/Modules/` começa igual:

```lua
-- ============================================================
-- Okanvil -- <Nome> (native core module).
-- <1-3 linhas: o QUE faz e PORQUÊ existe. Não o como.>
-- ============================================================

local Okanvil = Okanvil        -- upvalue local do global (rápido + claro)
local M = {}                   -- a tabela do módulo
Okanvil.<Nome> = M             -- publica no namespace único
```

- **Um só global**: `Okanvil`. Nunca crias outro global. Tudo pendura de `Okanvil.*`.
- **`local Okanvil = Okanvil`** no topo — todos os ficheiros o fazem; é upvalue
  rápido e deixa claro que dependes do host.
- A tabela do módulo é **local** (`M`) e publicada uma vez (`Okanvil.Loot = M`).

## 2. Registar-se no host (para aparecer no menu)

Um módulo que tem uma **página** regista-se em `Okanvil_Plugins` no `PLAYER_LOGIN`:

```lua
Okanvil_Plugins = Okanvil_Plugins or {}
Okanvil_Plugins[ADDON] = {
    title = "ID Finder",
    desc  = "Search spells & items by name to get their ID.",
    icon  = (Okanvil and Okanvil.ICONS and Okanvil.ICONS.ids) or "Interface\\Icons\\...",
    build = function(panel) buildUI(panel) end,   -- desenha para o painel dado
}
if Okanvil and Okanvil.Register then
    Okanvil:Register(ADDON)
end
```

- O registo é **load-order safe**: preenches `Okanvil_Plugins`, o Core drena com
  `ProcessPlugins` / `Register`. Não assumes que o Core já carregou.
- `build(panel)` recebe um painel já com scroll — **desenhas para dentro dele**,
  não crias a tua própria janela.
- Um módulo **sem** página (ex. captura sempre-ligada como Attendance) não se
  regista — só engancha os eventos.

## 3. Helpers: usa os partilhados, não recries

**Antes de escrever um helper, procura-o.** A ordem de preferência:

1. **`Okanvil.U.*`** — string/link utils partilhados (`esc`, `escPattern`,
   `itemIDFromLink`, `shortLink`). Ver `Core/Util.lua`.
2. **`Okanvil.W.*`** — a fábrica de widgets (`Button`, `Check`, `Slider`,
   `EditBox`, `DropDown`, `Text`, `Frame`, `Dashboard`). Ver `Core/Widgets.lua`.
3. **`Okanvil.Comms.After`** (não há `C_Timer` no 3.3.5a), **`Okanvil.Clip`**
   (não há `SetClipsChildren`).

Se copiaste o mesmo bloco **3 vezes**, sobe-o para `Okanvil.U` (lógica) ou
`Okanvil.W` (widget) — foi assim que o `esc` e o `W.Dashboard` nasceram.

### A regra que evita over-engineering

**Extrai quando as ocorrências são IGUAIS, não quando são só PARECIDAS.** Um
helper com 8 parâmetros opcionais para cobrir 4 formas diferentes é pior que 4
blocos honestos. Auditámos os "campos" da UI uma vez: pareciam duplicados, eram
7 formas distintas — e a decisão certa foi **não** criar o helper. Regra de ouro:
se o helper precisa de um `if` por cada call-site, não é um helper.

## 4. UI: uma página por ficheiro

A UI vive em `Core/UI/`:

- **`Shell.lua`** — a moldura (janela, nav, panels, minimap) + publica os helpers
  partilhados de UI em `Okanvil.UI.*` (`FLAT`, `u3`, `newFillPanel`,
  `newScrollPanel`).
- **`Page_<X>.lua`** — uma página por ficheiro. Cada uma começa com o mesmo
  preâmbulo que puxa os helpers de `Okanvil.UI.*`:

  ```lua
  local Okanvil = Okanvil
  local W = Okanvil.W
  local C = Okanvil.Colors
  local FLAT           = Okanvil.UI.FLAT
  local newFillPanel   = Okanvil.UI.newFillPanel
  -- ...
  function Okanvil:BuildX() ... end
  ```

- As páginas são **métodos** `Okanvil:BuildX()`. Isso é de propósito: métodos de
  tabela não fecham sobre upvalues de ficheiro, por isso movem-se entre ficheiros
  sem partir. Se precisas de estado partilhado entre páginas, põe-no numa tabela
  (`Okanvil.algo`), **nunca** num `local` de ficheiro.

## 5. Armadilhas do 3.3.5a (Interface 30300)

Estas partem o addon em clientes stock. Ver também o `CLAUDE.md`.

| Não existe | Usa |
|---|---|
| `SetShown` / `SetEnabled` | `Show()`/`Hide()` (o Core faz polyfill de `SetShown`) |
| `C_Timer` | `Okanvil.Comms.After(delay, fn)` |
| `SetClipsChildren` | `Okanvil.Clip(frame)` |
| `RegisterAddonMessagePrefix` | — (não é preciso) |
| HTTP / qualquer rede | — (impossível; a ponte é SavedVariables) |

**Nunca `SetFocus` automático** num EditBox — captura o teclado (W/A/S/D) e torna
o jogo injogável. O Core rastreia EditBoxes e liberta foco ao esconder/combate.

## 6. Validar sem interpretador

Não há Lua CLI. Valida **estruturalmente**: balanceador que tira
comentários/strings primeiro, depois confere `then`/`do`/`function`/`repeat`
contra `end`/`until`, e parênteses/chavetas a zero. Compara o resultado contra a
versão pristina (`git show HEAD:<ficheiro>`) antes de confiar no zero. Depois o
teste real: carregar in-game e `/reload`.

**Dois clientes**: a máquina corre dois WoW (LoTK + "hd stable"). Copia os
ficheiros alterados para **ambos**, ou o fix "não pega" após `/reload`.
