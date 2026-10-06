# Desenvolvimento

O jogo é HTML + CSS + JavaScript puro: **sem build e sem dependências**. Arte e som com licenças abertas: Kenney (CC0), game-icons.net (CC BY 3.0) e Nunito (OFL). Lista completa em [ASSETS.md](../ASSETS.md).

Prévia do estilo visual: https://mxrlind.github.io/jogo-teste/estilo.html

## Rodar localmente

```bash
npm start            # http://localhost:8080 (Node 18 ou mais novo; nenhuma dependência)
npm test             # testes do motor + varredura de emoji (falha se achar algum)
npm run simulate -- 8 1 --ascend   # bot joga 8 h de jogo (semente 1) e mostra o ritmo
```

Abrir o `index.html` direto pelo `file://` não funciona, porque navegadores bloqueiam módulos ES fora de HTTP. Use `npm start` ou qualquer servidor estático. Com `?debug` na URL, o estado do jogo fica em `window.reino`.

A publicação no GitHub Pages é automática a cada push na `main` (`.github/workflows/pages.yml`).

## Estrutura

```
index.html · styles.css · manifest.webmanifest · sw.js    página, tema, app instalável, offline
estilo.html                                              prévia do estilo visual
src/core/     motor puro, roda no Node (economia, mapa, save, hordas, temporadas...)
src/data/     conteúdo e números de balanceamento
src/ui/       canvas, HUD, painéis, menus, áudio
assets/       sprites, ui, icons, sfx, music, fonts (com as licenças originais)
tests/        testes do motor (node:test)
tools/        servidor, simulador, varredura de emoji, geradores (ASSETS.md, ícones, música)
```

## Documentação

| Arquivo | Conteúdo |
|---|---|
| [GDD.md](../GDD.md) | Documento de design curto: conceito, core loop, progressão, estilo visual e sonoro |
| [EXECUTAR.md](../EXECUTAR.md) | O que depende de uma pessoa: música, publicação, conferência de assets |
| [ASSETS.md](../ASSETS.md) | Cada asset: arquivo, uso, fonte, autor, licença e link |
| [CHANGELOG.md](../CHANGELOG.md) | O que mudou e por quê |
| [ROADMAP.md](../ROADMAP.md) | O que ficou de fora, em ordem de impacto |
| [DIAGNOSTICO.md](DIAGNOSTICO.md) | Diagnóstico: bugs, checklist de jogo completo, pesquisa do gênero |
| [REVISAO-0.3.md](REVISAO-0.3.md) | Revisão de código da 0.3.0: problemas encontrados, plano priorizado e pendências |
| [BALANCEAMENTO.md](BALANCEAMENTO.md) | Fórmulas, constantes e resultados do simulador |
| [ARQUITETURA.md](ARQUITETURA.md) | Código, formato do save, como adicionar conteúdo, debug |
| [ESPECIFICACAO-SISTEMAS.md](ESPECIFICACAO-SISTEMAS.md) | Especificação detalhada de cada sistema |
| [PESQUISA-PARA-DESIGN.md](PESQUISA-PARA-DESIGN.md) · [pesquisa-de-mercado.md](pesquisa-de-mercado.md) | Pesquisa de mercado e como ela virou design |
| [MODELO-DE-NEGOCIO.md](MODELO-DE-NEGOCIO.md) | Monetização ética, validação na Steam, riscos |
