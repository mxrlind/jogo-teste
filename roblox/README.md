# Reino de Bolso no Roblox

Esta pasta é o porte direto do jogo web para o Roblox. Ele tem as mesmas regras, os mesmos números e a mesma tela 2D com os sprites KayKit. O jogo web (fora desta pasta) não é alterado.

## Jogar no Roblox Studio

1. Abra `ReinoDeBolso.rbxl` no Roblox Studio. Ele é gerado com `rojo build default.project.json -o ReinoDeBolso.rbxl`.
2. Para o progresso ser salvo, vá em **Home > Game Settings > Security** e ligue **Enable Studio Access to API Services**. Isso só funciona depois de publicar o jogo (passo 4).
3. Para trocar os blocos coloridos pelos sprites:
   - Abra **View > Asset Manager > Bulk Import**.
   - Envie `assets/folha-1.png` e `assets/folha-2.png`.
   - Clique com o botão direito em cada imagem e escolha **Copy Asset ID**.
   - Cole os ids em `ReplicatedStorage > Reino > Imagens`.
4. Aperte **Play** para testar. Para colocar no ar, use **File > Publish to Roblox** e, depois, deixe o jogo como público nas configurações.

## Como está organizado

- `src/shared/Reino/Core` e `src/shared/Reino/Data`: as regras do jogo em Luau, traduzidas uma a uma do código JS.
- `src/server/Main.server.luau`:
  - Roda um reino por jogador e salva no DataStore `ReinoDeBolso_v1`.
  - Salva a cada 60 s e também quando o jogador sai.
  - Recebe as ações do cliente e confere cada uma.
- `src/client/Ui.client.luau`: a tela do jogo, com mapa 12x12, barra de recursos e abas.
- `src/client/Atlas.luau` e `assets/`: as folhas de sprites, geradas por `tools/atlas.py`.

## Testes

São rodados a partir desta pasta, com [Lune](https://github.com/lune-org/lune) e [Rojo](https://github.com/rojo-rbx/rojo):

```sh
lune run tests/run     # regras: compara com o jogo web (tests/fixtures.json)
lune run tests/smoke   # place inteiro num Roblox simulado: servidor, tela, cliques e save
```

Para regerar as fixtures a partir do jogo web, rode `TZ=America/Sao_Paulo node roblox/tools/fixtures.mjs`.

## Créditos e licenças

- Sprites: [KayKit](https://kaylousberg.itch.io/) de Kay Lousberg, licença CC0 1.0 (domínio público), renderizados em 2D.
