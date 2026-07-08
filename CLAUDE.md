# SeniorsBI — Workspace Claude Code

## O que é

Cockpit operacional **live** da 4Seniors Brasil. Dados vindos do Milldesk (PDFs mensais)
são extraídos por Claude, persistidos no Supabase e exibidos em tempo real no dashboard.

## Estrutura

```
SeniorsBI/
├── Base/                   ← OneDrive: usuário deposita PDFs aqui
│   └── 2026-07/            ← pasta por mês/competência
│       └── *.pdf
└── Workspace/              ← este workspace
    ├── CLAUDE.md           ← este arquivo
    ├── .env.example
    ├── server.js           ← servidor de dev local (porta 5180)
    ├── dashboard/
    │   ├── index.html      ← cockpit live (Supabase JS + Tailwind CDN)
    │   └── vercel.json     ← deploy: seniors-bi.vercel.app
    ├── ingest/
    │   ├── watch.ps1       ← vigia Base/ e loga novos arquivos no Supabase
    │   └── push-mes.ps1    ← envia dados de um mês para o Supabase
    ├── schema/
    │   └── schema.sql      ← schema Supabase (rodar 1x no SQL Editor)
    └── data/
        ├── premissas.json
        ├── skills.json
        ├── tickets.json
        ├── satisfacao.json
        ├── sla.json
        └── meses/
            └── 2026-0X.json
```

## Infraestrutura

| Serviço | URL / referência |
|---|---|
| Supabase | https://ovciyobdpcawghdynqiw.supabase.co |
| GitHub | https://github.com/rsolanjo/SeniorsBI |
| Vercel | https://seniors-bi.vercel.app |
| OneDrive Base | `OneDrive - 4 Seniors Brasil Informatica/Área de Trabalho/SeniorsBI/Base/` |

## Fluxo de novo mês (ex: julho/2026)

1. Usuário deposita PDFs em `Base/2026-07/`
2. `watch.ps1` detecta e registra no `ingest_log` (Supabase)
3. **Claude Code é aberto** → eu leio os PDFs e populo `data/meses/2026-07.json`
4. Rodar: `.\ingest\push-mes.ps1 -Slug 2026-07`
5. Dashboard em `seniors-bi.vercel.app` atualiza automaticamente via Realtime

## Regras

- **Nunca inventar números** — onde faltar dado, usar `null` e registrar em pendências
- **Preços/salários em R$** são estimativas até substituição por dados reais
- **Fonte confiável de horas por cliente** = somar `Indicadores [Nome].pdf` individuais,
  NÃO o "Resumo por local" consolidado (pode vir filtrado por 1 técnico)
- Linguagem: PT-BR

## Setup inicial (fazer 1 vez)

```powershell
# 1. Rodar schema no SQL Editor do Supabase (schema/schema.sql)

# 2. Criar .env a partir do exemplo
Copy-Item .env.example .env
# Preencher SUPABASE_SERVICE_ROLE_KEY (Settings → API no Supabase)

# 3. Carregar todos os meses históricos
foreach ($slug in @('2026-01','2026-02','2026-03','2026-04','2026-05','2026-06')) {
    .\ingest\push-mes.ps1 -Slug $slug
}

# 4. Abrir dashboard local
node server.js   # http://localhost:5180
```
