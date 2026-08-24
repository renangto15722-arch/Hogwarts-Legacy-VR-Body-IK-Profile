# Corpo VR no perfil Hogwarts Legacy

## Primeira linha alterada no main.lua (importante)

`main.lua:1549` passou de `uevrUtils.initUEVR(uevr)` para
`uevrUtils.initUEVR(uevr, function() UEVRReady(uevr) end)`.

Motivo: a uevrlib nova **se auto-inicializa** no fim do `libs/uevr_utils.lua`
(`M.initUEVR(uevr)`), coisa que a versão antiga não fazia. Isso acontece já no
`require` da linha 3 do `main.lua` — antes da função `UEVRReady` existir. Então
o `if UEVRReady ~= nil then UEVRReady(uevr) end` de dentro do `initUEVR` não
achava nada, e a chamada do fim do arquivo caía no early-return de "já
inicializado", sem callback.

Resultado: **`UEVRReady` nunca era executada**, e com ela ficavam de fora:

- `config.init()` → o painel **"Hogwarts Config"** não aparecia e as
  configurações salvas em `data/config_hogwarts.json` nunca eram carregadas (o
  mod rodava com os valores fixos do `config/config.lua`)
- `initLevel()`, `preGameStateCheck()`, `hookLateFunctions()`,
  `checkStartPageIntro()`

O `initUEVR` novo executa o callback mesmo já estando inicializado — é o
caminho de compatibilidade previsto pela própria lib.

## A segunda alteração no main.lua: Locomotion Head pelo UEVR (12/08/2026)

`main.lua:1002`, dentro do `on_lazy_poll` (que roda o tempo todo), era:

```lua
if MovementOrientation == "1" or MovementOrientation == "2" then
    uevr.params.vr.set_mod_value("VR_MovementOrientation","0")
end
```

Ou seja: marcar **Locomotion: Head** na aba **Input do UEVR** voltava sozinho para
Game na passada seguinte do poll. O motivo original é legítimo — este perfil faz a
orientação de movimento **por conta própria**, girando o analógico em
`helpers/input.lua:153`, e deixar os dois ligados aplicaria o giro duas vezes.
(Curiosidade: o valor `3`, controle direito, nunca foi revertido — só 1 e 2.)

Agora a supressão só vale **quando o perfil está de fato dirigindo**:

```lua
if locomotionMode ~= LocomotionMode.Manual and (MovementOrientation == "1" or MovementOrientation == "2") then
```

Com **Hogwarts Config → Locomotion Mode: Game** o perfil não gira nada, e aí a
escolha feita na aba Input do UEVR sobrevive. Em qualquer outro caso o
comportamento é idêntico ao original.

Isso existe porque o modo **Head do próprio perfil** só age dentro de
`not isDecoupledYawDisabled` (`helpers/input.lua:139`) — um `local` do `main.lua`
que nasce `true` e é ligado/desligado por uns seis ganchos (Field Guide,
Alohomora, astronomia, NewGame, `isFP` desligado, grip esquerdo segurado). Se um
deles disparar sem o par de saída, o modo Head para em silêncio e o andar fica
igual ao Game, com a caixinha ainda marcada em Head. A via nativa do UEVR não
passa por esse flag.

Backup do arquivo antes desta mudança:
`backups/main_2026-08-12_antes_locomotion.lua`. Fora essas **duas** alterações, o
`main.lua` continua idêntico ao do zip original.

## O que foi feito

1. **`scripts/libs/` foi atualizado** para a versão atual da uevrlib (a mesma da
   pasta `UEVRLIB`). A versão que estava no perfil era antiga e não tinha o
   módulo `ik.lua`, que é o que cria o corpo. As funções que o perfil já usava
   (`hands`, `animation`, `controllers`, `configui`, `uevr_utils`,
   `flicker_fixer`) continuam existindo com as mesmas assinaturas — as
   diferenças são só parâmetros opcionais novos no fim das listas.
2. **`scripts/body.lua`** (novo) — cria e controla o corpo.
3. **`data/ik_parameters.json`** (novo) — a configuração do rig: quais ossos
   cada braço usa e onde o corpo fica em relação ao jogador.

O perfil original está inteiro em
`Desktop\HOGWARTS LEGACY\backups\HogwartsLegacy_2026-08-04`.

## Como funciona

É o mesmo esquema do perfil do Silent Hill f:

1. O módulo IK faz uma **cópia `PoseableMeshComponent`** da malha do personagem
   (`Pawn.Mesh` + as malhas filhas: roupa, luvas, braços…) e prende essa cópia
   no `RootComponent` do pawn, abaixada até o chão.
2. Dois **solvers de Two Bone IK** giram `RightArm → RightForeArm → RightHand` e
   `LeftArm → LeftForeArm → LeftHand` para as mãos acompanharem os controles.
3. As poses de dedo que o perfil já tinha (`helpers/hand_animations.lua`) são
   reaproveitadas nas mãos do corpo, então gatilho, grip e polegar continuam
   animando os dedos.

Como o corpo é uma cópia separada, ele continua visível mesmo com o
`hidePlayer()` do perfil escondendo o personagem original em primeira pessoa.

## Posição do corpo

A posição é **configuração em jogo**, pelo campo **Posição** da aba "VR Body"
(X frente, Y direita, Z altura) e pela **Rotação (Yaw)**. Os dois gravam em
`data/ik_parameters.json`, que é a fonte da verdade.

Os valores que já vêm no perfil foram ajustados em jogo e testados:
`Posição = (0, -4.5, -87)` e `Yaw = 13`.

A **base** horizontal do corpo é a origem do pawn. Houve aqui, até 11/08/2026,
uma base tirada da posição do HMD — o **"Corpo segue a posicao da cabeca"** —,
removida opção e código; ver a seção da câmera na cabeça, logo abaixo. O
parágrafo seguinte explica por que ela existia, e continua valendo como aviso do
que reaparece se a câmera na cabeça for desmarcada.

A razão era que a câmera deste perfil orbita a origem do pawn: o `main.lua:130`
faz `camera = pawnPos + RotateAngleAxis(playerOffset(19,-3,70), yawDaVisão)`, ou
seja, um raio de ~19 cm — virar 180° com yaw desacoplado move a câmera uns 38 cm.
O corpo, preso ao `RootComponent` com deslocamento fixo, não acompanhava essa
órbita e aparecia mais para frente ou mais para trás conforme a direção do olhar.

Em vez de repetir a fórmula do `main.lua` (que ainda depende do offset de
montaria), o script mede onde o HMD está em relação ao pawn e usa isso como base
— o que cobre a órbita da câmera, o roomscale e as montarias de uma vez.

O X e o Y do campo **Posição** entram por cima dessa base, medidos **no espaço do
corpo** (X = para onde o corpo olha), então giram junto quando o corpo vira. O Z
não passa por aqui: quem cuida da altura é o `ik.lua`.

Só o **"Somente bracos"** ainda tira a base do HMD, e por outro motivo: sem
tronco nem pernas não existe "onde o corpo está", existe onde os ombros têm de
ficar — e isso é debaixo da sua cabeça.

Existiu também uma "trava de cabeça" que empurrava o corpo até o osso da cabeça
encostar no HMD a cada frame — era a causa do corpo piscar, e foi removida.

## Detecção automática dos ossos

Cada jogo nomeia os ossos do seu jeito (`RightHand`, `hand_r`, `Bip01 R Hand`,
`mixamorig:RightHand`…) e o `ik.lua` **descarta o solver em silêncio** quando o
nome configurado não existe na malha — o corpo aparece, mas os braços ficam
parados e nada é dito.

Por isso o `body.lua` confere os nomes contra a malha real assim que o corpo
nasce:

1. Procura o osso da mão de cada lado — primeiro pelos nomes conhecidos, depois
   por qualquer osso que contenha "hand" (ou "wrist") do lado certo, ignorando
   dedos, `ik_`, sockets e afins. Se achar só um lado, espelha o nome para o
   outro.
2. **Antebraço, braço, ombro e espinha saem da própria hierarquia da malha**
   (o pai, o avô, etc.), então não são adivinhados.
3. O osso da cabeça é detectado do mesmo jeito.
4. Se algo mudou, grava em `ik_parameters.json` e reconstrói o corpo uma vez.

Regra importante: **nome que já existe na malha nunca é alterado**. Se você
escolher os ossos na mão pela aba IK Dev Config, a detecção não desfaz.

Foi testada contra as convenções Mixamo/HumanIK (a do Hogwarts), mannequin do
Unreal (`hand_r`), 3ds Max Biped (`Bip01 R Hand`), Mixamo com prefixo
(`mixamorig:`), esqueletos que usam `wrist` no lugar de `hand`, e esqueletos
cheios de ossos-armadilha (`ik_hand_r`, `hand_r_socket`, `weapon_hand_r`).

Dá para desligar em **Corpo VR → "Detectar ossos automaticamente"**, e forçar
uma nova varredura no botão **"Detectar ossos agora"**.

## Como a aba "VR Body" está organizada

Três blocos com título colorido, na ordem em que se usa:

- **Corpo** — o que ligar: corpo VR, mãos do corpo, sombra e "Somente bracos"
  (com a altura dos braços logo abaixo, porque só vale nesse modo);
- **Calibragem** — o que cada pessoa acerta uma vez: altura dos olhos e pernas,
  mais o botão "Restaurar padroes";
- **Acoes** — os botões de recalibrar, reconstruir e mandar coisa para o log.

Entre a Calibragem e as Ações fica o checkbox **"Configuracoes avancadas"**. Os
títulos saem do atalho `head()` no `body.lua`, um `text_colored`; o `configui` lê
a cor na ordem `#BBGGRRAA` (`configui.lua:480`).

## Configurações avançadas

Checkbox **"Configuracoes avancadas"**, perto do fim da aba "VR Body".
Desmarcado (o padrão) ele esconde tudo o que já está no ponto certo, dividido em
quatro blocos:

- **Camera** — câmera na cabeça do corpo, avanço ao olhar para baixo e o quanto
  ela avança;
- **Corpo** — acompanhar a visão (com o ângulo de giro), animar as pernas e
  acompanhar o agachamento;
- **Montaria** — braços pelo IK, tronco acompanhando o headset (com sensibilidade,
  zona morta e limite) e a postura da coluna (endireitar, ajuste fino em graus e
  inclinação lateral);
- **Ossos** — detectar ossos automaticamente.

Junto com eles some a aba **"IK Dev Config"** inteira.

Mexer em qualquer um quebra alguma parte do corpo. O painel do dia a dia fica só
com o que muda de pessoa para pessoa: altura dos olhos, pernas e braços.

Como funciona: os widgets ficam dentro de um `begin_group` com `isHidden`, e o
`drawUI` pula tudo até o `end_group` correspondente (`configui.lua:614`) — um
interruptor para o bloco inteiro, sem precisar dar id a cada linha de texto. A aba
do IK é **criada sempre** (criar depois exigiria inicializar o módulo no meio da
sessão); o modo só a mostra ou esconde, por `configui.hidePanel`. O id do painel é
o nome do arquivo de save dele, `dev/ik_config_dev`.

A chamada que aplica o estado salvo fica **depois do `ik.init`**, que é quem cria
a aba — num `onCreateOrUpdate` ela rodaria durante o `configui.create`, quando o
painel do IK ainda não existe.

## Restaurar padrões

Botão **"Restaurar padroes"**, no fim do bloco "Calibragem". Devolve a aba inteira
à calibragem testada em jogo em 18/08/2026 — não é um chute de fábrica, é o que
estava funcionando.

Os valores moram numa lista só no `body.lua` (`PANEL_DEFAULTS`), que serve para as
duas coisas: é o `initialValue` de cada controle na primeira vez que o perfil roda
e é o que o botão devolve. Dois lugares com a mesma verdade é o defeito que já
custou caro aqui.

O botão **só escreve o que está diferente**. `configui.setValue` dispara os
`onUpdate` sem comparar nada, e um deles é o do "Somente bracos", que mexe no
`hide_body` do rig — e `hide_body = false` cai no `destroyAll()` do `ik.lua:899`,
que é o caminho que empilha cópia órfã. Reescrever um valor que já estava certo
destruiria e recriaria o corpo à toa.

**Cada valor vai dentro do seu próprio `pcall`, e a ordem é fixa** (`RESET_ORDER`).
Esses `onUpdate` fazem coisa de verdade — reconstroem o corpo, mexem no rig,
escondem painel —, e um erro em qualquer um deles abortava o laço inteiro: todos
os campos **depois** dele ficavam sem restaurar, em silêncio, e como `pairs` não
tem ordem definida a vítima mudava de vez em quando. Foi o que aconteceu com a
"Altura dos olhos" em 11/08/2026. Agora um erro isolado não contamina os outros e
sai no `log.txt` com o nome do campo (`Padroes que falharam: ...`).

Há ainda uma segunda passada sobre `PANEL_DEFAULTS` que restaura, por último,
qualquer padrão que não esteja na lista de ordem — para um campo novo não ficar
de fora se alguém esquecer de acrescentá-lo nos dois lugares.

**Não encosta na "Posicao" nem na "Rotacao (Yaw)"**: dono único delas é o painel
IK Dev Config, que grava em `data/ik_parameters.json` (decisão de 09/08/2026).

## Primeira vez que rodar

No menu do UEVR aparecem duas abas novas: **"Corpo VR"** e **"IK Dev Config"**.

Ao ativar, o "Show Hands" do perfil é desligado automaticamente — as mãos
antigas (presas aos controles) e as mãos do corpo não podem coexistir, porque
as duas usam os mesmos IDs de animação e ficariam duplicadas.

O desligamento não depende só do checkbox: o script mexe direto na variável
global `showHands` que o `main.lua` consulta, destrói as mãos que já existirem,
e reconfere a cada 2 segundos. No `log.txt` aparece
`[body] 'Show Hands' desligado`. Para voltar a usar as mãos antigas, desmarque
**"Usar as maos do corpo"** — aí o script religa o "Show Hands" sozinho.

Os dois checkboxes andam juntos: desmarcar **"Ativar corpo VR"** desmarca
**"Usar as maos do corpo"** (as mãos do perfil voltam), e marcar de novo remarca
os dois. Sem corpo não existem mãos do corpo, então deixar o segundo marcado
sozinho só deixaria você sem mão nenhuma.

A cabeça é **sempre** escondida e não tem mais checkbox: em primeira pessoa a
câmera fica dentro dela, e mostrá-la só renderiza o interior do crânio e do
cabelo na sua cara. O osso é encolhido (escala 0,001), não movido — a posição
dele continua valendo, e é dela que sai a câmera atracada à cabeça.

Ordem sugerida de ajuste, na aba **Corpo VR**:

1. **Posição → Z**: sobe/desce o corpo. Se o corpo estiver afundado no chão ou
   flutuando, é esse valor. O perfil já vem em -87, ajustado em jogo.
2. **Posição → X / Y**: encaixa o pescoço embaixo da sua cabeça.
3. **Rotação (Yaw)**: se o corpo estiver virado de lado, gire de 90 em 90.

## Somente braços

Com **"Somente bracos"** marcado, o `ik.lua` esconde o corpo encolhendo o
**esqueleto**: a raiz vai para escala 0,001 e só do ombro em diante volta ao
tamanho normal. Com a raiz encolhida, todos os ossos desabam para a origem do
componente — e é dali que os ombros brotam.

Só que a origem do componente está nos **pés**: o Z que o `ik.lua` escreve todo
frame vale menos a altura da cápsula, porque foi calibrado com o corpo inteiro,
para os pés encostarem no chão. Era isso que deixava os braços lá embaixo, na
altura dos tornozelos, esticados para cima até os controles.

Neste modo, então, a posição inteira (X, Y e Z) sai do **HMD**: os ombros ficam
pendurados na sua cabeça, a pé e montado. Isso torna sem efeito, aqui, o
"Posicao" do IK Dev Config e a conta da cápsula — quem calibra é

- **"Altura dos bracos"** — só uma altura: a distância dos seus olhos até os
  ombros; mais negativo desce os braços. Padrão -15.

A largura continua sendo do `Shoulder Width Scale`, no IK Dev Config.

Duas defesas acompanham esse modo, e as duas existem porque "esconder o corpo",
aqui, é **escala de osso** e não visibilidade:

- o Z automático do `ik.lua` é desligado (`coupling = 2`, o mesmo truque da
  montaria). Com dois donos escrevendo o mesmo Z, um único frame sem a nossa
  correção jogava os braços de volta para os pés — pisca;
- quando o jogo anima os braços (magia, gesto, objeto na mão), o `ik.lua` copia
  a pose inteira da malha do jogo, e a cópia vem em escala 1: o corpo inteiro
  reapareceria pendurado na sua cabeça. O `body.lua` repõe o encolhimento nos
  frames em que isso acontece. No `log.txt` sai
  `Somente bracos: pose do jogo copiada, corpo escondido reposto (N)`, só nas
  cinco primeiras vezes.

Se ainda piscar, o botão **"Diagnostico no log"** lista todas as cópias
`PoseableMesh` penduradas no pawn com a posição de cada uma: mais de uma cópia
é corpo fantasma; uma só é briga de escrita.

Depois, na aba **IK Dev Config** → `Solvers`, para o alinhamento fino das mãos:

- `Rotation` do solver: gira a mão até a palma bater com o controle. Os valores
  que vêm no perfil ((-185, -4, -180) na direita e (1, 13, 211) na esquerda)
  foram ajustados em jogo e testados.
- `Location`: desloca a mão alguns centímetros em relação ao controle.

Tudo que você mexer nessas duas abas é gravado em `data/ik_parameters.json`,
que é a fonte da verdade — o painel "VR Body" só grava por cima quando você
realmente arrasta um controle.

## Pernas animadas e tronco acompanhando a visão

Duas coisas inspiradas no perfil do Silent Hill f:

**Pernas.** O `ik.lua` cria o corpo com `useDefaultPose = true` — pose de
referência, parada — e só mexe nos braços. No SHf o corpo ganha animação
copiando a pose da malha que o jogo anima (disparado por montagem, via
`libs/montage.lua`).

Aqui a cópia é **restrita à subárvore das pernas, da coxa para baixo**. Copiar a
pose inteira animaria também o tronco, a cabeça e principalmente os dedos, que
passariam a seguir a animação do jogo em vez do gatilho/grip do VR.

A conta é a mesma do `animation.copyDescendantTransforms` da lib: lê cada osso na
malha de origem em espaço de componente e reancora no **quadril da cópia**, que
continua parado. Por isso as pernas andam "penduradas" na cintura do corpo VR em
vez de arrastarem o corpo junto.

**Na criatura, perna crua (18/08/2026).** Montado, a cópia é colada na malha do
jogo — mesma transform de mundo, mesmo esqueleto (ver "Montaria de criatura") —,
então o osso lido em espaço de componente já cai exatamente em cima do osso do
jogo. Reancorar ali é que estragava: o quadril da cópia recebia só a *translação*
do jogo e ficava com a rotação da pose de referência, e o `align` girava a perna
inteira por essa diferença. No hipogrifo, onde a pelve do personagem está bem
girada, a perna saía visivelmente deitada. Agora, montado em criatura, o quadril
vem inteiro (rotação inclusive) e as pernas são escritas cruas — a perna é a do
jogo, com o pé no estribo. O **"Ajuste das pernas" do painel também não entra
montado**: ele é calibragem de quem está de pé, e empurrar a perna ali tira o pé
do estribo. A **vassoura ficou de fora** dessa mudança, pela regra de não mexer
no que já funciona lá.

Os ossos são detectados, não fixos: acha o pé de cada lado e sobe a hierarquia
(pé → canela → coxa → quadril), depois pega a coxa e todos os descendentes dela.
Testado nas convenções Mixamo (a do Hogwarts), mannequin do Unreal, 3ds Max
Biped e Mixamo com prefixo — incluindo esqueletos com `ik_foot_r` e ossos de
twist para atrapalhar.

Um detalhe que também veio do SHf: o `pawn_parameters.json` deles esconde o
corpo real com `hideSettingsRenderInMainPass`, e não com `SetVisibility` — de
propósito, para a malha continuar animando enquanto invisível. O perfil do
Hogwarts usa `SetVisibility`, então forçamos
`VisibilityBasedAnimTickOption = AlwaysTickPoseAndRefreshBones` nas malhas de
origem, que dá o mesmo efeito sem mexer na lógica do perfil.

Controle: **"Animar as pernas pelo jogo"** na aba "VR Body".

**Tronco acompanhando a visão.** O corpo é filho do `RootComponent` do pawn,
então gira com o *pawn*. Só que este perfil usa yaw desacoplado: virar a cabeça
não vira o pawn, o corpo ficava para trás e dava o tranco quando o pawn
finalmente alinhava. No SHf isso não aparece porque o `shf.lua` zera o
`InputTurn` e mantém o pawn sempre colado no HMD — não existe yaw desacoplado
lá. Como aqui o desacoplamento é proposital, usamos o `libs/body_yaw.lua` da
própria uevrlib, que é feito exatamente para isso: gira o corpo em direção ao
yaw do HMD com lerp e zona morta.

Controles: **"Corpo acompanha a visao"** e o ângulo em que ele começa a virar
(padrão 40°, ou seja, olhar de lado não arrasta o corpo).

*Corrigido em 05/08/2026 — o corpo virava com o analógico.* Empurrar o
analógico para trás fazia o corpo virar de costas e seguir a direção apontada.
A causa: o yaw do corpo era **lido de volta** do próprio componente a cada
frame. Como o corpo é filho do `RootComponent` e o jogo gira o pawn na direção
do movimento (andar para trás vira o personagem 180°) no tick do motor — que
roda *depois* do nosso callback —, no frame seguinte a rotação lida já vinha
girada pelo pawn. O `bodyYaw.update` interpretava isso como "o corpo está
virado para lá" e ia atrás. Agora o yaw do corpo é uma variável do script, que
nunca é lida do componente: a direção do corpo depende só do headset, e o que o
pawn faz com a própria rotação não entra na conta.

## Câmera atracada à cabeça do corpo

É o único jeito de o corpo ficar debaixo da sua vista, e desde 11/08/2026 não tem
mais alternativa: o "Corpo segue a posicao da cabeca", que fazia o inverso —
levava o corpo até a câmera em vez de a câmera até o corpo —, foi removido,
opção e código. Ele só valia com este modo desmarcado, e este é o modo em uso.

**Se você desmarcar este modo**, o corpo passa a ficar preso à origem do pawn e
volta a aparecer mais para frente ou mais para trás conforme a direção do olhar,
porque a câmera orbita essa origem. Não há mais nada compensando isso.

Por padrão a câmera deste perfil **orbita o pawn** (`main.lua:130`:
`pawnPos + RotateAngleAxis(playerOffset(19,-3,70), yawDaVisão)`), e sobra para o
corpo correr atrás dela. Neste modo a conta se inverte: **a câmera vai até a
cabeça do corpo** e o corpo fica parado em relação ao pawn. O pescoço fica
sempre no lugar certo debaixo da vista, sem perseguição e sem o vaivém da
órbita.

A **rotação continua sendo do headset** — o script mexe só na posição da
câmera. O yaw desacoplado que o `main.lua` escreve em `rotation.y` também
continua valendo. O deslocamento roomscale do HMD é somado pelo UEVR *depois*
deste callback, então andar e se inclinar no espaço real continuam funcionando:
o que muda é a base sobre a qual esse deslocamento é aplicado.

Controles, na aba "VR Body":

- **"Camera na cabeca do corpo"** — liga o modo.
- **"Altura dos olhos"** — só isso: uma altura. Padrão 5.

  É **um só para tudo**: a pé, na vassoura e na criatura. Existiu um segundo
  campo, só para criatura, e foi removido a pedido do Renan — dois campos para a
  mesma coisa é o defeito que já custou caro aqui. Se a vista montado incomodar,
  o lugar de mexer é a **postura da cintura**, que é o que desloca a cabeça.

  **O X e o Y saíram em 11/08/2026, a pedido do Renan.** Eles eram girados pela
  direção do olhar, e era isso que fazia a câmera percorrer um círculo em volta
  do osso toda vez que você virava a cabeça — ou girava no analógico, com o yaw
  desacoplado, sem mexer a cabeça de verdade. Era a queixa "o olhar fica
  esquisito, a configuração vira obsoleta quando ando e viro", e ela **morreu
  junto com os dois campos**: sem nada para girar, não há círculo.

  Antes disso houve ainda uma tentativa de salvar o X/Y medindo-os na frente do
  corpo e limitando o empurrão a uma janela de 120° (10/08/2026). Ficou bagunçado
  e foi removida inteira. A lição ficou: o ajuste da câmera é o lugar errado para
  uma janela angular. Quem leva a vista para a frente hoje é o "olhar para
  baixo", logo abaixo — horizontal, medido na frente do corpo e zerado quando
  você olha para trás.

**A altura vem da cabeça do corpo; o horizontal vem do pawn** (a pé)**.** Prender o X/Y da
câmera ao osso da cabeça fazia o mundo deslizar, porque duas somas de arco
entravam na conta — as duas dependendo do giro do *corpo*, que gira com atraso
(zona morta + lerp do `body_yaw`):

1. o osso da cabeça fica fora do eixo de rotação do corpo, então quando o corpo
   gira o osso descreve um arco de alguns centímetros;
2. pior, o `updateBodyTransform` gira o `meshLocationOffset` pelo ângulo entre o
   corpo e o pawn — é o que mantém "um pouco para trás" atrás do pescoço quando
   o corpo vira. Com o X do painel em -6,5 cm e yaw desacoplado, esse ângulo
   varre 360°: a origem do corpo percorre um círculo de 6,5 cm de raio, e a
   câmera ia junto.

Nada disso é movimento do jogador — é o corpo se acomodando —, e virava deslize
contínuo da imagem, muito visível na vassoura, onde se olha em volta o tempo
todo. Ancorando o horizontal no pawn, o giro do corpo deixa de mexer na câmera.
O Z continua vindo da cabeça, que é o que faz o agachamento descer a vista, e
altura não sofre com rotação em torno do eixo vertical.

Por isso, com este modo ligado, **deixe X e Y de "Posição" perto de zero**: eles
giram junto com o corpo e fazem o corpo bambear em volta da sua vista quando
ele vira. Agora isso mexe só no corpo, não na imagem, mas continua sendo
movimento à toa.

**O tick guarda uma altura relativa ao pawn; o callback compõe a posição.** Duas
armadilhas já pagas, nesta ordem:

1. **Não usar `view_index == 0` como "primeiro olho".** Hogwarts é UE4, e lá o
   índice vem do `EStereoscopicPass`: `eSSP_LEFT_EYE = 1`, `eSSP_RIGHT_EYE = 2`
   — nunca 0. Uma versão calculava a câmera só quando `view_index` era 0, e a
   conta rodou uma única vez: a câmera **congelou** num ponto do mundo e o
   personagem saiu andando. Hoje não há teste de olho nenhum; o callback
   recalcula sempre e os dois olhos batem porque leem o mesmo estado dentro do
   quadro.
2. **Não guardar posição em mundo no tick.** O callback da câmera roda depois do
   tick do motor, ou seja, depois de o personagem já ter andado naquele quadro.
   Posição em mundo calculada no tick chega atrasada, e o corpo — filho do
   `RootComponent`, portanto já na posição nova — aparecia **adiantado** em
   relação à câmera. O desvio é velocidade × tempo de quadro: invisível parado,
   visível andando, escancarado na vassoura. Altura relativa não envelhece,
   porque é somada à posição do pawn do próprio instante.

É o mesmo padrão do perfil do Silent Hill f (`melee.lua:456`), que prende a
câmera no corpo lendo a posição do pawn **dentro do callback** e somando um
deslocamento fixo.

Não foi assim de primeira, e o erro vale registrar. A primeira versão calculava
dentro do próprio callback (que roda uma vez por olho) e usava `view_index == 0`
para não refazer a conta no segundo olho. Só que Hogwarts Legacy é UE4, e lá o
`view_index` vem do `EStereoscopicPass`: `eSSP_LEFT_EYE = 1`,
`eSSP_RIGHT_EYE = 2` — **nunca 0**. A condição só passava pelo outro braço,
`headCameraLocation == nil`, que é verdade uma única vez: a câmera era calculada
no primeiro frame e **congelava** naquele ponto do mundo, com o personagem
saindo andando e deixando a câmera para trás. Calcular no tick elimina a
dependência de como o motor numera os olhos e garante que os dois recebem
exatamente a mesma posição (valor diferente por olho desalinha o estéreo).

O registro do callback sai de um `uevrUtils.delay`, não do corpo do arquivo: o
`main.lua` registra o dele dentro do `UEVRReady`, durante o carregamento dos
scripts, e quem registra primeiro é sobrescrito por quem vem depois.

### Na montaria a âncora é outra

Tudo o que está acima — horizontal do pawn, altura da cabeça — descreve **quem
está em pé**. Montado, as duas premissas caem:

- a origem do pawn deixa de ficar debaixo da cabeça, porque a vassoura **deita**
  o personagem sobre ela (e ainda inclina, com pitch e roll);
- no hipogrifo o personagem vira o `RiderCharacter`, que é **outro ator** — o
  `main.lua:126` já lida com isso na câmera dele, via `mounts.getMountPawn`.

O sintoma é exatamente esse: a pé a câmera fica no pescoço, montado ela vai
parar noutro lugar, sem relação com a cabeça.

Montado, então, a câmera é atracada **direto no osso da cabeça, nos três
eixos** (`applyMountHeadCamera`). O cuidado que obrigava a tirar o X/Y do pawn
some junto com o problema: com **"Na montaria, corpo copia a malha do jogo"**
ligado o corpo não tem mais yaw próprio (o `bodyYawState` é zerado e ele herda a
rotação inteira da malha), logo não há arco para fazer o mundo deslizar. Por
isso o modo só entra quando essa opção está ligada — desligada, o corpo volta a
ficar em pé preso ao pawn e é a conta de a pé que descreve onde ele está.

A posição do osso é lida **dentro do callback**, não no tick: o callback roda
depois do tick do motor, e na vassoura um quadro de atraso é justamente o que
aparecia como corpo adiantado em relação à câmera. Ler a cabeça da **cópia**
(e não da malha do jogo) ainda dá o "Ajuste na montaria" de graça, porque ele já
está embutido na posição em que a cópia foi posta.

O ajuste dos olhos é **um só**, o mesmo a pé, na vassoura e na criatura.

Se o osso não puder ser lido, o script **não escreve nada** e vale a câmera de
montaria do `main.lua` (o comportamento antigo). Congelar a câmera num ponto do
mundo seria bem pior.

## Olhar para baixo leva a vista para a frente (11/08/2026)

Em VR, para enxergar o próprio corpo você não gira só os olhos: você se inclina
um pouco à frente. Aqui isso é reproduzido movendo **a câmera**, e nada mais.
Quanto mais para baixo você olha, mais a vista avança; olhando reto, avanço
nenhum. Mora dentro do `applyHeadCamera` (seção 3), junto do "Ajuste dos olhos".

Controles, na aba "VR Body", em **"Configuracoes avancadas"**:

- **"Camera avanca ao olhar para baixo"** — liga o efeito. Nasce
  marcado. Precisa da **"Camera na cabeca do corpo"** marcada também.
- **"Quanto avanca"** (cm, padrão 16,677) — o avanço olhando reto para baixo.
  Entre a zona morta e os 90° o valor sobe em rampa, então o número do painel é
  uma distância de verdade, não um ganho abstrato.

### O corpo não se mexe, de propósito

Houve antes uma versão que inclinava de verdade o peito e o pescoço da cópia
(60/40) e descontava na câmera o deslocamento que isso dava no osso da cabeça.
Foi **removida inteira** a pedido do Renan em 11/08/2026: não funcionou bem com a
"Camera na cabeca do corpo" — que é justamente o modo em uso — e não era
isso que ele queria. Como aqui nenhum osso é tocado, não há nada que possa brigar
com o IK dos braços, com a cintura ou com as escalas de esconder a cabeça.

### A janela de 120°

O efeito só existe olhando dentro de **60° para cada lado da frente do corpo**.
Olhando para trás — por cima do ombro — ele é zero, senão a vista sairia andando
para um lugar que não tem nada a ver com o olhar. Entre 45° e 60° o fator cai por
cosseno; corte seco seria a câmera saltando os centímetros de uma vez, no meio de
um giro de cabeça. Há ainda uma zona morta de 10° de pitch: olhar quase reto não
move nada.

### O avanço é na frente do CORPO, não na direção do olhar

Girar um deslocamento pela visão faz a câmera percorrer um círculo em volta do
ponto de origem toda vez que você vira a cabeça — ou gira no analógico, com o yaw
desacoplado, sem mexer a cabeça de verdade. É a queixa "o olhar fica esquisito"
que o "Ajuste dos olhos" ainda tem, e não vale a pena repeti-la aqui. Medido na
frente do corpo, virar a cabeça dentro da janela não move nada; só olhar para
baixo move.

### Yaw contra o corpo, pitch contra o horizonte

Os dois ângulos saem de `getGazeInBodySpace` e vêm de fontes diferentes **de
propósito**:

- **Yaw relativo ao corpo** — a janela de 120° é sobre estar de frente para o
  próprio corpo, então ela tem de acompanhar para onde o boneco aponta. O yaw sai
  da *sombra no chão* da frente do esqueleto, não do peito dele, para valer igual
  com o personagem reclinado ou deitado.
- **Pitch contra o horizonte** — o pescoço de quem está jogando está na vertical
  na sala, independentemente do que o jogo faz com o boneco. "Olhar para baixo" é
  olhar para baixo, montado ou não.

**O defeito do hipogrifo (11/08/2026).** A primeira versão media os dois ângulos
no plano do personagem, e no hipogrifo isso saiu pela culatra: montado, a cópia
recebe a rotação da malha do jogo e o personagem vai **reclinado para trás**. Com
o peito inclinado, olhar reto para a frente no mundo já contava como "olhar bem
para baixo" em relação ao peito — o empurrão ligava sozinho e ficava ligado, e a
vista sentava para a frente o tempo todo. Não aparecia a pé porque a pé o peito
está na vertical e os dois planos coincidem. Sintoma do Renan: "no hipogrifo os
olhos tão muito pra frente, só acontece isso no hipogrifo".

Pelo mesmo motivo o **avanço é sempre horizontal**: a direção é a frente do corpo
achatada no chão. Antes saía na frente crua do personagem, o que montado mandava
a vista para o chão ou para o céu junto com a inclinação do bicho.

A conta é toda por vetor, nunca pelo `.Yaw` ou `.Pitch` de um rotator.
Montado, a cópia recebe a rotação da malha do jogo com pitch e roll grandes, e
perto de 90° de pitch o yaw de um rotator se confunde com o roll — foi essa
leitura errada que fez um ajuste anterior "não alterar nada na vassoura". Pegam-se
os eixos do componente em mundo, giram-se pelo Mesh Rotation Offset para chegar
aos eixos do esqueleto, e projeta-se neles a frente do HMD.

### Sem suavização, e por quê

Não há lerp nenhum: a conta já é contínua nas duas bordas (o cosseno da janela e
a rampa do pitch), e **amortecer o que alimenta a câmera é atraso na vista, não
suavidade** — foi a lição do lerp do quadril, tirado em 10/08/2026. Tudo é
calculado dentro do callback, no mesmo instante em que a posição é escrita, e os
dois olhos recebem o mesmo valor porque leem o mesmo estado.

Ler a **rotação** do HMD aqui não é realimentação: o mod só escreve posição de
câmera. E o efeito exige a câmera na cabeça justamente porque, sem ela, o "Corpo
segue a posicao da cabeca" persegue o HMD — empurrar a vista levaria o corpo
junto.

O botão **"Diagnostico no log"** traz a linha `olhar:` com o yaw e o pitch já
relativos ao corpo e o empurrão em centímetros. Tudo zero com um yaw grande é o
esperado — é a janela agindo.

## Montaria de criatura: três coisas, todas trancadas no caso

As três só existem enquanto você está montado. A pé o código roda igualzinho ao
de antes delas — o diff contra o perfil de referência **não tem uma única linha
removida ou alterada**, só blocos novos, e todos começam por uma condição de
montaria.

### 1. A malha é a do personagem, não a da criatura

Montado numa criatura (hipogrifo, graphorn) o pawn controlado passa a ser **a
criatura**, e o bruxo vira `pawn:GetMountComponent().RiderCharacter` — é o que
`mounts.getMountPawn` devolve, e por isso o `main.lua` o usa em tudo que fala do
personagem.

Isso importa porque o corpo é recriado sozinho pelo temporizador do `ik.lua`
(`ik.lua:2535`, 1× por segundo enquanto não existir). Em 06/08/2026 essa
recriação caiu no meio de um voo de hipogrifo, a lista de malhas veio de
`pawn.Mesh`, e **o corpo VR foi montado a partir da malha da criatura** — 142
ossos, esqueleto de asas. Nada disso dá erro no log: o corpo simplesmente vira o
bicho.

Duas linhas de defesa:

- `getCustomIKComponent` troca a malha base pela do `RiderCharacter`
  **só quando `mounts.isWalking()` é falso**;
- a **detecção automática de ossos não roda montado**. Ela grava em
  `data/ik_parameters.json` (`setConfigParameter` com `persist = true`), e foi
  isso que escreveu `wing_elbow_left`, `wing_wrist_right` e
  `wing_clavicle_left` por cima dos ossos e dos offsets ajustados em jogo.

No log, o marco é `Montado: corpo criado a partir da malha do personagem`.

### 2. Braços pelo IK (era o Z do `ik.lua`, não o solver)

O tick do `ik.lua` (`ik.lua:417`) começa escrevendo, todo frame,
`RelativeLocation.Z = offset + (offset + CapsuleHalfHeight)` e **só depois**
resolve os braços. Montado numa criatura o pawn é a criatura, e a cápsula dela é
enorme: a cópia era atirada para longe em Z bem no instante em que os solvers
convertem a posição dos controles para o espaço do componente. O alvo caía fora
do alcance do braço, o solver saturava, e a mão congelava numa pose só. A imagem
parecia certa porque a posição era corrigida logo depois, no tick de prioridade
-10.

Com `coupling == 2` o `ik.lua` não toca no Z (`ik.lua:418`). O script troca esse
campo na instância do rig enquanto estiver montado e devolve o original ao
desmontar — e a devolução compara antes de escrever, então **a pé é um no-op**.
Só entra com "corpo copia a malha do jogo" ligado, que é quem cuida da posição
montado.

Controle: **"Bracos pelo IK"**.

### 3. Tronco acompanhando o headset

Montado, o corpo não tem yaw próprio — herda a rotação da malha do jogo, que
aponta para onde a criatura aponta. Olhar para o lado deixava você de perfil
dentro do próprio corpo.

O script gira **um osso**, com zona morta, sensibilidade e limite. Nada muda de
lugar: nem você, nem a criatura, nem a posição do corpo.

**Por que na cintura e não no quadril.** As pernas penduram no quadril: girá-lo
levaria as duas junto e tiraria os pés do estribo. Girando o osso logo acima
dele — o primeiro da coluna, achado por hierarquia (filho do quadril que não é
perna) — sobe tudo o que tem que subir (tronco, ombros, braços, pescoço, cabeça)
e as pernas ficam onde a animação as pôs. Muda só onde a torção começa.

A rotação é sempre calculada a partir da **pose de referência capturada na
criação**, nunca do que está no osso: o osso guarda o que nós escrevemos no
frame anterior, e realimentar isso faria a torção crescer sozinha (é a mesma
armadilha do `bodyYawState`). Ao desmontar, a cintura é devolvida à pose de
referência **uma vez** — sem isso ela guardaria a última torção para sempre,
porque a pé ninguém mais escreve nesse osso.

A vassoura fica de fora: lá a regra é não modificar nada.

Controles: **"Tronco acompanha o headset"**, com Sensibilidade,
ângulo de partida e limite.

> **Interação a vigiar:** com a câmera na cabeça ligada, torcer o tronco move o
> osso da cabeça alguns centímetros, e a câmera vai junto. Se der sensação de
> mundo deslizando ao olhar em volta, baixe a Sensibilidade ou desligue um dos
> dois.

### Endireitar a coluna (09/08/2026)

No hipogrifo o tronco aparece deitado para trás. **A reclinada não vem de osso
nenhum:** do peito para cima a cópia está em pose de referência, que é ereta. Ela
vem da malha inteira — montado, o corpo copia a rotação da malha do jogo com
pitch e roll inclusive ("corpo copia a malha", seção da montaria), e essa rotação
é a do personagem sentado na criatura. Componente inclinado, tronco vertical
dentro dele: o resultado é um tronco inclinado.

Por isso o ajuste é feito **na cintura**, e não desinclinando o componente:
mexer no componente levaria as pernas junto e tiraria os pés do estribo. É o
mesmo motivo do giro de yaw, logo acima.

A conta é fechada, não é perseguição. Sabemos a rotação do componente e sabemos
qual seria ela nivelada (mesmo yaw, inclinação reduzida); a cintura recebe a
diferença entre as duas, convertida para o espaço do componente com
`MakeTransform` / `InvertTransform` / `ComposeTransforms` — transform e não
rotator porque **o inverso de um rotator não é o rotator negado**.

**Nos eixos do personagem, não nos da malha (18/08/2026).** A primeira versão
escalava direto o `Pitch` e o `Roll` do `K2_GetComponentRotation`. Só que o
`mesh_rotation_offset` do rig está em Yaw -90: nesse rotator o **pitch é a
inclinação lateral** e o **roll é a da frente**. Na prática, "Endireitar a coluna"
endireitava o lado e deixava o personagem deitado para a frente, e a coluna só
ficava reta ligando junto o "Endireitar a inclinacao lateral" — que era quem
estava mexendo na frente. Agora a conta tira o yaw do mundo, conjuga pelo
`rigMeshYaw()` para cair nos eixos do personagem, escala frente e lado lá dentro,
e volta (`composeRot` em `body.lua`). Com o controle em 0 a rotação reconstruída
é idêntica à do jogo, então "0 = pose do jogo" continua valendo ao pé da letra.

Controles, em **"Configuracoes avancadas"**:

- **"Endireitar a coluna"** (0 a 1). 0 = pose original do jogo e o código escreve
  exatamente o que escrevia antes; 1 = tronco na vertical. Sozinho ele tira a
  inclinação **para a frente e para trás**.
- **"Endireitar a inclinacao lateral"** — soma a inclinação **de lado** ao que o
  controle acima já faz. Desligue para continuar deitando junto com a criatura
  nas curvas.
- **"Ajuste fino da coluna (graus)"** — inclinação a mais, positivo para trás. Vale sozinho,
  com o controle de cima em 0. Ele é aplicado em volta do eixo esquerda-direita
  **do personagem**, e essa direção sai de `yaw da malha − "Rotacao (Yaw)"`: o
  esqueleto não aponta para a frente do componente, e o campo do painel é
  justamente a diferença entre um e outro.

**A cabeça acompanha a coluna, e não pode ser diferente.** A primeira versão
tentava o contrário: como a câmera montado fica pendurada no osso da cabeça, ela
reescrevia esse osso na posição que teria **sem** a correção, para a vista não se
mexer ao endireitar. Em jogo isso deu o oposto do pretendido — a coluna ia para a
frente, a cabeça ficava para trás, o pescoço esticava visivelmente ("chiclete") e
a vista ficava descolada do corpo. Foi removido. A cabeça é osso da coluna, sobe
com ela, e a câmera sobe junto.

O efeito colateral é que mexer no controle desloca a sua vista para cima e para a
frente. Quem corrige isso é o **"Ajuste dos olhos na montaria"**, que existe
exatamente para isso — reajuste ele depois de escolher o valor da coluna.

Se o "Diagnostico no log" mostrar **pitch e roll da malha de origem perto de
zero** com o corpo visivelmente deitado, a inclinação vem de outro lugar e quem
resolve é o "Ajuste fino", não o controle de 0 a 1.

## Altura: agachar no jogo e agachar de verdade

Dois problemas diferentes com o mesmo sintoma — **o corpo parece subir quando
você abaixa**.

**Agachar no jogo.** A altura do corpo é inteiramente do `ik.lua`
(`ik.lua:417`: `RelativeLocation.Z = off + (off + CapsuleHalfHeight)`). Quem
trata o agachamento é só a altura do quadril, abaixo.

### O corpo entrando no chão (09/08/2026) — em aberto

A conta acima só fecha com a cápsula na altura de **pé**: ali `off` vale
`-CapsuleHalfHeight` e o resultado dá exatamente o pé da cápsula — é de onde saiu
o `-98.5`. Quando a cápsula encolhe (agachar, furtivo), o motor abaixa o root
junto para o pé da cápsula não sair do lugar; a conta não sabe disso e desce mais
uma vez pelo `H` menor. **O corpo afunda o dobro do que a cápsula encolheu.**

Trocar essa conta pelo Z da malha do jogo (`srcLoc.Z - rootZ + off`) foi tentado
e **revertido no mesmo dia**. A conta em si estava certa, mas rebase o
significado do Z de "Posicao": o valor calibrado (`-98.5`) passa a valer `~0`. E
com o Z em 0 apareceu o defeito de verdade — **dois corpos**, um deles 88 cm no
alto.

> **Dois rigs vivos.** O `ik.lua` guarda os rigs numa lista (`ik.lua:24`,
> `_rigInstances`) e o `body.lua` rastreia só o que veio no callback de criação —
> `getCurrentMesh` devolve o do **último**. O log mostra `Corpo criado com 8
> malha(s)` e, no meio, um `Corpo criado com 1 malha(s)`: o rig não rastreado
> continua sendo posicionado **só** pela fórmula da cápsula.
>
> Com o Z em `-98.5` os dois caíam praticamente no mesmo lugar (`-109` contra
> `-98.5`) e o duplicado passava por z-fighting — **o "piscando"**. Com o Z em 0
> a fórmula manda o duplicado para `+88` e ele fica visível.
>
> Enquanto houver mais de um rig, mexer na altura afasta os dois. **A ordem certa
> é garantir um rig só primeiro.** O botão "Diagnostico no log" imprime
> `rig rastreado x rig do ik.lua` exatamente para isso.

> **Tentativa removida — não repetir.** Houve aqui uma correção que perseguia a
> malha do jogo: media `malhaDeOrigemZ - rootZ - ikZ` e devolvia ao corpo o que
> mudasse nessa distância, para manter os pés plantados quando a cápsula
> encolhesse. A premissa era que a malha de origem só se mexe em relação à
> cápsula quando algo de fato mudou — e é **falsa**: a UE desloca a malha em
> relação à cápsula para suavizar degrau e subida. O número oscilava sozinho
> justamente ao subir, e isso ia direto para a altura do corpo; recalibrar só
> reposicionava a linha de base, sem tirar a oscilação.
>
> Note que isto é diferente da tentativa revertida acima: aquela **atribuía** a
> altura da malha (sem linha de base, sem acúmulo) e caiu por causa dos dois
> rigs; esta **perseguia** uma diferença contra uma linha de base capturada, e
> caiu sozinha, por acumular e oscilar. Quando os rigs estiverem resolvidos, é a
> atribuição que vale a pena retomar — a perseguição, não.

Quem faz o corpo realmente *agachar* é a **altura do quadril**. Antes o quadril
era só âncora e ficava parado na altura de pé: agachar dobrava as pernas mas
levantava os pés do chão, e o tronco (com a câmera presa nele) continuava lá em
cima. Agora ele desce, e o tronco vem junto porque é filho dele.

**Só a altura, e só quando é agachamento de verdade.** A primeira tentativa
copiou a translação inteira do quadril e trouxe junto o balanço do andar — o
quadril da animação sobe, desce e joga para os lados a cada passo, e o tronco
inteiro balançava junto, indo direto para o olho por causa da câmera na cabeça.
A separação é por amplitude, que aqui é limpa: o balanço fica na casa dos 2-4 cm
e um agachamento passa de 30, então abaixo de 8 cm (`HIP_DROP_DEADZONE`) não é
agachamento, é balanço, e vira zero. X e Y do quadril vêm sempre da pose de
referência, e a rotação fica intocada — girar o quadril giraria o tronco inteiro
e brigaria com o "Corpo acompanha a visao".

As pernas continuam reancoradas no quadril, então acompanham a descida sem
rasgo na cintura. Parado ou agachado, a altura do quadril bate com a da animação
e os pés caem no lugar; andando, sobra a diferença do balanço, que é o
deslizezinho de pé que este método sempre teve.

A posição do quadril é sempre reconstruída a partir do valor capturado na
criação do corpo (`referenceHip`), nunca do que está no osso: o osso guarda o
que o script escreveu no frame anterior, e realimentar isso faria a altura
derivar sozinha.

O agachamento é medido contra a altura do quadril **na malha animada com o
personagem em pé** (`standingSourceHipZ`, capturada no primeiro frame), e não
contra a pose de referência. As duas não coincidem: a pose de referência é a
bind pose crua, de perna reta, e a pose animada de "em pé" tem sempre um joelho
mole. Essa diferença é livre — pode ser para cima ou para baixo — e entrava
inteira na conta. Quando a bind pose era a mais baixa das duas, ela comia a
folga dos 8 cm e o agachamento quase não passava: o personagem abaixava e o
corpo (com a câmera na cabeça) mal descia.

Controle: **"Corpo acompanha o agachamento"**.

**Agachar de verdade, no espaço real.** A base horizontal que vinha do HMD (o
antigo "Corpo segue a posicao da cabeca") sempre tratou só X e Y — o Z nunca
seguiu o HMD. O corpo ficava de pé enquanto
você abaixava e o tronco subia na sua frente. Agora a altura do HMD abaixo da
linha de referência desce o corpo junto, com 5 cm de folga e só para baixo
(ficar na ponta dos pés não levanta o corpo, o que deixaria os pés no ar).

Isto **não** é a "trava de cabeça" que fazia o corpo piscar. Aquela empurrava o
corpo até o osso da cabeça encostar no HMD a cada frame, realimentando a
própria medida. Aqui a conta é aberta: HMD contra uma linha de referência fixa,
capturada quando o corpo nasce, e nada que o script escreveu entra na medida.

Controle: **"Corpo acompanha voce agachando de verdade"**, e o botão
**"Recalibrar altura"** (fique de pé, na altura em que você joga, e clique) para
recapturar as duas linhas de referência.

Com a câmera atracada à cabeça ligada, o agachamento **real** é descontado da
posição da câmera: o corpo já desceu esse tanto e o UEVR soma o deslocamento
roomscale do HMD depois, então sem o desconto a câmera desceria duas vezes. O
agachamento do **jogo** não entra nessa conta — esse o UEVR não tem como somar,
e tem que vir mesmo da cabeça do corpo.

## Diagnóstico: por que o log.txt estava vazio

O `uevr_utils` nasce com `logToFile = false` (`uevr_utils.lua:1802`), e o
`print()` cru do Lua vai só para a janela de console do UEVR. Por isso procurar
`[body]` no `log.txt` não devolvia nada — nem o `"UEVR is now ready"` do
`main.lua` está lá. O `body.lua` agora chama `uevrUtils.setLogToFile(true)`.
Isso não enche o log: o filtro de nível continua valendo e o padrão é `Error`,
então passam só erros de verdade e os marcos do corpo (criação, pernas
detectadas, câmera registrada), que vão como `Error` de propósito.

O botão **"Diagnostico no log"** despeja o estado que interessa quando a câmera
ou a altura estão erradas: posição do pawn e `CapsuleHalfHeight`, HMD, malha de
origem, corpo (relativo e mundo), osso da cabeça, as duas linhas de referência
de altura e o quadril nas duas malhas.

## A varinha volta junto com o corpo

Reconstruir o corpo também reconstrói a varinha. Ela é presa na criação — ao
controle (`wand.connectToController`) ou ao socket da mão
(`wand.connectToSocket`) — e esse vínculo não sobrevive ao rig novo: a varinha
ficava para trás, presa a uma mão que não existe mais.

O script só **desconecta**. Quem reconecta é o poll do próprio `main.lua`
(linha 1009: `if isFP and not isWandDisabled and not isInCinematic and not
wand.isConnected() then connectWand()`), que já monta a varinha no estado certo
com o corpo novo no lugar. Refazer a conexão daqui duplicaria essa lógica e
correria o risco de rodar antes de o corpo existir.

Vale para todos os caminhos, não só o botão "Reconstruir corpo": troca de
malhas, redetecção de ossos e a criação automática no começo do nível.

## Roupa nova: o corpo é refeito ao mexer no equipamento

O corpo VR é uma **cópia** das malhas do personagem, tirada quando o rig nasce.
Trocar de roupa troca as malhas do personagem, não a cópia — a túnica nova
aparecia em todo mundo menos em você.

Por isso o script refaz o corpo quando a **tela de equipamento** (aba 1 do Guia
de Campo) abre e quando ela fecha. É a mesma saída que o perfil já usava para as
luvas (`main.lua`, no `ExitFieldGuideWithReason`: *"always updating hands here
until we can find a specific call for glove changes"*).

**Não há opção no painel** — é automático. A tela é reconhecida pelo UIManager
do jogo, do mesmo jeito que o `inMenuMode` do `main.lua`, e só a aba do
equipamento conta: abrir o mapa (aba 6) ou uma conversa não refaz nada. No
`log.txt` saem as linhas `Equipamento aberto/fechado: refazendo o corpo`.

O antigo **"Refazer o corpo ao montar e ao desmontar"** foi **removido**
(opção e código). O que segura a montaria não era ele, e sim o que continua no
arquivo: o `updateRigPawn` (o `ik.lua` passa a ler raiz e cápsula do
personagem, não da criatura), o `coupling = 2` e o giro/postura da cintura. O
personagem montado é o mesmo ator, com as mesmas malhas, então a cópia continua
valendo.

## Limitações (são do método, não do script)

- **"Somente braços"** continua disponível na aba "VR Body", caso você prefira
  esconder tronco e pernas. Com esse modo ligado, a animação do corpo não faz
  diferença (não sobra corpo para animar).
- O corpo é escondido automaticamente em terceira pessoa e em cinemática,
  porque nesses casos o jogo mostra o personagem de verdade. Na **montaria**
  (vassoura, hipogrifo) ele **não** some: a opção "Esconder o corpo na montaria"
  foi removida (opção e código). Ela nunca ganhava em caso nenhum — como o
  perfil já esconde o jogador em primeira pessoa, ligá-la deixava você sem corpo
  nenhum em cima da vassoura, e todo o trabalho da montaria (copiar a malha do
  jogo, o giro e a postura da cintura) existe justamente para o contrário.

## O estado de "esconder" é filtrado — use `isBodyHidden()`

`shouldHideBody()` lê `pawn.InCinematic`, que **entra e sai** durante certas
animações. O `ik.lua` já sabia disso: ele pergunta a cada 200 ms e o script só
esconde depois de duas leituras seguidas pedindo (voltar a aparecer continua
imediato).

As funções das pernas, da posição do corpo e da câmera, porém, chamavam
`shouldHideBody()` **cru, a cada frame**, sem esse filtro. O resultado era o
corpo parando e voltando de um frame para o outro, e — com a câmera na cabeça —
a câmera saltando entre o osso da cabeça e a câmera normal do perfil. Era a
"flicada", e mais forte justamente com a câmera na cabeça ligada.

Regra: dentro deste arquivo, só o callback `is_hands_hidden` usa
`shouldHideBody()`. Todo o resto usa `isBodyHidden()`, que devolve o estado já
filtrado.

## Corpo sumindo / piscando

A causa era a trava de cabeça, que reposicionava o corpo a cada frame — **foi
removida**. Nada no script mexe mais na transform do corpo.

Duas outras proteções ficaram, porque são baratas e o sintoma seria o mesmo:

1. **Oscilação do estado de esconder.** O `ik.lua` pergunta a cada 200 ms se o
   corpo deve sumir, e o `pawn.InCinematic` entra e sai durante certas
   animações. Agora exige duas leituras seguidas pedindo para esconder (voltar
   a aparecer continua imediato).
2. **Flicker do próprio UEVR em Native Stereo.** Componentes criados por Lua
   piscam nesse modo de renderização — é para isso que existe o painel
   **"Flicker Fixer"**, que o perfil já usa nas mãos. Está configurado em
   Delay = 2 s, Duration = 0.62 s.

## Se algo der errado

- **Corpo não aparece**: veja o `log.txt` do perfil, procure por `[body]`. Se
  aparecer "Pawn.Mesh indisponível", o corpo tentou nascer antes do jogo estar
  pronto — ele tenta de novo a cada segundo.
- **Braços parados**: procure `[body] Solver ... usando X -> Y -> Z` no
  `log.txt` para ver que ossos foram escolhidos. Se aparecer "Não achei o osso
  da mão", clique em **"Listar ossos no log"** e escolha na mão pelos combos da
  aba IK Dev Config.
- **Braços torcidos**: os ossos estão certos, o que está errado é o alinhamento
  — ajuste `Rotation` do solver na aba IK Dev Config.
- **Roupa/malha estranha aparecendo**: troque "Malhas" para **"Somente
  Pawn.Mesh"** e clique em "Reconstruir corpo".
- **Voltar ao perfil antigo**: apague a pasta `HogwartsLegacy` e copie de volta
  a que está em `Desktop\HOGWARTS LEGACY\backups\`.

## Mapa do Field Guide em branco (19/08/2026)

Sintoma: abrir o mapa e não ver nem o desenho do mapa nem o bonequinho do
personagem — só a moldura da interface.

Causa: o perfil já sabia que mexer na câmera do VR quebra essas duas telas. O
`main.lua` desliga o `enableVRCameraOffset` na aba do mapa (`CurrentTabIndex`
6, com 1,3 s de atraso) e na tela de equipamento (aba 1, "dont offset the
camera so that the avatar appears"). A **câmera atracada à cabeça** do
`body.lua` é um segundo callback de `on_early_calculate_stereo_view_offset` e
ignorava esse desligamento: continuava escrevendo a posição da câmera no osso
da cabeça, no mundo, enquanto o jogo tentava mostrar o mapa.

Fix: `main.lua` expõe `isVRCameraOffsetEnabled()` (só devolve o flag) e o
`headCameraActive()` do `body.lua` devolve false quando ela é false. Um dono
por valor: quem decide se a câmera pode ser mexida continua sendo o `main.lua`,
e o corpo apenas obedece — por isso o fix vale também para a tela de
equipamento e para qualquer tela que venha a desligar o offset.

Teste de bissecção se voltar a acontecer: desmarque "Camera na cabeca do corpo"
no painel "VR Body" e abra o mapa. Se ainda assim não desenhar, a causa não é o
corpo, é renderização do UEVR (modo de renderização / Native Stereo Fix).

## Interação que não pega o objeto à sua frente (19/08/2026)

**A mira do jogo sai da VARINHA, não do olhar** (descoberto pelo Renan em jogo): o
`main.lua` chama `wand.getWandTargetLocationAndDirection()` todo tick — ponta da
varinha + `GetUpVector` — e é isso que alimenta o alvo e o plugin SpellCaster
(`helpers/wand.lua:257`). Para interagir, é a mão que aponta.

O que já foi **descartado por medição** neste caso, para não se repetir a caçada:
- **Câmera na cabeça**: `vista x camera do jogo: horizontal=0,5 cm` — a vista está
  praticamente em cima da câmera do jogo.
- **Colisão das cópias**: o sintoma continuou depois de desligada (ela continua
  desligada, que é o certo para uma cópia visual).
- **Pitch da rotação de controle**: fica em `0,0` sempre (Decoupled Pitch do UEVR,
  e o eixo vertical do analógico direito está remapeado para pular/rolar em
  `helpers/input.lua`) — mas isso não é o que escolhe o alvo, então **não é para
  "corrigir"**. Chegou a existir um bloco escrevendo o pitch do HMD em
  `SetControlRotation`; foi removido quando a mira pela varinha apareceu.
- **Desmarcar o Decoupled Pitch** não serve de jeito nenhum: a vista entorta,
  porque aí o pitch e o roll do jogo entram na view.

O "reconstruir o corpo melhora a interação" que apareceu no meio da caçada era
impressão — **não há bug aqui**, é a mira pela mão. Fica só a ferramenta: o
diagnóstico imprime `varinha: ponta=…, visivel=…, apontando N graus na vertical,
esq=… cm, dir=… cm`. Se um dia a mira sair errada, é essa linha que responde — se
a ponta estiver longe dos **dois** controles, ela está saindo de uma varinha que
não está na sua mão (o `connectAltWand` cria componentes novos; ver "A varinha
volta junto com o corpo").

## Cinemática em primeira pessoa (20/08/2026)

**O desenho do Pande.** Quem cuida das cenas é o `checkCinematic()`, e ele só roda
com "First Person Cinematics" **desligado**: `startCinematic()` devolve a malha do
jogo, guarda a varinha, esconde as mãos e desliga o "seguir a vista";
`endCinematic()` devolve as mãos e religa; e `isInCutscene()` fica true,
bloqueando os controles (`on_xinput_get_state`), o offset de câmera VR e o bloco
do tick. Com a opção **ligada**, ele não trata a cena de outro jeito — ele
simplesmente **sai de cena**. Fora o corpo VR, ninguém assume.

**O que o corpo VR assume quando a opção está ligada** (duas coisas, as duas no
`body.lua`, o `main.lua` fica byte a byte igual ao do Pande nesta parte):

1. `shouldHideBody()` não esconde por `InCinematic` — ali quem tem de aparecer é o
   corpo VR, com o IK dos braços rodando normalmente. Com a opção desligada o
   comportamento é o de sempre: cena em terceira pessoa, corpo escondido.
2. `keepGameMeshHidden()` (timer de 200 ms) reesconde a **malha do jogo**, que a
   cena reexibe: sem isso sobra o personagem do jogo, com cabeça, por cima do corpo
   VR, e reconstruir o corpo vira dois corpos empilhados. Quem esconde continua
   sendo o `hidePlayer` do `main.lua`, com `force = true` para passar pela guarda
   do `isInCinematic`. Sai no log como `Malha do jogo estava visível com o corpo VR
   em cena: escondida (N)`.

**O que fica de fora de propósito.** Alternar terceira ↔ primeira pessoa *no meio
de uma cena* não é sustentado, e foi daí que saíram os problemas de 19/08: a UI
perde o "seguir a vista" (o `disableUIFollowsView` desliga e o religar tem guardas)
e o `isFP` local do `main.lua` sai de sincronia com o checkbox do painel — a malha
fica em primeira pessoa e os controles em terceira. Eu cheguei a escrever remendos
para os dois casos e o Renan mandou removê-los (20/08): o `main.lua` segue o Pande.
Escolha a vista **antes** da cena.

Fica também o `rebuildOnCinematicEnd()` (timer de 200 ms): refaz o corpo na borda
cinemática → jogo, a pedido, com debounce de duas leituras e só a pé. No log:
`Dialogo terminou: refazendo o corpo`.

## Interação que não pega o objeto à sua frente (19/08/2026)

**A mira do jogo sai da VARINHA, não do olhar** (descoberto pelo Renan em jogo): o
`main.lua` chama `wand.getWandTargetLocationAndDirection()` todo tick — ponta da
varinha + `GetUpVector` — e é isso que alimenta o alvo e o plugin SpellCaster
(`helpers/wand.lua:257`). Para interagir, é a mão que aponta.

O que já foi **descartado por medição** neste caso, para não se repetir a caçada:
- **Câmera na cabeça**: `vista x camera do jogo: horizontal=0,5 cm` — a vista está
  praticamente em cima da câmera do jogo.
- **Colisão das cópias**: o sintoma continuou depois de desligada (ela continua
  desligada, que é o certo para uma cópia visual).
- **Pitch da rotação de controle**: fica em `0,0` sempre (Decoupled Pitch do UEVR,
  e o eixo vertical do analógico direito está remapeado para pular/rolar em
  `helpers/input.lua`) — mas isso não é o que escolhe o alvo, então **não é para
  "corrigir"**. Chegou a existir um bloco escrevendo o pitch do HMD em
  `SetControlRotation`; foi removido quando a mira pela varinha apareceu.
- **Desmarcar o Decoupled Pitch** não serve de jeito nenhum: a vista entorta,
  porque aí o pitch e o roll do jogo entram na view.

O "reconstruir o corpo melhora a interação" que apareceu no meio da caçada era
impressão — **não há bug aqui**, é a mira pela mão. Fica só a ferramenta: o
diagnóstico imprime `varinha: ponta=…, visivel=…, apontando N graus na vertical,
esq=… cm, dir=… cm`. Se um dia a mira sair errada, é essa linha que responde — se
a ponta estiver longe dos **dois** controles, ela está saindo de uma varinha que
não está na sua mão (o `connectAltWand` cria componentes novos; ver "A varinha
volta junto com o corpo").

## Cinemática: o desenho é o do Pande, e ele não trata primeira pessoa (20/08/2026)

No perfil original, quem cuida das cenas é o `checkCinematic()` — **e ele só roda
com "First Person Cinematics" DESLIGADO**. Nesse caminho: `startCinematic()`
devolve a malha do jogo (`hidePlayer(false, true)`), guarda a varinha, esconde as
mãos e desliga o "seguir a vista"; `endCinematic()` devolve as mãos e religa o
"seguir a vista"; e `isInCutscene()` fica true, bloqueando os controles
(`on_xinput_get_state`), o offset de câmera VR e o bloco do tick. Com a opção
LIGADA, nada disso acontece — o tratamento de cinemática inteiro sai de cena, e é
por isso que ligar a opção deixa a malha do jogo aparecendo, o attach da UI preso e
o estado de vista fora de sincronia.

Em 19/08 eu tinha escrito três correções para sustentar a opção ligada
(`shouldHideBody` respeitando o `fpCinematic`, `enforceSourceMeshHidden` reescondendo
a malha do jogo e reposição do "seguir a vista"/yaw na troca de vista). **O Renan
mandou remover tudo (20/08/2026) e seguir o Pande exatamente.** Não voltar a
escrever isso: o modo suportado é com a opção **desligada**, cinemática em terceira
pessoa, corpo VR escondido por `InCinematic` no `shouldHideBody`.

O que ficou do lado do corpo é só o `rebuildOnCinematicEnd()` (timer de 200 ms):
refaz o corpo na borda cinemática → jogo, a pedido, com debounce de duas leituras e
só a pé. Sai no log como `Dialogo terminou: refazendo o corpo`.

## Interação que não pega o objeto à sua frente (19/08/2026)

**A mira do jogo sai da VARINHA, não do olhar** (descoberto pelo Renan em jogo): o
`main.lua` chama `wand.getWandTargetLocationAndDirection()` todo tick — ponta da
varinha + `GetUpVector` — e é isso que alimenta o alvo e o plugin SpellCaster
(`helpers/wand.lua:257`). Para interagir, é a mão que aponta.

O que já foi **descartado por medição** neste caso, para não se repetir a caçada:
- **Câmera na cabeça**: `vista x camera do jogo: horizontal=0,5 cm` — a vista está
  praticamente em cima da câmera do jogo.
- **Colisão das cópias**: o sintoma continuou depois de desligada (ela continua
  desligada, que é o certo para uma cópia visual).
- **Pitch da rotação de controle**: fica em `0,0` sempre (Decoupled Pitch do UEVR,
  e o eixo vertical do analógico direito está remapeado para pular/rolar em
  `helpers/input.lua`) — mas isso não é o que escolhe o alvo, então **não é para
  "corrigir"**. Chegou a existir um bloco escrevendo o pitch do HMD em
  `SetControlRotation`; foi removido quando a mira pela varinha apareceu.
- **Desmarcar o Decoupled Pitch** não serve de jeito nenhum: a vista entorta,
  porque aí o pitch e o roll do jogo entram na view.

O "reconstruir o corpo melhora a interação" que apareceu no meio da caçada era
impressão — **não há bug aqui**, é a mira pela mão. Fica só a ferramenta: o
diagnóstico imprime `varinha: ponta=…, visivel=…, apontando N graus na vertical,
esq=… cm, dir=… cm`. Se um dia a mira sair errada, é essa linha que responde — se
a ponta estiver longe dos **dois** controles, ela está saindo de uma varinha que
não está na sua mão (o `connectAltWand` cria componentes novos; ver "A varinha
volta junto com o corpo").

## Cinemática em primeira pessoa (19/08/2026)

Com **"First Person Cinematics"** ligado no painel do perfil, o `main.lua` nem roda
o `checkCinematic()`: ele não troca para terceira pessoa, não esconde as mãos e não
guarda a varinha. Duas coisas tiveram de acompanhar isso do lado do corpo VR:

1. `shouldHideBody()` só esconde por `InCinematic` quando a opção está **desligada**.
   Antes ele escondia sempre, e ligar a opção deixava você sem corpo nenhum no
   diálogo — o pior dos dois mundos, porque o `main.lua` também não colocava a
   malha do jogo de volta.
2. `rebuildOnCinematicEnd()` (timer de 200 ms) **refaz o corpo ao terminar o
   diálogo** — a pedido: sair de uma cena deixa o corpo em estado estranho e
   refazer resolve. Só na borda cinemática → jogo, com o mesmo debounce de duas
   leituras do `rebuildOnDismount` (o `InCinematic` oscila), e **só a pé**:
   refazer em cima de uma criatura faz o corpo nascer fora dela. Sai no log como
   `Dialogo terminou: refazendo o corpo`.
3. `enforceSourceMeshHidden()` (timer de 200 ms) mantém a **malha do jogo**
   escondida enquanto o corpo VR está em cena. O jogo revela essa malha nas
   cinemáticas, e sem o `checkCinematic()` ninguém a reesconde: sobrava o
   personagem do jogo, com cabeça, por cima do corpo VR — e reconstruir o corpo
   virava dois corpos empilhados. Quem esconde continua sendo o `hidePlayer` do
   `main.lua`, chamado com `force = true` para passar pela guarda do
   `isInCinematic`. Em terceira pessoa (`isFP == false`) a função não faz nada: ali
   a malha do jogo é justamente o que se quer ver.

## Corpo que "nasce no chão" ao trocar de nível (24/08/2026)

Sintoma: atravessar uma porta, uma chaminé de Flu ou uma viagem rápida e chegar do
outro lado com o corpo errado — no chão, em pose de referência, sem as pernas
animarem. Clicar em **"Reconstruir corpo"** arrumava.

O que acontece: numa troca de nível o `ik.lua` destrói o rig (ele tem um
`registerPreLevelChangeCallback` que chama `destroyAll()`) e o temporizador dele
recria o corpo **1x por segundo, assim que existir um pawn**. No mundo novo o pawn
aparece antes de o personagem terminar de carregar: `Pawn.Mesh` já é válida, mas as
**malhas modulares** (roupa, luvas, sapatos...) ainda não foram presas a ela e o
esqueleto ainda não devolve os ossos das pernas. O corpo nasce com **uma malha só**,
sem `detectLegBones()` e sem a linha do quadril "de pé" — daí a pose de referência,
a altura errada e as pernas paradas.

Como identificar no `log.txt`: a criação sai como

```
[body] Corpo criado com 1 malha(s)
```

sem as linhas `Pernas: ... ossos, ancoradas em Hips` e `Cintura: ...` que aparecem
numa criação boa (7 malhas, ou 11 com roupa completa).

O conserto é o `rebuildWhenCharacterLoads()` (timer de 200 ms): o
`getCustomIKComponent()` guarda em `builtChildCount` quantas malhas filhas entraram
na criação, e enquanto esse número for **zero** a vigia fica esperando o personagem
carregar. Quando as malhas modulares aparecem, ela refaz o corpo **uma vez** — o
mesmo que o botão fazia. Sai no log como `Personagem terminou de carregar (N
malhas): refazendo o corpo`.

Três travas, todas pelo mesmo motivo das outras seções:

- **Só age no corpo que nasceu incompleto.** Corpo criado com filhas não é
  revisitado; trocar de roupa continua sendo assunto do `rebuildOnGearScreen()`.
- **Só a pé** (`mounts.isWalking()`): refazer montado faz o corpo nascer fora da
  criatura.
- **Teto de 10 reconstruções** (`READY_MAX_REBUILDS`), zerado sempre que um corpo
  nasce completo. Se algum dia existir um personagem sem malha filha nenhuma, a
  vigia desiste em vez de virar laço de destruir/recriar.

## Armadilhas (resumo)

Índice das doze coisas que o `body.lua` não pode voltar a fazer. Cada uma custou
pelo menos uma sessão de teste em jogo, e cada uma tem a explicação longa numa
seção acima. O código só descreve o que faz; o porquê está aqui.

1. **Log.** `uevrUtils.print` só escreve quando o nível é `<= currentLogLevel`, e
   o padrão do perfil é `Error`: `Info` e `Warning` **não** chegam no `log.txt`.
   Erro dentro de `pcall` + aviso em `Warning` = falha invisível. Diagnóstico que
   importa sai por `logMilestone()`. A tabela `debug` **não existe** no Lua do
   UEVR — indexá-la estoura (foi o que quebrou o `setLocomotionMode` em
   14/08/2026). Ver "Diagnóstico: por que o log.txt estava vazio".
2. **A altura do corpo nunca sai do HMD.** Com a câmera atracada à cabeça, o
   componente do HMD fica onde a *vista* está, e a vista é o que nós escrevemos:
   corpo desce → cabeça desce → câmera desce → HMD desce → corpo desce. Sintomas:
   corpo piscando entre duas alturas e o "Ajuste dos olhos" baixando o
   personagem junto. Única exceção: "somente braços", onde `headCameraActive()` é
   `false`. Ver "Altura: agachar no jogo e agachar de verdade".
3. **Atribuir, não perseguir.** Medir a diferença contra uma linha de base
   capturada e devolver a sobra por cima acumula e oscila — a UE desloca a malha
   em relação à cápsula para suavizar degrau, então o número se mexe sozinho ao
   subir ("descalibra quando subo"). Preferir medidas em espaço de componente,
   que não sabem da altura do terreno.
4. **Nunca ler de volta** a transform de um componente preso ao pawn para
   alimentar a lógica que a escreve: o motor gira o pawn no tick dele, que roda
   depois do pré-tick, e a leitura já vem girada. O yaw do corpo é variável
   nossa (`bodyYawState`).
5. **Nada guardado entre o tick e o callback da câmera.** O callback roda depois
   do tick do motor, com o personagem já movido no quadro: posição calculada no
   tick chega atrasada (invisível parado, escancarado na vassoura). E
   `view_index` **nunca é 0** aqui — isto é UE4, o índice vem do
   `EStereoscopicPass` (1 = olho esquerdo, 2 = direito); os dois olhos têm de
   receber o mesmo valor, ou o estéreo desalinha. Ver "Camera na cabeca do corpo".
6. **Sem lerp** no que alimenta a câmera: amortecer não vira suavidade, vira
   atraso na vista. Ver "Sem suavização, e por quê".
7. **Montado, o `pawn` global é a criatura.** O personagem é
   `mounts.getMountPawn(pawn)` (`RiderCharacter`, outro ator). Tudo que sair de
   `pawn.Mesh` ou `pawn.RootComponent` está errado montado — inclusive a conta de
   altura do `ik.lua`, que usa o `CapsuleHalfHeight` da criatura. Onde a conta da
   cápsula não descreve nada, tira-se o `ik.lua` do Z (`coupling = 2`) em vez de
   corrigir depois. Ver "Montaria de criatura".
8. **Um dono só para cada valor.** Dois painéis gravando o mesmo parâmetro, cada
   um com sua cópia salva, é o defeito que faz o valor "voltar sozinho".
   Posição/Rotação são do IK Dev Config; o ajuste dos olhos é um só para tudo (a
   pé, vassoura, criatura). Não criar campo por caso. O mesmo vale entre
   arquivos: uma chave velha no `data/config_default.json` chegou a roubar o id
   do painel e congelar a "Altura dos olhos" (14/08/2026).
9. **Cópias órfãs.** As cópias nascem sem parent (com parent, a criação estoura
   neste jogo) e são presas depois com `K2_AttachTo`, então cada destroy/recria
   deixa uma cópia congelada para trás — daí os "dois corpos" e o z-fighting. Por
   isso existe o `destroyGhostBodies()`. `hide_body = false` cai no `destroyAll()`
   do `ik.lua` e vira laço de destruir/recriar.
10. **Esconder é escala, não visibilidade.** `hide_body` encolhe o esqueleto
    (raiz em 0,001) e "esconder a cabeça" encolhe o osso. Logo, tudo que
    reescreve pose ou transform (`CopyPoseFromSkeletalComponent`,
    `setInitialTransform`, `SetBoneTransformByName`) desfaz o esconder — tem de
    repor depois.
11. **Pitch e roll do rotator da malha não são a frente e o lado do
    personagem.** O `mesh_rotation_offset` do rig está em Yaw **-90**, então o
    pitch do `K2_GetComponentRotation` é a inclinação **lateral** e o roll é a
    da **frente**. Escalar o pitch achando que se endireita a coluna endireita o
    lado (18/08/2026). Antes de mexer em pitch/roll, tirar o yaw e conjugar pelo
    `rigMeshYaw()` — é o mesmo que o "Ajuste fino" já fazia com o `facingYaw`.
12. **Corpo criado antes de o personagem carregar.** Depois de uma troca de nível
    o temporizador do `ik.lua` recria o corpo assim que existe um pawn, e nessa
    janela `Pawn.Mesh` está sozinha: sai um corpo de uma malha só, sem pernas e
    "no chão". Quem espera as malhas modulares e refaz uma vez é o
    `rebuildWhenCharacterLoads()`. Ver "Corpo que nasce no chão ao trocar de
    nível".
