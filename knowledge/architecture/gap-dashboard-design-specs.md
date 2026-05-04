---
created: 2026-04-29
updated: 2026-05-01
---

# Gap Dashboard — Design Specs

Specs extraídas do Figma **MMBR — Definitions — UI** (file `GlbgT4xjflsYTtgtDBQ8Ss`) usando o Figma MCP. Cobre: page shell, tabs, Gaps table, Negative Feedback table, Most Asked table, info banner, sidebar entry.

## Figma Nodes

| Node ID | Tela | Ticket | Link |
|---|---|---|---|
| `570:37691` | Gap Dashboard — Gaps tab (default) | MMBR-52, MMBR-53, MMBR-56, MMBR-58 | [open](https://www.figma.com/design/GlbgT4xjflsYTtgtDBQ8Ss/MMBR---Definitions---UI?node-id=570-37691&m=dev) |
| `568:36224` | Negative feedback tab | MMBR-55 | [open](https://www.figma.com/design/GlbgT4xjflsYTtgtDBQ8Ss/MMBR---Definitions---UI?node-id=568-36224&m=dev) |
| `567:34963` | Most asked questions tab | MMBR-54 (prep landed via #37; full impl pending) | [open](https://www.figma.com/design/GlbgT4xjflsYTtgtDBQ8Ss/MMBR---Definitions---UI?node-id=567-34963&m=dev) |
| `743:6781` | Sidebar item "Gap Dashboard" | MMBR-52 | [open](https://www.figma.com/design/GlbgT4xjflsYTtgtDBQ8Ss/MMBR---Definitions---UI?node-id=743-6781&m=dev) |

## Layout Geral (viewport 1440)

```
┌─────────────┬────────────────────────────────────────────┐
│  Navbar     │  Page (padding 32px)                       │
│  244 px     │  ┌──────────────────────────────────────┐  │
│             │  │ "Gap Dashboard" (title)              │  │
│             │  ├──────────────────────────────────────┤  │
│             │  │ Usage Metrics card (1132 × 168)      │  │
│             │  │  4 cells (263×103 ea), Day/Week/Month│  │
│             │  ├──────────────────────────────────────┤  │
│             │  │ Tabs: Most asked | Neg fb | Gaps     │  │
│             │  ├──────────────────────────────────────┤  │
│             │  │ Active tab content (table)           │  │
│             │  ├──────────────────────────────────────┤  │
│             │  │ Info banner (only on Gaps tab)       │  │
│             │  └──────────────────────────────────────┘  │
└─────────────┴────────────────────────────────────────────┘
```

## Tokens (alinham 100% com `app/globals.css` atual)

| Figma var | Hex | CSS var no projeto |
|---|---|---|
| `Brand-Red` | `#dc1f26` | `--brand`, `--primary` |
| `Stroke/Accent` | `#da1f27` | `--stroke-accent` |
| `Text/Primary` | `#3e3e3e` | `--foreground`, `--text-primary` |
| `Text/Secondary` | `rgba(62,62,62,0.8)` | `--text-secondary` |
| `Surface/Primary` | `#ffffff` | `--surface-primary` |
| `Surface/Secondary` | `#f5f1f0` | `--secondary`, `--surface-secondary` |
| `Surface/Accent Secondary` | `rgba(216,166,166,0.1)` | `--accent`, `--surface-accent-secondary` |
| `Stroke/Default` | `#e3dbd4` | `--border`, `--input` |
| `Background` | `#fafafa` | `--background` |
| `Icon/Accent` | `#dc1f26` | (use `--brand` direto) |

> Nota: a tabela usa cores hardcoded `rgba(26,26,26,0.6)` para texto dim e `rgba(26,26,26,0.08-0.12)` para borders, mas isso é "lixo" do Figma — **mapear para `var(--text-secondary)` e `var(--border)`**.

## Sidebar entry (MMBR-52)

Item "Gap Dashboard" segue exatamente o mesmo padrão do "Documents Panel":

- Active state: `bg: rgba(216,166,166,0.1)`, `border-r-2 border-[#da1f27]`
- Padding: `px-4 py-3` (16/12)
- Icon: 24×24 — design tem annotation **"Change this icon"** → usar Lucide para um ícone melhor (sugestão: `Activity`, `Gauge`, `Sparkles`, ou `AlertCircle`. Confirmar com designer)
- Texto: 16px Regular, `var(--text-primary)`
- Posição no menu: depois de "Documents Panel" (mesma seção, mesmo padrão de proteção super-admin)

**Implementação:** copiar o item de Documents Panel em `components/layout/Sidebar.tsx`, trocar href, label e ícone.

## Page Shell (MMBR-52)

- **Rota:** `/gaps` (em `app/(protected)/gaps/page.tsx`)
- **Layout:** `app/(protected)/gaps/layout.tsx` espelhando `documents/layout.tsx` — guard server-side de role superadmin (redirect `/chat` se não)
- **Page padding:** 32px (`p-8`)
- **Title:** "Gap Dashboard" — 24px (mobile) / 30-36px (desktop) Bold, `var(--text-primary)`
- **Background:** `var(--background, #fafafa)` (default)

## Usage Metrics card

> ⚠️ **Não está nos tickets do sprint atual** — é o ticket MMBR-59 ([TBD][FE] Usage Metrics panel). Mencionado aqui só para reservar o espaço no shell.

- Container: 1132×168, `bg-surface-secondary`, padding 16px, border-radius 8px
- Header (linha 1): "Usage Metrics" (heading 16px Semibold) + buttons Day/Week/Month direita
- Buttons Day/Week/Month: pill `rounded-full`, ativo bg `#dc1f26` text white
- 4 cards (linha 2): cada 263×103, `bg-white`, padding 16px, border-radius 8px
  - Cell title: 14px Regular, `var(--text-secondary)`
  - Cell value: ~36px Bold, `var(--text-primary)`
  - Cell subtitle: 12px Regular, `var(--text-secondary)`

## Tabs (MMBR-53)

- Container: 1116×46, `border-b border-[rgba(26,26,26,0.12)]` → mapear para `var(--border)`
- 3 buttons inline, padding interno top 12px, height 45px
- Texto inativo: 14px Medium, `rgba(26,26,26,0.6)` → `var(--text-secondary)`
- Texto ativo: 14px Medium, `#da1f27` → `var(--stroke-accent)` ou `var(--brand)`
- **Underline ativo:** 80px × 2px, `bg-[#da1f27]`, posicionado bottom da tab
- URL state: `?tab=gaps|negative-feedback|most-asked`, default `gaps`
- Acessibilidade: arrow keys + Enter (mencionado no acceptance criteria)

## Gaps Table (MMBR-56)

- Container: 1114px wide, `bg-white`
- Sem filtro de plant chips nesta versão (vem por contexto do user)

### Header
- Height 48.5px, `bg-[#f8f8f8]` (≈ surface-secondary mais claro), `border-b border-[rgba(26,26,26,0.12)]`
- Header cells: 12px Semibold, `text-[rgba(26,26,26,0.6)]`, **uppercase**, `tracking-[0.3px]`, padding-left 20px

### Body rows
- Height 57px cada, `border-b border-[rgba(26,26,26,0.08)]`
- Cells: 14px Regular, padding-left 20px, vertical center
- Question column: cor `#1a1a1a` (mais escuro)
- Outras colunas: cor `rgba(26,26,26,0.6)` (mais clara — secondary)

### Columns

| # | Column | Width | Notas |
|---|---|---|---|
| 1 | Question | 439.25px | Cor primária, ellipsis + tooltip se overflow |
| 2 | Confidence | 159.39px | Bar 60×6px pill + % text 14px Semibold |
| 3 | Times Asked | 143.48px | Numérico |
| 4 | Plant | 146.98px | String |
| 5 | Last Occurred | 168.89px | Date `YYYY-MM-DD` |
| 6 | (action) | 24px | Autorenew icon — **HIDE neste sprint** |

### Confidence bar (importante)
- Bar container: 60px × 6px, `rounded-full`, `bg-[rgba(26,26,26,0.1)]`
- Fill: pill com cor por threshold (mock data observado):
  - **12% → red `#dc1f26`** (very low)
  - **18% → orange `#f5be4f`** (low)
  - **24% → orange/yellow** (similar)
  - **28% → green** (med — provavelmente `#1d9724`)
- Fill width: proporcional ao % (12% = 7.18px, 18% = 10.8px, 24% = 14.4px, 28% = 16.8px) → fórmula `width = 60 * (percent/100)`
- % text à direita do bar, gap 8px, 14px Semibold cor `#1a1a1a`

### Re-run icon (MMBR-57 — criar mas hidden)
- 24×24 ícone material `autorenew` (Lucide equivalente: `RefreshCw` ou `RotateCw`)
- Posição: 1058px da esquerda (final da linha)
- **Não renderizar nesta versão** (decisão designer) — implementar componente mas controlar via prop/feature flag

## Info Banner (MMBR-58)

- Container: 555×127, `bg-[var(--surface/secondary,#f5f1f0)]`, `border-[0.5px] border-[var(--stroke/default,#e3dbd4)]`, `rounded-[8px]`, `p-4` (16px)
- Layout interno: `flex flex-col items-start`
- Title: 17.5px Semibold, `var(--text/primary)`, line-height 25px
  - **⚠️ Texto "Title" no Figma é placeholder.** Precisa de copy real — proposta: "How to use this dashboard" ou similar. Confirmar com designer.
- Description: 14px Regular, `var(--text/secondary)`, line-height 20px
- Body completo: *"After uploading new documents to SharePoint and updating the knowledge base, select the relevant gaps and re-run them to check if the new content has improved the responses."*
- Aparece **só na tab Gaps** (não na Most Asked nem Negative Feedback)

## Negative Feedback Table (MMBR-55)

- Mesma estrutura visual da Gaps Table
- **Sem** info banner abaixo
- **Sem** filter chips nesta versão (figma mostra mas designer removeu — backend filtra por plant do user)

### Columns

| # | Column | Width | Notas |
|---|---|---|---|
| 1 | Question | ~280px | Cor primária |
| 2 | Response | ~280px | Texto truncado com tooltip |
| 3 | Rating | 90px | 5 stars, filled/empty baseado em valor numérico |
| 4 | Date | 110px | `YYYY-MM-DD` |
| 5 | Plant | 110px | String |

### Rating stars
- 5 stars inline, gap pequeno
- Filled: provavelmente `#f5be4f` (amarelo) ou `--brand`
- Empty: cinza claro `rgba(26,26,26,0.2)` ou similar
- Fonte das stars: provavelmente Material Icons "star" (24×24) ou Lucide `Star` com fill condicional

## Most Asked Questions Table (MMBR-54)

**Direção definida pelo product lead em 2026-04-30** (email reply para product team + frontend). Ainda fora do sprint atual, mas as 3 dimensões de tracking já estão claras:

### 3 dimensões a trackear

1. **Question category** (bucket que já aparece no chat): `process` | `operations` | `maintenance` | `procedure` | `general`
2. **Entity type** (sobre o que é a pergunta): `alarm` | `equipment` | `plant_operations`
3. **Process question flag** — perguntas estilo "qual é o setpoint?" ficam destacadas como categoria própria para análise rápida

### Implementado no PR #37 (frontend prep)

- Types: `QuestionCategory`, `EntityType`, e 3 campos novos em `MostAskedItem` (`category`, `entityType`, `isProcessQuestion`)
- Mock data atualizado com valores plausíveis nas 3 dimensões (incluindo 2 perguntas process-style)
- Tabela com 5 colunas: Question | Category | Entity | Times Asked | Plant
- Badge "Process" inline no texto da pergunta quando `isProcessQuestion = true`

### Pendências antes de implementar UI completa

- **Backend classification.** Quem classifica cada pergunta nessas 3 dimensões? LLM no QAP (backend team) ou regra estática? Sem contrato da API, nada além do prep frontend dá pra fazer.
- **Filter chips/multi-select UI.** Designer precisa passar antes — designer flagou no planning. Multi-select ou single-select por dimensão? AND ou OR entre dimensões? Posicionamento (acima da tabela, sidebar)?

### Columns Figma observadas (versão sem filtros)

- Question | Times Asked (com seta sort) | Plant — adaptado para incluir Category + Entity quando o backend entregar.
- Sem filter chips nesta versão (decisão designer: backend filtra por plant do user automaticamente).

## Mapeamento Figma → CSS no projeto

Valores raw do Figma e como mapear para os tokens já existentes:

| Figma raw | Mapear para |
|---|---|
| `rgba(26,26,26,0.6)` (texto dim) | `var(--text-secondary)` |
| `rgba(26,26,26,0.08-0.12)` (borders) | `var(--border)` |
| `rgba(26,26,26,0.1)` (bar bg) | `var(--secondary)` ou neutral 100 |
| `#1a1a1a` (texto strong) | `var(--text-primary)` |
| `#f8f8f8` (table header bg) | usar `bg-neutral-50` ou nova var |
| `#f5be4f` (warning fill) | nova var `--warning` (não existe ainda) |
| `#dc1f26` (red fill / brand) | `var(--brand)` |

> **Decisão:** valores `#f5be4f` (orange/yellow) e cor verde do confidence bar **não existem** nos tokens atuais. Criar variantes novas: `--confidence-low: #dc1f26`, `--confidence-med: #f5be4f`, `--confidence-good: #1d9724` (verde já usado em password strength) em `app/globals.css`.

## Diferenças entre Figma e o que vamos implementar

| Item | Figma | Decisão designer (planning 2026-04-29) |
|---|---|---|
| Filter by plant chips | Visíveis nas 3 tabs | **Remover** — backend filtra automaticamente |
| Re-run gap icon (autorenew) | Visível em cada linha de Gaps | **Hidden** na v1 (depende do Graph RAG do backend team) |
| Info banner title "Title" | Placeholder | Pedir copy real para designer |
| Sidebar icon (document) | Annotation "Change this icon" | Usar Lucide; pedir designer no follow-up |
| Most Asked Questions tab | Completa no Figma | Container básico só, sem table (rework esperado) |

## Convenções para implementação

1. **Onde colocar arquivos** (segue `web-platform/.claude/CLAUDE.md`):
   - Page: `app/(protected)/gaps/page.tsx`
   - Layout (guard): `app/(protected)/gaps/layout.tsx`
   - Client components: `app/(protected)/gaps/{Name}Client.tsx`
   - Componentes específicos: `components/gaps/*.tsx`
   - Tipos: `types/api.ts` (request/response), `types/domain.ts` (Gap, NegativeFeedback, etc)

2. **Stack:** Next.js App Router, React 19, Tailwind 4, shadcn/ui + base-ui/react, Lucide

3. **Mock-first nas tables:** começar com mock data hardcoded (mesmas linhas do Figma) — quando MMBR-200 e MMBR-206 (backend) chegarem, trocar fonte de dados por fetch.

4. **Server-side pagination** prevista nos tickets — implementar API route handler com paginação desde o início mesmo com mock.

5. **Acessibilidade:** tabs navegáveis por teclado, sort buttons como `<button>`, table com `<thead>/<tbody>` semântico.
